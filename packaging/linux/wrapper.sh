#!/bin/sh
# Instalado como /usr/bin/youtube pelo .deb.
#
# O programa de verdade fica em /usr/share/youtube/, junto do views/,
# porque o app resolve os templates contra o DIRETÓRIO DE TRABALHO — é o que dá
# o hot-reload em dev. Sem este `cd`, rodar `youtube` de qualquer pasta
# abriria uma janela vazia, sem mensagem de erro nenhuma.
cd /usr/share/youtube || exit 1
exec ./youtube "$@"
