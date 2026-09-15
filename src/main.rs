use glacier_ui::GlacierDaemon;

fn main() -> glacier_ui::iced::Result {
    forcar_backend_gl_se_preciso();
    GlacierDaemon::new().run()
}

#[cfg(target_os = "linux")]
fn forcar_backend_gl_se_preciso() {
    use std::os::unix::process::CommandExt;
    if std::env::var_os("WGPU_BACKEND").is_some() { return; }
    let Ok(exe) = std::env::current_exe() else { return; };
    let erro = std::process::Command::new(exe)
        .args(std::env::args_os().skip(1))
        .env("WGPU_BACKEND", "gl")
        .exec(); // só volta em caso de erro — sucesso substitui este processo
    eprintln!("forcar_backend_gl_se_preciso: falha ao reexecutar: {erro}");
}

#[cfg(not(target_os = "linux"))]
fn forcar_backend_gl_se_preciso() {}
