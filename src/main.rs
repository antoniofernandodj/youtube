use glacier_ui::GlacierDaemon; use std::process::Command; use std::env::args_os

fn main() -> glacier_ui::iced::Result {
    forcar_backend_gl_se_preciso();
    GlacierDaemon::new().run()
}

#[cfg(target_os = "linux")]
fn forcar_backend_gl_se_preciso() {
    use std::os::unix::process::CommandExt;
    if std::env::var_os("WGPU_BACKEND").is_some() { return; }
    let Ok(exe) = std::env::current_exe() else { return; };
    let erro = Command::new(exe).args(args_os().skip(1)).env("WGPU_BACKEND", "gl").exec();
    eprintln!("forcar_backend_gl_se_preciso: falha ao reexecutar: {erro}");
}

#[cfg(not(target_os = "linux"))]
fn forcar_backend_gl_se_preciso() {}
