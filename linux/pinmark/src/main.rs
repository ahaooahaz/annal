#[cfg(target_os = "linux")]
mod cli;

#[cfg(target_os = "linux")]
fn main() {
    cli::main();
}

#[cfg(not(target_os = "linux"))]
fn main() {
    eprintln!("Pinmark 是 Linux Wayland 工具；此平台可以运行核心单元测试，但不能启动界面。");
    std::process::exit(1);
}
