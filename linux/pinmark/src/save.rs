use std::{
    fs::{self, OpenOptions},
    io::Write,
    os::unix::fs::OpenOptionsExt,
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};

use crate::backend::TaskError;

static SERIAL: AtomicU64 = AtomicU64::new(0);

pub fn file_uri_path(uri: &str) -> Result<PathBuf, TaskError> {
    let url = url::Url::parse(uri)
        .map_err(|error| TaskError::Failed(format!("无效的保存位置：{error}")))?;
    if url.query().is_some() || url.fragment().is_some() {
        return Err(TaskError::Failed("保存位置不能包含 URI 查询或片段".into()));
    }
    url.to_file_path()
        .map_err(|_| TaskError::Failed("只能另存到本地文件，不能上传到网络地址".into()))
}

pub fn default_filename() -> String {
    let mut buffer = [0_u8; 64];
    let mut local: libc::tm = unsafe { std::mem::zeroed() };
    unsafe {
        let now = libc::time(std::ptr::null_mut());
        if !libc::localtime_r(&now, &mut local).is_null() {
            let length = libc::strftime(
                buffer.as_mut_ptr().cast(),
                buffer.len(),
                c"Pinmark-%Y%m%d-%H%M%S.png".as_ptr(),
                &local,
            );
            if length > 0 {
                return String::from_utf8_lossy(&buffer[..length]).into_owned();
            }
        }
    }
    "Pinmark.png".into()
}

pub fn write_png_atomic(path: &Path, data: &[u8]) -> Result<(), TaskError> {
    if !data.starts_with(b"\x89PNG\r\n\x1a\n") {
        return Err(TaskError::Failed("不能保存无效的 PNG 数据".into()));
    }
    let parent = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .ok_or_else(|| TaskError::Failed("保存位置缺少目录".into()))?;
    let serial = SERIAL.fetch_add(1, Ordering::Relaxed);
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let temporary = parent.join(format!(
        ".pinmark-{}-{timestamp}-{serial}.tmp",
        std::process::id()
    ));
    let result = (|| -> std::io::Result<()> {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC)
            .open(&temporary)?;
        file.write_all(data)?;
        file.sync_all()?;
        drop(file);
        // The destination is exactly the path approved in the native dialog.
        // Never append a suffix and accidentally replace an unconfirmed file.
        fs::rename(&temporary, path)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result.map_err(|error| TaskError::Failed(format!("另存失败（{}）：{error}", path.display())))
}

#[cfg(target_os = "linux")]
mod portal {
    use super::{default_filename, file_uri_path, write_png_atomic};
    use crate::{backend::TaskError, geometry::Markings, render};
    use futures_util::StreamExt;
    use std::{collections::HashMap, path::PathBuf, time::Duration};
    use tokio::sync::oneshot;
    use zbus::{
        zvariant::{OwnedObjectPath, OwnedValue, Value},
        Connection, Proxy,
    };

    const SERVICE: &str = "org.freedesktop.portal.Desktop";
    const DESKTOP: &str = "/org/freedesktop/portal/desktop";
    const CHOOSER: &str = "org.freedesktop.portal.FileChooser";
    const REQUEST: &str = "org.freedesktop.portal.Request";

    fn failed(error: impl std::fmt::Display) -> TaskError {
        TaskError::Failed(format!("系统另存为对话框失败：{error}"))
    }

    pub fn request_path(sender: &str, token: &str) -> String {
        format!(
            "{DESKTOP}/request/{}/{}",
            sender.trim_start_matches(':').replace('.', "_"),
            token
        )
    }

    async fn choose_file(
        filename: &str,
        mut cancel: oneshot::Receiver<()>,
    ) -> Result<Option<PathBuf>, TaskError> {
        let connection = tokio::select! {
            _ = &mut cancel => return Err(TaskError::Cancelled),
            result = tokio::time::timeout(Duration::from_secs(10), Connection::session()) => result.map_err(failed)?.map_err(failed)?,
        };
        let token = format!(
            "pinmark_{}_{}",
            std::process::id(),
            super::SERIAL.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
        );
        let sender = connection
            .unique_name()
            .ok_or_else(|| failed("D-Bus 未提供会话名称"))?;
        let path = request_path(sender.as_str(), &token);
        let request = Proxy::new(&connection, SERVICE, path.as_str(), REQUEST)
            .await
            .map_err(failed)?;
        // Subscribe before requesting the dialog: an immediate cancellation or
        // a fast response must not be lost between method return and subscribe.
        let mut responses = request.receive_signal("Response").await.map_err(failed)?;
        let chooser = Proxy::new(&connection, SERVICE, DESKTOP, CHOOSER)
            .await
            .map_err(failed)?;
        let filters = vec![("PNG 图片", vec![(0_u32, "*.png")])];
        let options: HashMap<&str, Value<'_>> = HashMap::from([
            ("handle_token", Value::from(token.as_str())),
            ("current_name", Value::from(filename)),
            ("modal", Value::from(false)),
            ("filters", Value::new(filters)),
        ]);
        // Layer-shell surfaces cannot be exported as xdg toplevel parents.
        // The viewer is temporarily unmapped, so an unparented dialog is safe.
        let body = ("", "Pinmark — 另存为 PNG", options);
        let handle: OwnedObjectPath = tokio::select! {
            _ = &mut cancel => return Err(TaskError::Cancelled),
            result = tokio::time::timeout(Duration::from_secs(15), chooser.call("SaveFile", &body)) => result.map_err(failed)?.map_err(failed)?,
        };
        if handle.as_str() != path {
            let unexpected = Proxy::new(&connection, SERVICE, handle, REQUEST)
                .await
                .map_err(failed)?;
            let _ = unexpected.call::<_, _, ()>("Close", &()).await;
            return Err(failed("文件选择器返回了不匹配的请求标识"));
        }
        let response = tokio::select! {
            _ = &mut cancel => {
                let _ = tokio::time::timeout(Duration::from_secs(2), request.call::<_, _, ()>("Close", &())).await;
                return Err(TaskError::Cancelled);
            }
            _ = tokio::time::sleep(Duration::from_secs(1800)) => {
                let _ = tokio::time::timeout(Duration::from_secs(2), request.call::<_, _, ()>("Close", &())).await;
                return Err(failed("对话框等待超时"));
            }
            response = responses.next() => response.ok_or_else(|| failed("文件选择器响应连接已关闭"))?,
        };
        let (status, mut results): (u32, HashMap<String, OwnedValue>) =
            response.body().deserialize().map_err(failed)?;
        match status {
            0 => {
                let value = results
                    .remove("uris")
                    .ok_or_else(|| failed("未返回保存位置"))?;
                let uris: Vec<String> = value.try_into().map_err(failed)?;
                if uris.len() != 1 {
                    return Err(failed("必须选择一个保存位置"));
                }
                Ok(Some(file_uri_path(&uris[0])?))
            }
            1 => Ok(None),
            _ => Err(failed("文件选择器未能完成请求")),
        }
    }

    pub fn save_as(
        image: &tiny_skia::Pixmap,
        markings: &Markings,
        cancel: oneshot::Receiver<()>,
    ) -> Result<Option<PathBuf>, TaskError> {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .map_err(failed)?;
        let path = runtime.block_on(choose_file(&default_filename(), cancel))?;
        if let Some(path) = &path {
            let png = render::export_png(image, markings).map_err(TaskError::Failed)?;
            write_png_atomic(path, &png)?;
        }
        Ok(path)
    }

    pub fn chooser_version() -> Result<u32, TaskError> {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .map_err(failed)?;
        runtime.block_on(async {
            tokio::time::timeout(Duration::from_secs(10), async {
                let connection = Connection::session().await.map_err(failed)?;
                let proxy = Proxy::new(&connection, SERVICE, DESKTOP, CHOOSER)
                    .await
                    .map_err(failed)?;
                proxy.get_property("version").await.map_err(failed)
            })
            .await
            .map_err(failed)?
        })
    }

    #[cfg(test)]
    mod tests {
        use super::*;
        #[test]
        fn response_subscription_path_uses_the_portal_token_contract() {
            assert_eq!(
                request_path(":1.234", "pinmark_12_3"),
                "/org/freedesktop/portal/desktop/request/1_234/pinmark_12_3"
            );
        }
    }
}

