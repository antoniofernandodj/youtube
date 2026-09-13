# YouTube (desktop)

Um cliente desktop de YouTube com [glacier-ui](https://crates.io/crates/glacier-ui):
busca, "em alta", canal e comentários são uma UI nativa própria, consumindo a
**API de Dados do YouTube v3**; assistir abre a página de verdade do YouTube
numa webview nativa embutida (WebKitGTK no Linux).

```
cargo run
```

Na primeira vez, o app pede uma chave de API (tela "Configurar chave de API"
— veja "A chave de API" abaixo).

## Por que duas fontes de vídeo

A API de Dados do YouTube **não devolve URL de stream** — isso é proposital,
pelos termos de uso do YouTube: a API é para metadados (busca, listas,
comentários), não para reprodução de terceiros. Então este app usa a API só
para navegação, e quando chega a hora de assistir, abre
`https://www.youtube.com/watch?v=<id>` — a página de verdade — numa janela de
webview nativa. Foi tentado embutir o IFrame Player oficial (`/embed/<id>`,
a forma "correta" de embutir vídeo do YouTube em outro site) primeiro, mas o
próprio YouTube recusa com "Error 153" — uma verificação de origem/referrer do
lado deles, não uma limitação do motor. A página normal de `/watch` não tem
essa checagem (é só o YouTube sendo o YouTube, dentro de uma janela nativa em
vez de dentro de um navegador) e funciona perfeitamente.

## A chave de API

1. Abra [console.cloud.google.com](https://console.cloud.google.com).
2. Crie um projeto (ou use um existente).
3. **APIs e serviços → Biblioteca** → ative **"YouTube Data API v3"**.
4. **APIs e serviços → Credenciais → Criar credenciais → Chave de API**.
5. Cole a chave na tela de configuração do app (o botão ⚙ no cabeçalho abre
   essa tela de novo, a qualquer momento).

A chave fica só no `storage` local do app (`~/.local/share/youtube/` no
Linux) — nunca no código, nunca em rede além das chamadas à própria API do
Google. A cota gratuita padrão (10.000 unidades/dia) é generosa para uso
pessoal; buscar e navegar consultam a API, mas assistir (a parte mais usada)
não consome cota nenhuma — é só a webview abrindo uma página normal.

## O mapa

```
src/main.rs                     runner: janela única, instância única, semeia `cache_dir`
views/
├── app.gv                      a tela inteira — troca de "página" por `{view}` (config/home/busca/vídeo/canal)
├── scripts/
│   ├── app.luau                handlers (a "vitrine": lê o depósito, escreve o `ctx`)
│   ├── state.luau               o depósito tipado (listas, vídeo/canal atual, paginação)
│   ├── api.luau                 cliente da API de Dados do YouTube v3 (busca/populares/vídeo/canal/comentários)
│   ├── thumbs.luau               cache em disco de thumbnails/avatares (`download_file`, não `fetch`)
│   ├── format.luau               contagens ("1,2 mi"), duração ISO 8601 → "4:13", "há 3 dias"
│   └── glacier.d.luau            tipos dos globais do motor (só para o luau-lsp)
└── styles/
    ├── app.gss                   tokens :root + todas as classes
    └── theme.json                 tema escuro, acento vermelho (marca do YouTube)
```

Não navega entre janelas: é um app de uma janela só, que troca de "página"
girando a chave `ctx.view` (ver AGENTS.md — "muitos apps de uma janela só nem
navegam"). `voltar()` usa uma pilha (`State.historico`) em vez de um valor
fixo, porque busca → vídeo → canal → vídeo (de outro autor) precisa desfazer
na ordem certa.

## Por que thumbnails passam por `download_file`, não `<image>` direto

O motor não busca imagem por URL — `<image source="...">` só lê do disco. E
`fetch` decodifica toda resposta como texto (`String::from_utf8_lossy`), o
que corromperia um JPEG. `download_file(url, caminho)` (Luau) grava os bytes
crus direto no arquivo; `thumbs.luau` cacheia por id (vídeo/canal/autor do
comentário) para não baixar de novo a cada troca de tela.

## Sem bandeja, de propósito

O scaffold original tinha `.tray(...)` (ícone de bandeja, minimizar em vez de
fechar). Foi removido: no Linux, `tray` e `webview` **disputam o GTK** — a
bandeja sobe numa thread própria chamando `gtk::init()`, a webview precisa da
thread principal, e GTK só aceita ser inicializado uma vez por processo. Com
as duas ligadas, o app panica ("Attempted to initialize GTK from two
different threads") assim que a primeira janela de vídeo abre. Como assistir
é o motivo deste app existir, a bandeja perdeu — documentado em
`src/main.rs` e no próprio `glacier-ui` (`src/tray.rs`/`src/webview.rs`,
0.104.0), para quem precisar reavaliar essa troca depois.

## Rodando no Linux sob Wayland

`webview` só funciona sob X11 — o `wry` não suporta Wayland nativo nesta
plataforma. O `GlacierDaemon::run` do glacier-ui já força X11 sozinho antes de
qualquer janela abrir (contanto que `DISPLAY` exista, o que XWayland garante
na maioria das distros) — não precisa fazer nada manual. Dependências de
sistema: `libwebkit2gtk-4.1-dev` para compilar, `libwebkit2gtk-4.1-0` em
runtime.

## Compilar

```sh
make lint   # clippy + type-check dos .luau (luau-lsp)
make run    # roda em debug
make build  # release
```
