use std::{
    env,
    fs::{self, File, OpenOptions},
    io::{self, Read, Write},
    os::unix::{
        fs::{FileTypeExt, MetadataExt, OpenOptionsExt, PermissionsExt},
        net::{UnixListener, UnixStream},
    },
    path::{Path, PathBuf},
    time::Duration,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Request {
    Capture,
    Demo,
    Quit,
}

impl Request {
    pub fn text(self) -> &'static str {
        match self {
            Self::Capture => "CAPTURE\n",
            Self::Demo => "DEMO\n",
            Self::Quit => "QUIT\n",
        }
    }

    pub fn parse(value: &str) -> Result<Self, String> {
        match value.trim() {
            "CAPTURE" => Ok(Self::Capture),
            "DEMO" => Ok(Self::Demo),
            "QUIT" => Ok(Self::Quit),
            _ => Err("无效的本地控制消息".into()),
        }
    }
}

pub fn runtime_directory() -> Result<PathBuf, String> {
    let path = PathBuf::from(
        env::var_os("XDG_RUNTIME_DIR").ok_or("请在图形会话中运行：XDG_RUNTIME_DIR 未设置")?,
    );
    let metadata = fs::metadata(&path).map_err(|error| error.to_string())?;
    // Socket commands are limited to the logged-in user, never a world-writable directory.
    if !metadata.is_dir()
        || metadata.uid() != unsafe { libc::geteuid() }
        || metadata.mode() & 0o077 != 0
    {
        return Err("XDG_RUNTIME_DIR 必须是当前用户拥有的私有目录（权限 0700）".into());
    }
    Ok(path)
}

pub fn send_existing(directory: &Path, request: Request) -> io::Result<bool> {
    let mut stream = match UnixStream::connect(directory.join("pinmark.sock")) {
        Ok(stream) => stream,
        Err(error)
            if matches!(
                error.kind(),
                io::ErrorKind::NotFound | io::ErrorKind::ConnectionRefused
            ) =>
        {
            return Ok(false)
        }
        Err(error) => return Err(error),
    };
    stream.set_read_timeout(Some(Duration::from_millis(800)))?;
    stream.set_write_timeout(Some(Duration::from_millis(800)))?;
    stream.write_all(request.text().as_bytes())?;
    let mut response = [0_u8; 16];
    let length = stream.read(&mut response)?;
    if !response[..length].starts_with(b"OK") {
        return Err(io::Error::other("现有 Pinmark 进程未接受请求"));
    }
    Ok(true)
}

pub struct Instance {
    pub listener: UnixListener,
    lock: File,
    socket: PathBuf,
    inode: u64,
}

impl Instance {
    pub fn acquire(directory: &Path) -> io::Result<Self> {
        let lock = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .mode(0o600)
            .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC)
            .open(directory.join("pinmark.lock"))?;
        fs2::FileExt::try_lock_exclusive(&lock)?;
        let socket = directory.join("pinmark.sock");
        match fs::symlink_metadata(&socket) {
            Ok(metadata) if metadata.file_type().is_socket() => fs::remove_file(&socket)?,
            Ok(_) => {
                return Err(io::Error::other(
                    "pinmark.sock 已存在且不是 socket，拒绝覆盖",
                ))
            }
            Err(error) if error.kind() == io::ErrorKind::NotFound => (),
            Err(error) => return Err(error),
        }
        let listener = UnixListener::bind(&socket)?;
        fs::set_permissions(&socket, fs::Permissions::from_mode(0o600))?;
        listener.set_nonblocking(true)?;
        let inode = fs::symlink_metadata(&socket)?.ino();
        Ok(Self {
            listener,
            lock,
            socket,
            inode,
        })
    }
}

impl Drop for Instance {
    fn drop(&mut self) {
        if let Ok(metadata) = fs::symlink_metadata(&self.socket) {
            if metadata.file_type().is_socket() && metadata.ino() == self.inode {
                let _ = fs::remove_file(&self.socket);
            }
        }
        let _ = fs2::FileExt::unlock(&self.lock);
    }
}

