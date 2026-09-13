use glacier_ui::{GlacierDaemon, window};

const ICONE: &[u8] = include_bytes!("../assets/icone.png");

// Este app NÃO liga `.tray(...)`, embora o scaffold original tivesse — e de
// propósito. No Linux, `tray` e `webview` competem pelo GTK: a bandeja sobe
// numa THREAD PRÓPRIA rodando `gtk::init()` + `gtk::main()` (ver
// glacier-ui/src/tray.rs), e a webview PRECISA rodar na thread principal (é
// onde mora a janela cujo handle ela usa). GTK só aceita ser inicializado
// numa única thread por processo — a segunda chamada panica com "Attempted
// to initialize GTK from two different threads" assim que a primeira janela
// de `open_window({ webview_url = ... })` abre (reproduzido e confirmado
// nesta versão, glacier-ui 0.104.0). Como assistir vídeo é o motivo de
// existir deste app, a bandeja perdeu. Se um dia isso importar mais que a
// webview, a saída no lado do glacier-ui é fazer a bandeja cooperar na
// thread principal (como a própria webview já faz, ver `crate::webview`) em
// vez de ter a sua própria — hoje ela não faz isso.
fn main() -> glacier_ui::iced::Result {
    GlacierDaemon::new()
        .main_window(window::Settings {
            icon: window::icon::from_file_data(ICONE, None).ok(),
            ..Default::default()
        })
        .remember_window_geometry(true)
        .storage_dir(diretorio_de_dados())
        .single_instance("youtube")
        .main(|motor| {
            // Onde `Thumbs.caminho` (views/scripts/thumbs.luau) cacheia
            // thumbnails/avatares baixados da API — semeado ANTES do `init`
            // do script, então `ctx.cache_dir` já existe quando a tela monta.
            motor.define_data(
                "cache_dir",
                &diretorio_de_dados().join("cache").to_string_lossy(),
            );
            if let Err(erro) = motor.register_component("app", "views/app.gv") {
                eprintln!("{erro}");
            }
            motor.set_initial_screen("app");
        })
        .run()
}

fn diretorio_de_dados() -> std::path::PathBuf {
    std::env::var_os("XDG_DATA_HOME")
        .or_else(|| std::env::var_os("APPDATA"))
        .map(std::path::PathBuf::from)
        .or_else(|| {
            std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".local/share"))
        })
        .unwrap_or_else(|| std::path::PathBuf::from("."))
        .join("youtube")
}
