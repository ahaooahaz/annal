use std::{
    fmt,
    io::{self, Read, Write},
    os::unix::process::CommandExt,
    process::{Child, Command, ExitStatus, Stdio},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    thread,
    time::{Duration, Instant},
};

use crate::{geometry::Rect, render::decode_png};
use tiny_skia::Pixmap;

#[derive(Debug)]
pub enum TaskError {
    Cancelled,
    Failed(String),
}

impl fmt::Display for TaskError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Cancelled => formatter.write_str("已取消"),
            Self::Failed(message) => formatter.write_str(message),
        }
    }
}

impl std::error::Error for TaskError {}

#[derive(Clone, Default)]
pub struct Runner {
    cancelled: Arc<AtomicBool>,
    child: Arc<Mutex<Option<Child>>>,
}

pub struct CommandOutput {
    pub status: ExitStatus,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

fn read_limited(mut reader: impl Read, limit: u64) -> io::Result<Vec<u8>> {
    let mut data = Vec::new();
    reader.by_ref().take(limit + 1).read_to_end(&mut data)?;
    if data.len() as u64 > limit {
        io::copy(&mut reader, &mut io::sink())?;
        return Err(io::Error::other("外部工具输出过大"));
    }
    Ok(data)
}

impl Runner {
    fn stop_child(child: &mut Child) {
        // Every child is spawned into its own process group. Never kill an
        // unrelated grim/slurp/wl-copy process by name.
        if child.try_wait().ok().flatten().is_none() {
            unsafe {
                libc::kill(-(child.id() as i32), libc::SIGTERM);
            }
            let started = Instant::now();
            while started.elapsed() < Duration::from_millis(400) {
                if child.try_wait().ok().flatten().is_some() {
                    return;
                }
                thread::sleep(Duration::from_millis(10));
            }
            unsafe {
                libc::kill(-(child.id() as i32), libc::SIGKILL);
            }
            let _ = child.wait();
        }
    }

    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::SeqCst);
        if let Some(child) = self.child.lock().unwrap().as_mut() {
            Self::stop_child(child);
        }
    }

    pub fn run(
        &self,
        args: &[String],
        input: Option<Vec<u8>>,
        timeout: Duration,
        collect: bool,
    ) -> Result<CommandOutput, TaskError> {
        if args.is_empty() {
            return Err(TaskError::Failed("没有指定外部工具".into()));
        }
        if self.cancelled.load(Ordering::SeqCst) {
            return Err(TaskError::Cancelled);
        }
        let mut command = Command::new(&args[0]);
        command
            .args(&args[1..])
            .process_group(0)
            .stdin(if input.is_some() {
                Stdio::piped()
            } else {
                Stdio::null()
            })
            .stdout(if collect {
                Stdio::piped()
            } else {
                Stdio::null()
            })
            .stderr(if collect {
                Stdio::piped()
            } else {
                Stdio::null()
            });
        let mut child = command
            .spawn()
            .map_err(|error| TaskError::Failed(format!("无法启动 {}：{error}", args[0])))?;
        let output_reader = child
            .stdout
            .take()
            .map(|stdout| thread::spawn(move || read_limited(stdout, 128 * 1024 * 1024)));
        let error_reader = child
            .stderr
            .take()
            .map(|stderr| thread::spawn(move || read_limited(stderr, 16 * 1024)));
        let input_writer = input.map(|input| {
            let mut stdin = child.stdin.take().unwrap();
            thread::spawn(move || stdin.write_all(&input))
        });
        *self.child.lock().unwrap() = Some(child);
        let started = Instant::now();
        let outcome = loop {
            let mut slot = self.child.lock().unwrap();
            let child = slot.as_mut().unwrap();
            if self.cancelled.load(Ordering::SeqCst) {
                Self::stop_child(child);
                slot.take();
                break Err(TaskError::Cancelled);
            }
            if started.elapsed() >= timeout {
                Self::stop_child(child);
                slot.take();
                break Err(TaskError::Failed(format!("{} 执行超时", args[0])));
            }
            match child.try_wait() {
                Ok(Some(status)) => {
                    slot.take();
                    break Ok(status);
                }
                Ok(None) => (),
                Err(error) => {
                    Self::stop_child(child);
                    slot.take();
                    break Err(TaskError::Failed(error.to_string()));
                }
            }
            drop(slot);
            thread::sleep(Duration::from_millis(10));
        };
        let read_thread = |handle: Option<thread::JoinHandle<io::Result<Vec<u8>>>>| -> Result<Vec<u8>, TaskError> {
            handle.map(|handle| handle.join().map_err(|_| TaskError::Failed("读取外部工具输出失败".into()))?
                .map_err(|error| TaskError::Failed(error.to_string())))
                .unwrap_or_else(|| Ok(Vec::new()))
        };
        let stdout = read_thread(output_reader);
        let stderr = read_thread(error_reader);
        let written = input_writer.map(|handle| {
            handle
                .join()
                .unwrap_or_else(|_| Err(io::Error::other("写入剪贴板失败")))
        });
        let status = outcome?;
        if let Some(Err(error)) = written {
            if status.success() {
                return Err(TaskError::Failed(error.to_string()));
            }
        }
        Ok(CommandOutput {
            status,
            stdout: stdout?,
            stderr: stderr?,
        })
    }
}

