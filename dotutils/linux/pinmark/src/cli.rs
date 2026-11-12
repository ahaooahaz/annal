use std::{env, os::unix::fs::PermissionsExt, path::PathBuf, thread, time::Duration};

use pinmark::ipc::{self, Instance, Request};

fn command_exists(name: &str) -> bool {
    env::var_os("PATH").is_some_and(|path| {
        env::split_paths(&path).any(|directory| {
            let candidate = directory.join(name);
            candidate.is_file()
                && candidate
                    .metadata()
                    .is_ok_and(|metadata| metadata.permissions().mode() & 0o111 != 0)
        })
    })
}

fn help() {
    println!("Pinmark {} — 原生 Wayland 截图贴图与标注\n\n用法：\n  pinmark           框选截图，原位贴图；再次运行重新框选\n  pinmark --demo    使用生成的测试图，不截取屏幕\n  pinmark --check   只检查依赖与 Wayland 协议\n  pinmark --quit    关闭当前 Pinmark\n  pinmark --version 显示版本\n\n工具栏：矩形、箭头、复制、另存为、关闭。未选工具时左键拖动，\n再次点击已选工具取消选中；右键撤销，点击贴图后 Esc 关闭。\n复制成功后自动退出；另存为使用系统文件选择器并保留贴图。\n只支持 Wayland layer-shell；需要 grim、slurp、wl-copy 和桌面 Portal。", env!("CARGO_PKG_VERSION"));
}

fn check() -> bool {
    let mut success = true;
    for tool in ["grim", "slurp", "wl-copy"] {
        let available = command_exists(tool);
        println!("{tool}: {}", if available { "OK" } else { "MISSING" });
        success &= available;
    }
    match ipc::runtime_directory() {
        Ok(path) => println!("XDG_RUNTIME_DIR: {} (private)", path.display()),
        Err(error) => {
            println!("运行目录: {error}");
            success = false;
        }
    }
    match pinmark::ui::check_protocols() {
        Ok(globals) => {
            for (interface, minimum) in [
                ("zwlr_layer_shell_v1", 4),
                ("wp_viewporter", 1),
                ("wl_shm", 1),
                ("zwlr_screencopy_manager_v1", 1),
            ] {
                let version = globals
                    .iter()
                    .find(|(name, _)| name == interface)
                    .map(|(_, version)| *version);
                let available = version.is_some_and(|version| version >= minimum);
                println!(
                    "{interface}: {}",
                    version.map_or("MISSING".into(), |version| format!("v{version}"))
                );
                success &= available;
            }
        }
        Err(error) => {
            println!("Wayland: {error}（请在图形会话终端运行）");
            success = false;
        }
    }
    match pinmark::save::chooser_version() {
        Ok(version) => println!("org.freedesktop.portal.FileChooser: v{version}"),
        Err(error) => {
            println!("FileChooser: {error}");
            success = false;
        }
    }
    success
}

fn execute(request: Request) -> Result<(), Box<dyn std::error::Error>> {
    let runtime: PathBuf = ipc::runtime_directory()?;
    if ipc::send_existing(&runtime, request)? {
        return Ok(());
    }
    if request == Request::Quit {
        return Ok(());
    }
    if env::var_os("WAYLAND_DISPLAY").is_none() {
        return Err("请在 Wayland 图形会话中启动 Pinmark".into());
    }
    let tools: &[&str] = if request == Request::Demo {
        &["wl-copy"]
    } else {
        &["grim", "slurp", "wl-copy"]
    };
    for tool in tools {
        if !command_exists(tool) {
            return Err(format!("缺少 {tool}；请先安装 grim slurp wl-clipboard").into());
        }
    }
    let instance = match Instance::acquire(&runtime) {
        Ok(instance) => instance,
        Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
            for _ in 0..20 {
                thread::sleep(Duration::from_millis(25));
                if ipc::send_existing(&runtime, request)? {
                    return Ok(());
                }
            }
            return Err("另一个 Pinmark 正在启动，请稍后重试".into());
        }
        Err(error) => return Err(error.into()),
    };
    pinmark::ui::run(&instance, request)
}

pub fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let request = match args.as_slice() {
        [] => Request::Capture,
        [arg] if arg == "--demo" => Request::Demo,
        [arg] if arg == "--quit" => Request::Quit,
        [arg] if arg == "--check" => {
            if !check() {
                std::process::exit(1);
            }
            return;
        }
        [arg] if arg == "--version" => {
            println!("pinmark {}", env!("CARGO_PKG_VERSION"));
            return;
        }
        [arg] if arg == "--help" || arg == "-h" => {
            help();
            return;
        }
        _ => {
            help();
            std::process::exit(2);
        }
    };
    if let Err(error) = execute(request) {
        eprintln!("Pinmark：{error}");
        std::process::exit(1);
    }
}
