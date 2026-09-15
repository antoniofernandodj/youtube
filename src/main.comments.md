
A janela e o aplicativo — ícone, instância única, geometria lembrada e
diretório de dados — estão no cabeçalho de `views/app.gv` (`<screen icon>` e
`<app id="youtube">`). Sem `.main`, o runner abre esse arquivo sozinho, e o
script acha o diretório de dados em `ctx.__data_dir`: o cache de thumbnails
mora em `{__data_dir}/cache` (ver views/scripts/thumbs.luau).

Este app NÃO declara `<tray>`, embora o scaffold original tivesse — e de
propósito. No Linux, `tray` e `webview` competem pelo GTK: a bandeja sobe
numa THREAD PRÓPRIA rodando `gtk::init()` + `gtk::main()` (ver
glacier-ui/src/tray.rs), e a webview PRECISA rodar na thread principal (é
onde mora a janela cujo handle ela usa). GTK só aceita ser inicializado
numa única thread por processo — a segunda chamada panica com "Attempted
to initialize GTK from two different threads" assim que a primeira janela
de `open_window({ webview_url = ... })` abre (reproduzido e confirmado
nesta versão, glacier-ui 0.104.0). Como assistir vídeo é o motivo de
existir deste app, a bandeja perdeu. Se um dia isso importar mais que a
webview, a saída no lado do glacier-ui é fazer a bandeja cooperar na
thread principal (como a própria webview já faz, ver `crate::webview`) em
vez de ter a sua própria — hoje ela não faz isso.

```rust
use glacier_ui::GlacierDaemon;
fn main() -> glacier_ui::iced::Result {
    forcar_backend_gl_se_preciso();
    GlacierDaemon::new().run()
}
```

Contorna um bug conhecido do driver Vulkan da Mesa em GPUs Intel antigas
(Ivy Bridge/Haswell, ~2012-2014 — é exatamente a documentada no próprio
`glacier-ui`, `docs/TROUBLESHOOTING.md`): `<image>` (e outro conteúdo
composto pela GPU) renderiza **preto sólido** com o backend Vulkan padrão
do `wgpu`, mesmo lendo os bytes certos do arquivo — confirmado ao vivo
nesta máquina (thumbnails/avatares do YouTube, todos pretos com Vulkan,
corretos com `WGPU_BACKEND=gl`). O driver **OpenGL** da Mesa para essas
mesmas GPUs é maduro e não sofre disso.



**Por que re-executa o próprio binário em vez de só `set_var` e seguir**:
`set_var` sozinho aqui no início do `main` NÃO chegou a tempo — algo na
cadeia `wgpu`/Vulkan decide o backend antes do ponto em que uma variável
setada de DENTRO do processo já em execução fica visível para quem a lê
(confirmado ao vivo: com o `set_var`, a variável já aparecia correta num
`eprintln!` logo em seguida, e a imagem continuava preta; só
`WGPU_BACKEND=gl` já presente no AMBIENTE antes do processo nascer
funcionou). Recriar o processo do zero (`exec`, que troca a imagem do
processo atual pela mesma, com o ambiente já correto) é a forma de
garantir isso sem depender de onde exatamente essa decisão acontece.

Só mexe em nada se ninguém já decidiu por fora (`.bashrc`,
`environment.d`, etc.) — quem sabe o que está fazendo não é sobrescrito,
e o processo nem re-executa. Numa GPU sem esse bug isto custa, na pior das
hipóteses, abrir mão do Vulkan por nada; correto e devagar é sempre melhor
que errado rápido. Só no Linux: é onde esse driver Mesa específico existe.

```rust
#[cfg(target_os = "linux")]
fn forcar_backend_gl_se_preciso() {
    use std::os::unix::process::CommandExt;

    if std::env::var_os("WGPU_BACKEND").is_some() {
        return;
    }
    let Ok(exe) = std::env::current_exe() else {
        return;
    };
    let erro = std::process::Command::new(exe)
        .args(std::env::args_os().skip(1))
        .env("WGPU_BACKEND", "gl")
        .exec(); // só volta em caso de erro — sucesso substitui este processo
    eprintln!("forcar_backend_gl_se_preciso: falha ao reexecutar: {erro}");
}

#[cfg(not(target_os = "linux"))]
fn forcar_backend_gl_se_preciso() {}
```