#[derive(Debug, Clone)]
pub struct Monitor {
    pub name: String,
    pub rect: Rect,
    pub scale: f64,
}

#[derive(Debug, Clone)]
pub struct Screenshot {
    pub region: Rect,
    pub output: Monitor,
    pub image: Arc<Pixmap>,
}

pub fn parse_selection(text: &str, monitors: &[Monitor]) -> Result<(Rect, Monitor), TaskError> {
    let (geometry, name) = text
        .trim()
        .split_once('|')
        .ok_or_else(|| TaskError::Failed("框选工具返回格式无效".into()))?;
    let region = geometry.parse::<Rect>().map_err(TaskError::Failed)?;
    let monitor = monitors
        .iter()
        .find(|output| output.name == name && output.rect.contains(region))
        .or_else(|| monitors.iter().find(|output| output.rect.contains(region)))
        .ok_or_else(|| {
            TaskError::Failed("请在同一显示器内框选；第一版不支持跨显示器贴图".into())
        })?;
    Ok((region, monitor.clone()))
}

fn grim_args(region: Rect, scale: f64) -> Vec<String> {
    // -g uses global compositor coordinates and already selects the region's
    // intersecting output. grim rejects combining it with -o (or -T).
    vec![
        "grim".into(),
        "-t".into(),
        "png".into(),
        "-l".into(),
        "1".into(),
        "-s".into(),
        scale.to_string(),
        "-g".into(),
        region.geometry(),
        "-".into(),
    ]
}

pub fn capture(
    monitors: Vec<Monitor>,
    runner: Runner,
    replacing_pin: bool,
) -> Result<Screenshot, TaskError> {
    // Only replacements need time for old surfaces to disappear. The first
    // invocation opens the selector immediately.
    if replacing_pin {
        thread::sleep(Duration::from_millis(100));
    }
    let args = ["slurp", "-d", "-f", "%x,%y %wx%h|%o"].map(String::from);
    let output = runner.run(&args, None, Duration::from_secs(600), true)?;
    if !output.status.success() {
        if output.stderr.is_empty() {
            return Err(TaskError::Cancelled);
        }
        return Err(TaskError::Failed(
            String::from_utf8_lossy(&output.stderr).trim().to_owned(),
        ));
    }
    let selected = String::from_utf8(output.stdout)
        .map_err(|_| TaskError::Failed("框选结果不是文本".into()))?;
    let (region, monitor) = parse_selection(&selected, &monitors)?;
    thread::sleep(Duration::from_millis(60));
    let args = grim_args(region, monitor.scale);
    let output = runner.run(&args, None, Duration::from_secs(15), true)?;
    if !output.status.success() {
        return Err(TaskError::Failed(format!(
            "截图失败：{}",
            String::from_utf8_lossy(&output.stderr).trim()
        )));
    }
    let image = decode_png(&output.stdout).map_err(TaskError::Failed)?;
    Ok(Screenshot {
        region,
        output: monitor,
        image: Arc::new(image),
    })
}