pub fn read_request(mut stream: UnixStream) -> Result<Request, String> {
    // Accepted sockets can inherit nonblocking mode on some Unix platforms.
    // Make the bounded request read explicit instead of racing the sender.
    stream
        .set_nonblocking(false)
        .map_err(|error| error.to_string())?;
    stream
        .set_write_timeout(Some(Duration::from_millis(100)))
        .map_err(|error| error.to_string())?;
    let deadline = std::time::Instant::now() + Duration::from_millis(250);
    let mut data = Vec::new();
    for _ in 0..64 {
        let remaining = deadline.saturating_duration_since(std::time::Instant::now());
        if remaining.is_zero() {
            return Err("本地控制请求超时".into());
        }
        stream
            .set_read_timeout(Some(remaining))
            .map_err(|error| error.to_string())?;
        let mut byte = [0_u8];
        if stream.read(&mut byte).map_err(|error| error.to_string())? == 0 {
            break;
        }
        data.push(byte[0]);
        if byte[0] == b'\n' {
            break;
        }
    }
    let result = std::str::from_utf8(&data)
        .map_err(|_| "控制消息必须是 UTF-8".to_owned())
        .and_then(Request::parse);
    let _ = stream.write_all(if result.is_ok() { b"OK\n" } else { b"ERROR\n" });
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    static COUNT: AtomicU64 = AtomicU64::new(0);

    fn temp_directory() -> PathBuf {
        let path = env::temp_dir().join(format!(
            "pinmark-test-{}-{}",
            std::process::id(),
            COUNT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path).unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).unwrap();
        path
    }

    #[test]
    fn rejects_unknown_commands() {
        assert_eq!(Request::parse("CAPTURE\n").unwrap(), Request::Capture);
        assert!(Request::parse("CAPTURE;rm -rf").is_err());
    }

    #[test]
    fn instance_is_private_and_exclusive() {
        let path = temp_directory();
        let first = Instance::acquire(&path).unwrap();
        assert_eq!(
            fs::metadata(path.join("pinmark.sock")).unwrap().mode() & 0o777,
            0o600
        );
        assert!(Instance::acquire(&path).is_err());
        drop(first);
        assert!(!path.join("pinmark.sock").exists());
        fs::remove_dir_all(path).unwrap();
    }

    #[test]
    fn stale_socket_can_be_replaced_but_regular_files_cannot() {
        let path = temp_directory();
        let socket = path.join("pinmark.sock");
        let old = UnixListener::bind(&socket).unwrap();
        drop(old);
        drop(Instance::acquire(&path).unwrap());
        fs::write(&socket, b"do not delete").unwrap();
        assert!(Instance::acquire(&path).is_err());
        assert_eq!(fs::read(&socket).unwrap(), b"do not delete");
        fs::remove_dir_all(path).unwrap();
    }

    #[test]
    fn nonblocking_accepted_stream_waits_for_the_request() {
        let (mut client, server) = UnixStream::pair().unwrap();
        server.set_nonblocking(true).unwrap();
        let reader = std::thread::spawn(move || read_request(server));
        std::thread::sleep(Duration::from_millis(25));
        client.write_all(b"CAPTURE\n").unwrap();
        assert_eq!(reader.join().unwrap().unwrap(), Request::Capture);
    }

    #[test]
    fn stalled_request_is_bounded() {
        let (_client, server) = UnixStream::pair().unwrap();
        let started = std::time::Instant::now();
        assert!(read_request(server).is_err());
        assert!(started.elapsed() < Duration::from_secs(2));
    }

    #[test]
    fn request_roundtrip_works() {
        let path = temp_directory();
        let instance = Instance::acquire(&path).unwrap();
        let listener = instance.listener.try_clone().unwrap();
        let worker = std::thread::spawn(move || loop {
            match listener.accept() {
                Ok((stream, _)) => return read_request(stream).unwrap(),
                Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                    std::thread::sleep(Duration::from_millis(5))
                }
                Err(error) => panic!("{error}"),
            }
        });
        assert!(send_existing(&path, Request::Demo).unwrap());
        assert_eq!(worker.join().unwrap(), Request::Demo);
        drop(instance);
        fs::remove_dir_all(path).unwrap();
    }
}
