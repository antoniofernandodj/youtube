#!/bin/sh
# Instalador do youtube para Linux (pacote portátil .tar.gz).
#
# Padrão: `~/.local` — sem sudo, sem tocar em nada do sistema. `--sistema`
# instala em `/usr/local` para todos os usuários.
#
#     <prefixo>/share/youtube/          o binário real e o views/
#     <prefixo>/bin/youtube             um wrapper de 3 linhas
#     <prefixo>/share/applications/*.desktop     a entrada no menu
#
# ## Por que um wrapper, e não o binário direto em bin/
#
# O app resolve `views/` contra o DIRETÓRIO DE TRABALHO — é o que dá o
# hot-reload em dev, onde se roda `cargo run` da raiz do projeto. Instalado, o
# diretório de trabalho é onde a pessoa estiver: rodar `youtube` de
# `~/Documentos` abriria uma janela vazia, sem nenhuma mensagem de erro.
#
# O wrapper faz `cd` para a pasta de instalação antes de executar. Três linhas
# resolvem o problema para o terminal, para o menu de aplicativos e para um
# atalho — sem exigir uma linha sequer de Rust no projeto. O `.desktop` também
# leva `Path=`, que é a mesma ideia pelo lado do menu.
set -eu

APP=youtube
ORIGEM=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PREFIXO="$HOME/.local"
SUDO=""
ACAO=instalar

for arg in "$@"; do
    case "$arg" in
        --sistema)   PREFIXO=/usr/local; [ "$(id -u)" = 0 ] || SUDO=sudo ;;
        --remover)   ACAO=remover ;;
        --prefixo=*) PREFIXO=${arg#--prefixo=} ;;
        -h|--help)
            cat <<AJUDA
uso: ./instalar.sh [opções]

  (sem opção)     instala em ~/.local          (não pede sudo)
  --sistema       instala em /usr/local        (pede sudo)
  --prefixo=DIR   instala em DIR
  --remover       remove o que foi instalado
AJUDA
            exit 0 ;;
        *) echo "opção desconhecida: $arg (use --help)" >&2; exit 2 ;;
    esac
done

WRAPPER="$PREFIXO/bin/$APP"
COMPARTILHADO="$PREFIXO/share/$APP"
DESKTOP="$PREFIXO/share/applications/$APP.desktop"

if [ "$ACAO" = remover ]; then
    $SUDO rm -f  "$WRAPPER" "$DESKTOP"
    $SUDO rm -rf "$COMPARTILHADO"
    command -v update-desktop-database >/dev/null 2>&1 &&
        $SUDO update-desktop-database "$PREFIXO/share/applications" 2>/dev/null || true
    echo "$APP removido de $PREFIXO."
    exit 0
fi

# Um pacote incompleto instala e só falha ao abrir, numa janela vazia. Melhor
# recusar aqui, onde ainda dá para dizer o que faltou.
[ -f "$ORIGEM/$APP" ] || { echo "ERRO: $APP não está nesta pasta." >&2; exit 1; }
[ -d "$ORIGEM/views" ] || {
    echo "ERRO: a pasta 'views' não está nesta pasta — pacote incompleto." >&2
    exit 1
}

$SUDO mkdir -p "$PREFIXO/bin" "$COMPARTILHADO" "$PREFIXO/share/applications"
$SUDO install -m 755 "$ORIGEM/$APP" "$COMPARTILHADO/$APP"
# `views/` é espelhado, não mesclado: um arquivo que sumiu entre versões não
# pode ficar para trás e continuar sendo carregado como se ainda existisse.
$SUDO rm -rf "$COMPARTILHADO/views"
$SUDO cp -r "$ORIGEM/views" "$COMPARTILHADO/views"

$SUDO sh -c "cat > '$WRAPPER'" <<AREA
#!/bin/sh
# Gerado pelo instalador do $APP. O \`cd\` é o que faz o app achar views/.
cd "$COMPARTILHADO" || exit 1
exec ./$APP "\$@"
AREA
$SUDO chmod 755 "$WRAPPER"

$SUDO sh -c "cat > '$DESKTOP'" <<AREA
[Desktop Entry]
Type=Application
Name=Youtube
Exec=$WRAPPER
Path=$COMPARTILHADO
Terminal=false
Categories=Utility;
AREA

command -v update-desktop-database >/dev/null 2>&1 &&
    $SUDO update-desktop-database "$PREFIXO/share/applications" 2>/dev/null || true

echo "Pronto."
echo
echo "  programa: $COMPARTILHADO/$APP"
echo "  atalho  : $WRAPPER"
echo

case ":$PATH:" in
    *":$PREFIXO/bin:"*) echo "Rode '$APP', ou procure no menu de aplicativos." ;;
    *) echo "AVISO: $PREFIXO/bin não está no PATH. Rode '$WRAPPER', ou acrescente:"
       echo "       export PATH=\"$PREFIXO/bin:\$PATH\"" ;;
esac