pub fn copy_png(png: Vec<u8>) -> Result<(), TaskError> {
    // Do not use --foreground or --paste-once. wl-copy's background provider
    // preserves the image after Pinmark closes, including XWayland clients.
    // Its stdout/stderr are not piped, so a daemon child cannot hold EOF open.
    let result = Runner::default().run(
        &["wl-copy".into(), "--type".into(), "image/png".into()],
        Some(png),
        Duration::from_secs(15),
        false,
    )?;
    if result.status.success() {
        Ok(())
    } else {
        Err(TaskError::Failed(
            "复制失败，请检查 wl-copy 和 Wayland 剪贴板".into(),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn monitor() -> Monitor {
        Monitor {
            name: "eDP-1".into(),
            rect: Rect::new(0, 0, 1920, 1080).unwrap(),
            scale: 1.0,
        }
    }

    #[test]
    fn selection_matches_output_and_rejects_cross_output() {
        let (region, output) = parse_selection("20,40 300x200|eDP-1\n", &[monitor()]).unwrap();
        assert_eq!(region.x, 20);
        assert_eq!(output.name, "eDP-1");
        assert!(parse_selection("1900,20 100x100|eDP-1", &[monitor()]).is_err());
        assert!(parse_selection("20,40 300x200", &[monitor()]).is_err());
    }

    #[test]
    fn grim_region_capture_never_adds_an_output_or_toplevel_selector() {
        let args = grim_args(Rect::new(20, 40, 300, 200).unwrap(), 1.0);
        assert_eq!(
            args,
            [
                "grim",
                "-t",
                "png",
                "-l",
                "1",
                "-s",
                "1",
                "-g",
                "20,40 300x200",
                "-"
            ]
        );
        assert!(!args.iter().any(|arg| matches!(arg.as_str(), "-o" | "-T")));
    }

    #[test]
    fn grim_region_capture_preserves_negative_coordinates_and_fractional_scale() {
        let args = grim_args(Rect::new(-1800, -100, 400, 300).unwrap(), 1.5);
        assert_eq!(args.iter().filter(|arg| *arg == "-g").count(), 1);
        assert_eq!(
            args.windows(2).find(|pair| pair[0] == "-g").unwrap()[1],
            "-1800,-100 400x300"
        );
        assert_eq!(
            args.windows(2).find(|pair| pair[0] == "-s").unwrap()[1],
            "1.5"
        );
        assert_eq!(args.last().unwrap(), "-");
    }

    #[test]
    fn process_runner_collects_output_without_shell() {
        let result = Runner::default()
            .run(
                &["/bin/echo".into(), "a; b".into()],
                None,
                Duration::from_secs(2),
                true,
            )
            .unwrap();
        assert!(result.status.success());
        assert_eq!(result.stdout, b"a; b\n");
    }

    #[test]
    fn cancelled_runner_never_launches_a_process() {
        let runner = Runner::default();
        runner.cancel();
        assert!(matches!(
            runner.run(
                &["/bin/echo".into(), "no".into()],
                None,
                Duration::from_secs(1),
                true
            ),
            Err(TaskError::Cancelled)
        ));
    }

    #[test]
    fn background_provider_does_not_hold_output_pipe_open() {
        let started = Instant::now();
        let result = Runner::default()
            .run(
                &["/bin/sh".into(), "-c".into(), "sleep 0.5 & exit 0".into()],
                None,
                Duration::from_secs(2),
                false,
            )
            .unwrap();
        assert!(result.status.success());
        assert!(started.elapsed() < Duration::from_millis(400));
    }

    #[test]
    fn empty_command_is_rejected() {
        assert!(Runner::default()
            .run(&[], None, Duration::from_secs(1), true)
            .is_err());
    }

    #[test]
    fn process_timeout_is_bounded() {
        let started = Instant::now();
        let result = Runner::default().run(
            &["/bin/sleep".into(), "5".into()],
            None,
            Duration::from_millis(50),
            true,
        );
        assert!(matches!(result, Err(TaskError::Failed(_))));
        assert!(started.elapsed() < Duration::from_secs(2));
    }
}