#[cfg(target_os = "linux")]
pub use portal::{chooser_version, save_as};

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    fn directory() -> PathBuf {
        let path = std::env::temp_dir().join(format!(
            "pinmark-save-test-{}-{}",
            std::process::id(),
            SERIAL.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path).unwrap();
        path
    }
    fn png() -> Vec<u8> {
        tiny_skia::Pixmap::new(2, 2).unwrap().encode_png().unwrap()
    }

    #[test]
    fn save_paths_decode_unicode_and_spaces_but_reject_remote_destinations() {
        assert_eq!(
            file_uri_path("file:///tmp/%E6%88%AA%E5%9B%BE%20a.png").unwrap(),
            PathBuf::from("/tmp/截图 a.png")
        );
        assert!(file_uri_path("https://example.com/image.png").is_err());
        assert!(file_uri_path("file://elsewhere/image.png").is_err());
        assert!(file_uri_path("file:///tmp/a.png?unexpected").is_err());
    }

    #[test]
    fn save_creates_private_png_and_atomically_replaces_confirmed_file() {
        let dir = directory();
        let path = dir.join("截图 a.png");
        fs::write(&path, b"old image").unwrap();
        let bytes = png();
        write_png_atomic(&path, &bytes).unwrap();
        assert_eq!(fs::read(&path).unwrap(), bytes);
        assert_eq!(
            fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert_eq!(fs::read_dir(&dir).unwrap().count(), 1);
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn failed_save_keeps_existing_destination_and_removes_temporary_file() {
        let dir = directory();
        let destination = dir.join("existing-directory");
        fs::create_dir(&destination).unwrap();
        fs::write(destination.join("keep"), b"keep").unwrap();
        assert!(write_png_atomic(&destination, &png()).is_err());
        assert_eq!(fs::read(destination.join("keep")).unwrap(), b"keep");
        assert_eq!(fs::read_dir(&dir).unwrap().count(), 1);
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn save_does_not_change_the_confirmed_filename_or_write_invalid_data() {
        let dir = directory();
        let path = dir.join("no-extension");
        write_png_atomic(&path, &png()).unwrap();
        assert!(!dir.join("no-extension.png").exists());
        assert!(write_png_atomic(&path, b"invalid").is_err());
        assert!(fs::read(&path).unwrap().starts_with(b"\x89PNG"));
        assert!(default_filename().ends_with(".png"));
        fs::remove_dir_all(dir).unwrap();
    }
}
