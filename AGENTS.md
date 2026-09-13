# AGENTS.md

Instruções para quem trabalha neste projeto — pessoa ou agente. O que está aqui
foi medido, não suposto: cada número veio de um app real numa GPU integrada de
2012 (Intel HD 2500), que é onde as diferenças aparecem. Numa máquina moderna
boa parte disto some — o que não muda é a ordem de grandeza entre as causas.

**Por onde começar**, se você nunca escreveu um app glacier:

| se você quer | leia |
|---|---|
| entender como o app funciona (leia isto primeiro) | *Como um app glacier funciona* |
| saber onde cada arquivo vai | *A anatomia do projeto* |
| copiar algo que já roda | *Um app inteiro, comentado* |
| achar a tag certa para uma tela | *O catálogo de widgets* |
| saber os atributos e o formato de dado de uma tag | a entrada dela no catálogo |
| escrever ou arrumar um `.gss` | *A folha de estilo, por inteiro* |
| trocar as cores do app | *O `theme.json`* |
| escrever o comportamento | *Como escrever os scripts* |
| saber o que dá para chamar do script | *Todas as funções da camada Luau* |
| expor uma função ou objeto Rust ao script | *Expor uma função ou objeto Rust ao `<script>`* |
| que a tela não fique lenta | *O que custa num quadro* e as três regras |
| descobrir por que algo não aparece | *Armadilhas que já custaram tempo* |
| conferir antes de entregar | *Antes de dizer que está pronto* |

A regra que resume o resto: **o `.gv` diz o que existe, o `.gss` diz como
aparece, o script diz o que acontece.** Quase todo bug de layout deste motor é
alguém tendo misturado os três.

## Como um app glacier funciona

Leia esta seção antes de escrever a primeira linha: quase todo erro de quem
começa (inclusive de IA) vem de supor um modelo que não é este.

### Três arquivos, três papéis

| arquivo | responde a pergunta | e nada mais |
|---|---|---|
| `.gv` | **o que existe** na tela e o que cada coisa dispara | sem cor, sem tamanho |
| `.gss` | **como aparece** | sem estrutura, sem ação |
| `.luau` (ou Rust) | **o que acontece** quando algo é disparado | sem markup |

### O contexto é um mapa plano de strings

Existe **um** dicionário por janela, `chave → texto`. Tudo que a tela mostra sai
dele, e é a única ponte entre o comportamento e o markup:

```
        escreve                          lê
script  ─────────►   ctx: { … }   ─────────►  markup
ctx.total = "3"      total = "3"              <text>{total}</text>
```

Três consequências que mudam como se escreve:

1. **Tudo é texto.** `ctx.total = 3` funciona (o motor converte na escrita), mas
   na leitura volta `"3"`. Compare com `tonumber(ctx.total)`, nunca com `3`.
2. **Uma tabela vira JSON.** `ctx.itens = { {id="1"}, {id="2"} }` grava a string
   JSON, que é o formato que `items="itens"` espera nos widgets de coleção.
3. **Qualquer escrita reavalia a tela inteira.** Não existe atualização parcial —
   e não precisa existir: montar a árvore custa 0,07 ms (ver a primeira seção).
   Escreva no `ctx` e esqueça; o motor redesenha o que mudou.

### Onde mora o estado que não é texto

O `ctx` é a **vitrine**, não o depósito. Estado com forma (listas de structs,
flags de carregamento, o que veio de uma API) mora num módulo Luau tipado — ou
nos campos do seu `Component` Rust — e uma função `publicar()` o projeta no
`ctx` quando muda:

```lua
-- views/scripts/state.luau — o depósito, tipado
export type Item = { id: string, nome: string, ativo: boolean }
local State: { itens: { Item } } = { itens = {} }
return State
```
```lua
-- views/scripts/handlers/dados.luau — a vitrine
local State = require("../state")
local Dados = {}

function Dados.publicar(): ()
    local linhas = {}
    for _, it in State.itens do
        table.insert(linhas, { id = it.id, nome = it.nome, ativo = if it.ativo then "1" else "0" })
    end
    ctx.itens = json.encode(json.array(linhas))   -- a coleção que o markup lê
    ctx.total = tostring(#State.itens)            -- os derivados, já prontos
end

return Dados
```

**O markup não calcula.** Se a tela precisa de "3 de 7 ativos", quem monta essa
string é o script; `{ativos} de {total}` é o máximo que o `.gv` faz. Isso não é
limitação a contornar — é o que mantém o template legível e o cálculo testável.

`json.array(t)` marca a tabela como **array** para o encode: sem ele, uma lista
vazia vira `{}` em vez de `[]`, e o widget de coleção não acha itens.

### O ciclo de uma ação, passo a passo

```xml
<button text="Salvar" on_click="salvar" />
```

1. O clique vira a ação `"salvar"`.
2. O motor consome sozinho se o nome tiver um **prefixo reservado** (abaixo).
3. Senão procura uma função global Luau chamada `salvar` e a chama.
4. Se não houver script, procura o braço `"salvar"` no `update` do `Component`
   Rust.
5. Se não houver nenhum dos dois **e a ação trouxer um valor** (um `on_change`,
   por exemplo), o motor grava `ctx["salvar"] = valor` e pronto.
6. O que o passo 3/4 escreveu no `ctx` reavalia a tela.

O passo 5 é o atalho que faz `<textinput value="nome" on_change="nome" />`
funcionar sem uma linha de script: a ação tem o nome da chave, e o motor grava.

**Ação com carga.** `on_click="remover:banco"` chama `remover("banco")` — o
sufixo depois do `:` vira o primeiro argumento. É como uma linha de lista passa
o próprio id:

```xml
<button for-each="itens" var="i" text="✕" on_click="remover:{i.id}" />
```
```lua
function remover(id: string): ()  …  end
```

**O valor.** Um `on_change`/`on_toggle` traz o texto novo. Em Luau ele chega
como argumento (`function nome(v: string)`) e também no global `value`; em Rust,
no parâmetro `value: Option<&str>`.

### Os prefixos que o motor consome sozinho

Nunca chegam ao seu código — e por isso não precisam de handler:

| prefixo | o que faz |
|---|---|
| `window:drag`, `window:minimize`, `window:maximize`, `window:close` | controles da janela, para uma titlebar própria |
| `window:resize:se` (e `n`,`s`,`e`,`w`,`nw`,`ne`,`sw`) | alças de redimensionar |
| `dialog:config` / `dialog:close` | abre o `<dialog name="config">` / fecha o aberto |
| `clipboard:{chave}` | copia o valor da chave |
| `open:{chave}` | abre a URL/arquivo que a chave guarda |
| `textarea_end:doc` / `textarea_top:doc` | move o cursor do `<textarea>` |
| `style:escuro` | troca o estilo builtin ativo |

E um que é o oposto — `app:` **desmarca** a ação de quem a repassou:

```xml
<!-- dentro de um componente seu, repassando uma ação do app para um filho -->
<button on_click="app:{ao_salvar}" text="Salvar" />
```

Sem o `app:`, uma ação que passa por dentro de um componente vira
`MeuComponente::salvar` e nunca chega no handler da tela. Use `app:` sempre que
um componente **repassar** uma ação que ele recebeu por prop.

### Navegação entre telas

Cada tela é um componente registrado. Trocar de tela é uma ação:

```xml
<button text="Sobre" navigate_to="sobre" />     <!-- do markup -->
```
```lua
navigate("sobre")      navigate_back()          -- do script
```

Muitos apps de uma janela só nem navegam: guardam a tela numa chave e trocam o
ramo com um condicional — é o que o preset `completo` faz:

```xml
<Home  if="{view}" equals="home" />
<Sobre if="{view}" equals="sobre" />
```

### Condicional e repetição são ATRIBUTOS

Isto vale em **qualquer** tag, não só em `<template>` — e é a forma que se usa
quando há uma tag só para condicionar:

```xml
<text if="{erro}" class="erro">{erro}</text>
<text else class="ok">tudo certo</text>

<Card for-each="servicos" var="s" title="{s.nome}" estado="{s.estado}" />
```

`<template>` existe para quando o condicional precisa envolver **vários** nós
sem criar uma caixa em volta deles:

```xml
<template if="{aba}" equals="rede">
  <text class="secao">Rede</text>
  <textinput value="host" on_change="host" />
</template>
```

Comparadores disponíveis nos dois: `equals`, `not_equals`, `one_of` (lista
separada por espaço, no atributo), `contains` (o inverso — a lista está na
chave), `empty` e `not_empty` (que testam um **array JSON**, não uma string).
Sem comparador nenhum, o teste é **truthy**: vazio, `"false"` e `"0"` são
falsos — e é essa a forma de testar um texto.

## A anatomia do projeto

```
meu-app/
├── Cargo.toml
├── Makefile              # make run | lint | linux-dist | windows | deb
├── src/main.rs           # registra as telas e abre a janela
└── views/                # LIDO EM RUNTIME — ver o aviso abaixo
    ├── app.gv            # a tela raiz
    ├── components/       # os .gv reutilizáveis
    ├── scripts/
    │   ├── app.luau      # o `init` e os handlers da tela
    │   ├── state.luau    # o estado tipado
    │   ├── handlers/     # handlers por assunto
    │   └── glacier.d.luau# os tipos dos globais (só o luau-lsp lê)
    └── styles/
        ├── app.gss
        └── theme.json    # as cores base do tema
```

**`views/` é lido em tempo de execução, não embutido no binário.** Isso é o que
dá o hot-reload — salvar um `.gv` ou `.gss` com o app aberto aplica na hora, sem
recompilar. E é o que faz todo alvo de pacote do `Makefile` copiar a pasta
junto: um pacote sem `views/` compila, instala, abre e mostra uma janela vazia.

Os comandos que importam:

```sh
make run     # roda em debug
make lint    # clippy + type-check dos .luau (é o que precisa passar)
make luau    # só o type-check dos scripts
```

## Um app inteiro, comentado

Uma lista com filtro, contador e uma ação por linha — o esqueleto de nove em
cada dez telas. São três arquivos.

```xml
<!-- views/servicos.gv -->
<screen title="Serviços" size="720 520" min_size="480 360">
  <resources>
    <link rel="theme"      href="views/styles/theme.json" />
    <link rel="stylesheet" href="views/styles/app.gss" />
    <script src="scripts/servicos.luau"></script>
  </resources>

  <column class="tela">
    <row class="topo">
      <text class="titulo">Serviços</text>
      <space />                                   <!-- empurra o resto -->
      <text class="contador">{ativos} de {total} ativos</text>
    </row>

    <!-- `value` é o NOME da chave; `on_change` com o mesmo nome faz o motor
         gravar sozinho (passo 5 do ciclo de uma ação). -->
    <textinput value="busca" on_change="filtrar" placeholder="filtrar…" />

    <!-- Vazio e cheio são dois ramos do mesmo condicional. `empty` testa se a
         chave é um array JSON sem elementos. -->
    <text if="{visiveis}" empty class="vazio">nenhum serviço encontrado</text>

    <scrollable height="fill">
      <column class="lista">
        <row for-each="visiveis" var="s" class="linha">
          <text class="nome">{s.nome}</text>
          <space />
          <Badge badge_text="{s.estado}" />
          <button class="btn" text="alternar" on_click="alternar:{s.id}" />
        </row>
      </column>
    </scrollable>
  </column>
</screen>
```

```lua
-- views/scripts/servicos.luau
--!strict
--!nolint FunctionUnused   -- o motor chama estas funções pelo nome; o lsp não vê

type Servico = { id: string, nome: string, ativo: boolean }

-- O DEPÓSITO: tipado, com a forma real do dado.
local servicos: { Servico } = {
    { id = "api",   nome = "api de borda",     ativo = true },
    { id = "fila",  nome = "fila de trabalhos", ativo = true },
    { id = "frio",  nome = "réplica fria",      ativo = false },
}

-- A VITRINE: projeta o depósito no ctx, já filtrado e com os derivados prontos.
local function publicar(): ()
    local busca = string.lower(ctx.busca or "")
    local visiveis, ativos = {}, 0

    for _, s in servicos do
        if s.ativo then ativos += 1 end
        if busca == "" or string.find(string.lower(s.nome), busca, 1, true) then
            table.insert(visiveis, {
                id = s.id,
                nome = s.nome,
                estado = if s.ativo then "ativo" else "parado",
            })
        end
    end

    ctx.visiveis = json.encode(json.array(visiveis))  -- json.array: lista vazia = []
    ctx.total    = tostring(#servicos)
    ctx.ativos   = tostring(ativos)
end

-- Chamado uma vez, quando a tela monta.
function init(): ()
    ctx.busca = ""
    publicar()
end

-- `on_change="filtrar"` — o texto novo chega como argumento.
function filtrar(texto: string): ()
    ctx.busca = texto
    publicar()
end

-- `on_click="alternar:{s.id}"` — o sufixo vira o primeiro argumento.
function alternar(id: string): ()
    for _, s in servicos do
        if s.id == id then
            s.ativo = not s.ativo
            toast({ message = `{s.nome}: {if s.ativo then "ativo" else "parado"}`, kind = "info" })
            break
        end
    end
    publicar()
end
```

```gss
/* views/styles/app.gss — só aparência */
:root {
  --fraco:  #7F849C;
  --linha:  #313244;
}

.tela     { width: fill; height: fill; padding: 16; spacing: 12; }
.topo     { width: fill; align_y: center; spacing: 12; }
.titulo   { size: 18; bold: true; }
.contador { size: 12; color: var(--fraco); }
.lista    { width: fill; spacing: 6; }
.linha    { width: fill; align_y: center; spacing: 10; padding: 8 10;
            border_radius: 6; border_width: 1; border_color: var(--linha); }
.nome     { size: 13; }
.vazio    { size: 12; color: var(--fraco); }
```

E o `src/main.rs`, que não muda quase nunca:

```rust
use glacier_ui::GlacierDaemon;

fn main() -> glacier_ui::iced::Result {
    GlacierDaemon::new()
        .main(|motor| {
            if let Err(erro) = motor.register_component("servicos", "views/servicos.gv") {
                eprintln!("{erro}");
            }
            motor.set_initial_screen("servicos");
        })
        .run()
}
```

## O que custa num quadro, em ordem

Antes de otimizar qualquer coisa, saiba onde o tempo vai. Numa tela de **111 nós
com 20 caixas pintadas**, janela de 900×720:

| | por quadro |
|---|---|
| Pintar as caixas | **~45 ms** |
| Layout, texto e o resto do `iced` | ~50 ms |
| O motor glacier montar a árvore | **0,07 ms** |

O motor é seiscentas vezes mais barato que a pintura. **Quase nunca é ele.** Uma
tela de 300 nós sem fundo nenhum roda mais rápido que uma de 111 nós pintada.

## As três regras de estilo que mais pagam

Toda caixa com fundo, borda ou canto arredondado vira um retângulo que a GPU
sombreia **por pixel**. O custo é da **área**, não da quantidade — e as camadas
se somam onde se sobrepõem.

### 1. Não pinte a janela inteira

O tema já pinta o fundo. Um `background` de mesma cor num nó `width: fill;
height: fill` é uma camada redobrada em **cada pixel da tela**, invisível e cara.

```gss
/* não */
.tela    { width: fill; height: fill; background: var(--bg); }
.conteudo { width: fill; height: fill; background: var(--bg); }

/* sim — a cor vive no theme.json, e o resto herda */
.tela    { width: fill; height: fill; }
.conteudo { width: fill; height: fill; }
```

Num app real isto apareceu **nove vezes**, incluindo duas camadas empilhadas no
mesmo arquivo. Removê-las não mudou um pixel na tela e foi o maior ganho isolado.

Se o fundo precisar diferir do tema, **mude o tema** — não pinte por cima.

### 2. Menos camadas sobrepostas

Um `groupbox` dentro de um `frame` dentro de um container pintado são três
passadas na mesma área. Escolha uma. Antes de acrescentar um fundo, pergunte o
que já está pintado ali embaixo.

### 3. Canto arredondado só nas caixas pequenas

Arredondar exige matemática de distância em cada pixel do retângulo — inclusive
no meio dele, longe dos cantos. Numa caixa que ocupa a tela, isso é caro e o
detalhe de 7px quase não se nota; num crachá ou botão, é barato e faz a
aparência. Guarde o `border-radius` para as caixas pequenas.

## Como medir, em vez de adivinhar

Três variáveis de ambiente, todas sem custo quando desligadas:

```sh
GLACIER_PERF=1 ./app                      # relatório por segundo
GLACIER_PERF=1 GLACIER_PERF_STRESS=1 ./app  # mede CAPACIDADE, não demanda
GLACIER_PERF=1 GLACIER_PERF_STRESS=1 GLACIER_NO_PAINT=1 ./app  # sem pintura
```

O relatório reparte o quadro em quatro:

```
render 0.43 méd | dispatch 1.20/quadro (14 msgs) | app 0.05 | resto 15.6ms (90.7%)
```

| Parcela grande | Onde mexer |
|---|---|
| `render` | o motor monta nós demais → `virtualize` numa coluna dentro de `<scrollable>` |
| `dispatch` | tratamento de mensagem: `update`, Luau, reavaliação |
| `app` | seus ganchos (`on_message`) — um lock disputado aqui trava a UI |
| `resto`, com árvore pequena | `iced`/GPU: layout, texto, **pintura** |

**Duas armadilhas de leitura**, ambas já custaram diagnósticos errados:

- **Sempre use `GLACIER_PERF_STRESS` para julgar velocidade.** Sem ele, um app
  orientado a evento fica ocioso entre eventos e o `intervalo` medido é a
  espera, não o custo. Um app parado já apareceu como "quadro de 19 segundos".
- **Compare com pintura e sem.** Se `NO_PAINT` acelerar muito, o gargalo é
  rasterização e a saída são as três regras acima — não otimizar código.

O procedimento que resolve em dois minutos: rode com `STRESS`, anote o
`intervalo méd`; rode de novo com `NO_PAINT` junto; compare.

## Listas longas

Uma lista que não cabe na tela entrega ao `iced` itens que ninguém vê, e ele
mede e desenha todos. `virtualize` monta só os visíveis:

```xml
<scrollable height="fill">
  <column spacing="12" virtualize="300">   <!-- 300 = altura de CADA item -->
    <foreach items="servicos" var="s"> … </foreach>
  </column>
</scrollable>
```

A altura é **declarada**, não medida (medir exigiria o layout, que é o trabalho
a evitar). A coluna precisa ser filha direta do `<scrollable>`. Errar a altura
desalinha a barra de rolagem, não quebra a tela.

Só vale para listas que **não cabem** na tela: com poucos itens ela não age, de
propósito.

## Como se escreve um `.gv` e um `.gss` aqui

A convenção vale para **todo** template e toda folha do projeto — os que já
existem e os que vierem. O motor aceita várias grafias como apelido, e é
justamente por isso que a regra precisa estar escrita: nada quebra se você
misturar, e um arquivo com quatro grafias da mesma coisa é o resultado natural
de não decidir.

**1. Tags do motor em minúsculas, atributos em `snake_case`.**

```xml
<!-- não -->
<Column spacing="10"><TextInput onChange="salvar" minSize="200 100" /></Column>

<!-- sim -->
<column><textinput on_change="salvar" min_size="200 100" /></column>
```

**A exceção é obrigatória, não estilística:** a tag de um componente do app é
resolvida pelo **nome com que ele foi registrado**, e a busca é sensível a
caixa — `<MeuCartao/>` funciona, `<meucartao/>` é `UnknownComponent`. Isso dá à
convenção uma propriedade que vale de graça: numa tela, `CamelCase` significa
"componente deste app" e minúscula significa "widget do motor".

**2. O texto de um `<text>` é filho, não atributo.**

```xml
<text content="Serviços ativos" />   <!-- não -->
<text>Serviços ativos</text>          <!-- sim -->
```

Interpolação continua valendo no filho: `<text>Olá, {usuario}</text>`.

**3. Estilo mora no `.gss`; o markup fica com estrutura.**

Cor, tamanho, espaçamento, padding e largura de caixa saem do `.gv` e viram uma
**classe com nome de papel**:

```xml
<text class="rotulo">Último salvamento</text>
```
```gss
.rotulo { size: 12; color: var(--fraco); }
```

Três coisas continuam inline, porque não são estilo: **valor dirigido por dado**
(`background="{cor}"`), **medida com significado de widget** (o `size` de uma
roda de cor, o `width` de um `<spinbox>` — que é a largura do *campo*, não a do
conjunto) e **estrutura/ação** (`value`, `items`, `slot`, `on_click`).

**4. Indentação de dois espaços**, nos dois arquivos.

**5. No `.gss`, propriedades também em `snake_case`** — `border_radius`,
`border_width`, `border_color`, `align_x`, `align_y`, `text_align`,
`text_color`, `max_width`, `max_height`, `font_family`. Cores nomeadas em
`:root` e usadas por `var(--nome)`, nunca um hexadecimal repetido em cinco
regras.

Uma exceção obrigatória: dentro de `@media` o nome é uma **feature do CSS**, não
uma propriedade do motor — `@media (max-width: 720)` funciona, `max_width` é
erro.

### Por que isso importa mais do que parece

Uma propriedade de estilo que o motor não conhece é **ignorada com aviso**, não
é erro: um `border-bottom:` (que não existe — a borda é dos quatro lados) some
em silêncio no meio de um `.gss` grande. Concentrar o estilo num arquivo só, com
nomes de papel, é o que torna esse aviso fácil de ver.

Do lado do markup vale o simétrico: quanto menos atributo por tag, mais óbvio
fica quando um deles **não é** o que parece — `value` num widget de valor é
*nome de chave*, não interpolação; `width` numa prop de builtin costuma ser a
largura de um filho, e um `fill` ali colapsa o widget sem erro nenhum.

## O catálogo de widgets

São **110 tags**. Nenhuma precisa ser registrada, importada ou configurada: o
motor conhece as primitivas e a lib auto-registra os builtins antes de a
primeira tela existir. Se a tag está nesta seção, ela funciona.

Como saber, olhando uma tela, o que é o quê:

| grafia | o que é | onde mora |
|---|---|---|
| `<column>`, `<textinput>` | **primitiva** do motor | `src/parser.rs` + `src/widget.rs` |
| `<Card>`, `<TabBar>` | **builtin** da lib (template de markup) | `src/builtins/` |
| `<MeuCartao>` | **componente deste app** | um `.gv` seu |

Builtins também respondem em minúscula colada (`<card/>` == `<Card/>`). A
convenção deste projeto usa minúscula para tudo do motor/lib e `CamelCase` só
para o que é seu — assim a caixa da letra já diz de onde a tag vem.

**Como ler uma entrada deste catálogo.** Cada widget traz os atributos que só
ele entende, com o valor aceito e o default; os atributos genéricos (`class`,
`width`, `padding`, `background`, `hidden`…) valem em todos e estão numa seção
só, logo abaixo. Quando o widget lê uma coleção, a forma exata do JSON está
junto, com um exemplo de como o script a produz. O motor aceita `CamelCase`,
`camelCase`, `kebab-case` e nomes em português como apelidos de quase todo
atributo; as tabelas mostram **uma** grafia, a que este projeto escreve.

### O esqueleto de um `.gv`

Uma **tela** (uma janela) e um **componente** (um pedaço importado por outra
tela) têm o mesmo formato; o que muda é a raiz:

```xml
<screen title="Painel" size="1080 760" min_size="900 640">
  <resources>
    <link rel="stylesheet" href="views/app.gss" />
    <link rel="theme" href="theme.json" />
    <link rel="import" href="views/cartao.gv" />
    <link rel="data" as="paises" href="dados/paises.json" />
    <script src="scripts/app.luau"></script>
    <dialog name="config"> … corpo do modal … </dialog>
    <component name="Rotulo">  … um componente local, sem arquivo … </component>
  </resources>

  <column class="tela"> … o layout … </column>
</screen>
```

```xml
<component>
  <props>
    <prop name="titulo" />                 <!-- sem default = obrigatória -->
    <prop name="cor" default="#89B4FA" />
  </props>

  <container class="cartao" background="{cor}">
    <text>{titulo}</text>
    <slot />                                <!-- o conteúdo de quem usa -->
  </container>
</component>
```

O `<props>` é um **contrato**: com ele declarado, uma prop que ninguém declarou
vira erro na hora (é onde um `labl="…"` deixa de ser invisível), e uma
obrigatória que faltou também. Sem `<props>`, nada é checado — a regra antiga
continua valendo para quem não quer o contrato.

Três formas de trazer outro template:

| forma | quando |
|---|---|
| `<link rel="import" href="views/cartao.gv" />` | no `<resources>`, registra pelo nome do arquivo |
| `<import name="Cartao" from="views/cartao.gv" />` | quando o nome do componente difere do arquivo |
| `<include src="views/pedaco.gv" />` | cola o conteúdo ali, sem virar componente |

Os `rel` que existem são cinco: `stylesheet`, `import`, `component` (apelido de
`import`), `data` — que carrega um JSON numa chave de contexto, e aí `as`/`name`
é obrigatório — e `theme`. Qualquer outro é erro na carga, com a lista na
mensagem.

No `<screen>`: `title`, `size="1080 760"`, `min_size` e `resizable="false"`. O
`<dialog>` tem seção própria ("O `<dialog>` — o modal com corpo em markup"),
com o `buttons=` nos mínimos detalhes.

### O que vale em qualquer tag

Estes atributos o motor lê em **todo** nó, primitiva ou builtin. Não os procure
na tabela de cada widget:

| atributo | valor aceito |
|---|---|
| `class` | uma ou mais classes separadas por espaço: `class="cartao destaque"` |
| `id` | um nome; casa `#nome { }` no `.gss`, que vence a classe |
| `width`, `height` | `fill`, `fill 2`, `shrink` ou um número (`"240"`). Qualquer outra coisa vira `shrink`, **sem aviso** |
| `padding` | 1, 2 ou 4 números: `"12"`, `"8 16"` (vertical horizontal), `"8 16 8 16"` (topo direita baixo esquerda). **Três números viram zero**, em silêncio |
| `spacing` | um número; o vão entre os filhos de uma `<column>`/`<row>`/`<grid>`/`<flow>` |
| `align_x`, `align_y` | exatamente `start`, `center` ou `end`. `left`/`right`/`top` **não existem** e caem no default |
| `background` | `#rrggbb` ou `#rrggbbaa` |
| `gradient` | `"180 #1e1e2e #313244"` — ângulo em graus (opcional, default 180) seguido de **duas ou mais** cores, distribuídas por igual. Vence o `background` |
| `border_radius`, `border_width` | um número |
| `border_color` | `#rrggbb`/`#rrggbbaa` |
| `max_width`, `max_height` | um número; o motor embrulha o nó num container que limita |
| `hidden`, `disabled` | truthy: `"true"`/`"1"` liga; vazio, `"false"` e `"0"` desligam. Aceitam `{chave}` — é assim que se liga ao dado |
| `tooltip`, `tooltip_position` | texto do balão; a posição é `top`/`bottom`/`left`/`right` |
| `whats_this` | ajuda do `QWhatsThis`. Só aparece com o **modo pegajoso** ligado (ação `whatsthis:on`/`off`/`toggle` → chave `__whatsthis`), e aí toma o lugar do `tooltip=` no hover |
| `cursor` | `pointer`, `text`, `grab`, `grabbing`, `move`, `crosshair`, `wait`, `progress`, `help`, `not-allowed`, `none`, e as alças `resize-h`, `resize-v`, `resize-ne`, `resize-nw` (com os apelidos de bússola `n`, `s`, `e`, `w`, `ne`, `nw`, `se`, `sw`) |
| `on_press`, `on_double_click` | nome de uma ação; clique em **qualquer** elemento (o `on_click` é do `<button>`) |
| `font`, `text_align`, `text_color`, `size`, `bold`, `color` | o texto **dentro** do nó |
| `virtualize` | só numa `<column>`/`<row>` dentro de `<scrollable>` — ver "Listas longas" |
| `x`, `y`, `anchor` | só num filho de `<stack>` — ver Sobreposição |
| `form_control` | liga o campo à `<form>` que o envolve; com `rules="…"`, `msg="…"`, `pattern="…"` o motor valida esse campo no envio (ver "Validação declarada no próprio `<form>`") |
| `if`, `else`, `else-if`, `for-each`, `var`, `slot` | diretivas; ver "Estrutura de template" |

Cor sempre em hexadecimal — não há `rgb()`, nem nome de cor, nem `transparent`
(o equivalente é `#00000000`).

`font` aceita `mono`/`bold` de fábrica, mais qualquer **família registrada** pelo
app no lado Rust (`GlacierDaemon::font_named("Inter", bytes)`) — o mesmo caminho
serve o `font_family` do `.gss`. Um nome não registrado cai na fonte padrão, sem
aviso. A chave `__fonts` (o motor a semeia) traz a lista, para um
`<combo items="__fonts">` ou o `<fontselect>`.

### Como um widget lê os seus dados

Três formas, e confundi-las é a causa mais comum de "o widget aparece vazio".

**1. Nome de chave.** `value`, `items`, `options`, `checked`, `group`, `open`,
`selected`, `sizes`, `widths` — todos recebem o **nome** de uma chave do
contexto, sem chaves:

```xml
<slider value="volume" min="0" max="100" />   <!-- sim -->
<slider value="{volume}" />                   <!-- NÃO: procura a chave "42" -->
```

É o que permite duas instâncias do mesmo widget sem estado por instância, e é
por isso que o erro não dá mensagem: `"42"` é um nome de chave válido.

**2. Valor interpolado.** Tudo que é texto exibido ou cor: `background="{cor}"`,
`title="{s.nome}"`, `active="{aba}"`. Aqui as chaves são obrigatórias.

**3. Chave *ou* JSON literal.** Alguns atributos aceitam os dois — o motor tenta
parsear o valor como JSON e, se não for JSON, trata como nome de chave:

| atributo | onde |
|---|---|
| `bands` | `<gauge>` |
| `colors` | `<piechart>`/`<donut>` |
| `items` | `<tumbler>`, `<rubberband>` |
| `columns` | `<tableview>`/`<tableheader>` (JSON de colunas **ou** especificação de trilhas) |

Todo o resto que é lista (`<linechart items>`, `<listview items>`,
`<treeview items>`, `for-each`) é **só nome de chave**. Uma lista literal no
atributo não existe ali.

**Uma chave que não existe, ou um JSON inválido, não dá erro:** o widget
renderiza vazio. Semear a chave no `init` do script é o que evita isso.

### O par `value` + `active`/`open`/`selected`

Vários widgets pedem os dois, e parece redundância:

```xml
<TabBar items="abas" value="aba" active="{aba}" />
```

`value="aba"` é o **nome da chave que o clique escreve**; `active="{aba}"` é o
**valor que o markup lê** para decidir qual aba está destacada. Um é escrita, o
outro é leitura. Escrever `active="aba"` (sem chaves) compara o valor da aba
ativa com a string literal `"aba"` — nada nunca fica ativo, e não há erro.

### Layout e estrutura

**`<column>` / `<row>`** — empilham na vertical / horizontal. Sem atributo
nenhum são `shrink` nos dois eixos. `spacing` é o vão **entre** os filhos,
`padding` é a margem interna da caixa, `align_x`/`align_y` alinham o conteúdo no
eixo transversal.

**`<container>`** — embrulha **um** filho. É onde `background`, `border_*` e
`max_width` fazem efeito de verdade; uma `<column>` também aceita, mas o
container é o nó que existe para isso. Com mais de um filho, só o primeiro
aparece.

**`<grid columns="…">`** — grade real: a largura de uma coluna é medida em
**todas** as células dela, não só na primeira linha.

| atributo | valor |
|---|---|
| `columns` (default `"1"`) | ou um número (`"3"` = três colunas automáticas), ou uma **especificação de trilhas** |
| `row_spacing` | vão vertical; sem ele, usa o `spacing` |

A especificação de trilhas é uma lista separada por espaço, e vale também no
`<splitter sizes>` e no `<tableview columns>` quando não é JSON:

| token | o que faz |
|---|---|
| `140` | largura fixa em pixels |
| `fill` | divide o que sobrou, peso 1 (`flex` é apelido) |
| `fill2`, `fill-2`, `fill_2` | o mesmo, com peso 2 |
| `auto` ou `*` | o que o conteúdo pedir |

Um token que não é nenhum desses vira `auto`, em silêncio.

**A pegadinha do número solto:** num `columns=`, `"3"` sozinho quer dizer *três
colunas automáticas*; na chave de `widths` de um `<tableview>`, `"160"` quer
dizer *uma coluna de 160px*. É a mesma gramática lida de dois modos, porque as
duas leituras são o que cada lugar precisa.

```xml
<grid columns="140 fill 80" spacing="8" row_spacing="4"> … </grid>
```

**`<flow>`** — como uma `<row>`, mas quebra a linha quando não cabe. `spacing`
horizontal, `row_spacing` vertical.

**`<scrollable direction="vertical">`** — área rolável. `direction` aceita
`vertical` (default), `horizontal`/`h`/`x`, e `both`/`xy`.

**`<space />`** — espaço vazio. Sem `width`/`height` é `fill` nos dois eixos: é
o empurrador que joga o resto da `<row>` para a direita.

**`<rule />`** — linha divisória. `direction="v"` (ou `vertical`) para vertical;
qualquer outra coisa é horizontal.

**`<splitter sizes="paineis">`** — painéis com alça arrastável entre cada par.
Cada filho direto é um painel.

| atributo | valor |
|---|---|
| `sizes` | **nome da chave** que guarda a especificação de trilhas (`"240 fill"`); o arrasto reescreve a chave |
| `vertical="true"` ou `direction="v"` | empilha na vertical |
| `handle` (default `6`, entre 2 e 24) | espessura da alça |
| `min` (default `60`) | tamanho mínimo de um painel, em pixels |

**`<stack>`** — empilha os filhos **no mesmo espaço**, o primeiro embaixo. É a
única tag em que `x`, `y` e `anchor` de um filho significam alguma coisa:

```xml
<stack width="fill" height="fill">
  <image source="fundo.png" />                        <!-- camada de baixo -->
  <text anchor="bottom-right" class="marca">v1.2</text>
  <container x="20" y="14" class="etiqueta">
    <text>beta</text>
  </container>
</stack>
```

`anchor` aceita os nove cantos: `top-left` (o default de qualquer grafia
desconhecida), `top`, `top-right`, `left`, `center`, `right`, `bottom-left`,
`bottom`, `bottom-right`. Hífen ou sublinhado, tanto faz. `x`/`y` são pixels a
partir do canto superior esquerdo e **ignoram** o `anchor`.

`<stack>` não pinta fundo por si; o motor insere uma camada base para o
`background` funcionar, mas a caixa que você quer colorida ainda é um
`<container>` dentro dele.

**`<mdiarea>` + `<mdisubwindow>`** — janelas internas, arrastáveis pela barra de
título e redimensionáveis pelo canto inferior direito.

| atributo do `<mdisubwindow>` | valor |
|---|---|
| `title` | texto da barra |
| `x_var`, `y_var` | **nomes de chave** onde a posição é gravada durante o arrasto |
| `w_var`, `h_var` | idem para o tamanho |
| `default_w` (320), `default_h` (220) | tamanho inicial, enquanto a chave ainda está vazia |

Sem as chaves, a janela não se move: o arrasto grava no contexto, e é do
contexto que a posição é lida no próximo quadro. Sem `x_var`, o `<mdiarea>` dá a
cada janela uma posição em cascata (`20 + i·24`).

### Texto e exibição

**`<text>`** — o conteúdo é **filho**, não atributo:

```xml
<text class="titulo">Serviços ativos</text>
<text>Olá, {usuario}</text>
```

`size`, `bold`, `color` e `text_align` existem inline, mas o lugar deles é uma
classe no `.gss`. O atributo `content="…"` continua funcionando e é o que os
builtins usam internamente.

**`<image source="foto.png" />`** — bitmap. `clip="circle"` recorta em círculo
(qualquer outro valor não recorta). Combine com `width`/`height` fixos: sem eles
a imagem pede o tamanho natural do arquivo.

**`<svg source="icone.svg" color="#89B4FA" />`** — vetor; `color` tinge o traço
inteiro.

**`<qrcode content="{url}" width="120" />`** — QR code.

| atributo | valor |
|---|---|
| `content` | o texto codificado; **interpolado**, não nome de chave |
| `color` | cor dos módulos |
| `width`/`height` | o **lado renderizado** do código, não a caixa em volta |

`value=` não é apelido de `content` de propósito: em todo o resto do catálogo
`value` significa nome de chave, e aqui significaria o oposto.

**`<progressbar value="pct" />`** — barra determinada.

| atributo | default |
|---|---|
| `value` | nome da chave com o número |
| `min` / `max` | `0` / `100` |
| `vertical` | `false` |
| `show_value` | `false` — a barra sozinha não escreve o número |
| `color` | a primária do tema |

**`<lcdnumber value="relogio" />`** — dígitos de sete segmentos.

| atributo | default | o que faz |
|---|---|---|
| `digits` | `0` (o que o valor pedir) | largura fixa em dígitos |
| `size` | `44` | altura de um dígito |
| `decimals` | `0` | casas depois da vírgula |
| `pad` | `false` | preenche com zeros à esquerda |
| `ghost` | `true` | desenha os segmentos apagados em tom fraco, como um LCD real |
| `color` | tema | cor dos segmentos acesos |

**`<spinner />`** — girando, sem fim. Para operação sem duração conhecida;
quando há progresso, `<progressbar>`.

**`<reveal open="{aberto}">`** — abre e fecha **animado**, interpolando a altura
do filho de 0 até a natural.

| atributo | default |
|---|---|
| `open` | truthy; aceita `{chave}` |
| `duration` | `180` (ms) |
| `axis="x"` | anima a **largura** em vez da altura |

**`<Badge badge_text="Novo" />`** — pílula de rótulo. Props: `badge_text`
(default `"Badge"`), `badge_bg`, `badge_fg`, `badge_size` (13), `text_class`.

**`<Avatar />`** — foto circular com iniciais como reserva. Props: `src`,
`initials` (default `"?"`), `size` (40), `bg` (`#8080803d`), `fg`,
`image_class`, `fallback_class`, `initials_class`. Com `src` vazio, cai nas
iniciais — é o caminho normal, não um erro.

**`<Chip label="produção" on_remove="tirar:producao" />`** — badge com "×".
Props: `label`, `on_remove` (sem ele o "×" não é desenhado), `bg`, `fg`, `size`
(13), `label_class`, `close_class`.

**`<Skeleton width="220" height="14" />`** — placeholder de carregamento. Props:
`width` (`fill`), `height` (16), `radius` (4), `background`.

### Entrada de dados

Todos gravam numa chave. O `on_change` é **opcional**: sem uma função global com
aquele nome, o motor faz `ctx[nome] = valor` sozinho. Preencha só quando quiser
interceptar.

**`<textinput value="nome" />`** — campo de uma linha. `placeholder`,
`secure="true"` (senha), `on_change`.

**`<textarea value="doc" />`** — multi-linha. `placeholder`, `on_change`. Para
um log vivo, use `readonly="true"` e escreva com `append_textarea` do Luau — que
insere no fim sem recriar o buffer, preservando o scroll. `font="JetBrains Mono"`
(uma família registrada, ver "O que vale em qualquer tag") é o `QPlainTextEdit`:
texto simples, mono declarável.

**`<maskedinput value="cpf" mask="cpf" />`** — guarda **cru** e exibe
mascarado. A chave nunca contém pontuação: é isso que faz um CPF gravado ser
comparável.

| símbolo na máscara | aceita |
|---|---|
| `#` | dígito |
| `A` | letra |
| `*` | qualquer caractere |
| qualquer outro | literal (só aparece quando há dado depois dele) |

Presets, no lugar da máscara literal:

| `mask=` | expande para |
|---|---|
| `cpf` | `###.###.###-##` |
| `cnpj` | `##.###.###/####-##` |
| `telefone` (ou `phone`, `celular`) | `(##) #####-####` |
| `cep` | `#####-###` |
| `placa` | `AAA#*##` (Mercosul; a antiga cabe na mesma) |
| `date` / `data` | `##/##/####` |
| `time` / `hora` | `##:##` |
| `card` / `cartao` | `#### #### #### ####` |

Qualquer outro valor é usado como máscara literal — `mask="+55 (##) ####-####"`
funciona.

**`<checkbox label="Usar proxy" checked="usar_proxy" />`** — a chave recebe
`"true"`/`"false"`. Com `tristate="true"` ela cicla `"false"` → `"mixed"` →
`"true"`, e `"mixed"` desenha o traço parcial.

**`<toggle label="Ativo" checked="ativo" />`** — mesma semântica de ligação, sem
tristate.

**`<radio label="Mensal" value="mensal" group="plano" />`** — `group` é o **nome
da chave**; dois `<radio>` com o mesmo `group` são o mesmo grupo, e o `value` de
cada um é o que a chave passa a conter.

**`<RadioGroup items="planos" value="plano" />`** — o grupo inteiro a partir de
uma coleção. Cada item é `{ id, label }`. Props: `layout="row"` (default
`column`), `spacing`, `options_class`, `option_class`.

**`<SpinBox value="qtd" />`** — campo numérico com degraus.

| prop | default |
|---|---|
| `min` / `max` | `0` / `100` |
| `step` | `1` |
| `decimals` | inteiro |
| `width` | `72` — a largura do **campo**, não da caixa |
| `layout` | `stacked` (▴▾ empilhados) ou qualquer outro valor para `−`/`+` lado a lado |
| `placeholder`, `field_class`, `step_class`, `glyph_class` | |
| `form_control`, `rules`, `msg` | repassados ao `<input>` de dentro — dentro de um `<form>`, o campo entra na validação (ver "Validação declarada no próprio `<form>`"). O `value=` continua **obrigatório**: é ele que diz onde o número mora. |

O `width` descer para o campo é a armadilha: `width="fill"` ali vira um risco
entre os dois botões, porque o campo está dentro de uma `<row>` `shrink`.

**`<slider value="volume" />`**

| atributo | default |
|---|---|
| `min` / `max` | `0` / `100` |
| `step` | `1` — o texto cru dele decide as **casas decimais** gravadas (`step="0.5"` grava `"7.5"`) |
| `shift_step` | passo fino com Shift segurado |
| `default` | valor restaurado no clique duplo |
| `vertical` | `false` |
| `on_change`, `on_release` | o segundo dispara só ao soltar — é onde vai o `fetch` |

**`<rangeslider start="preco_min" end="preco_max" />`** — dois cursores, **duas**
chaves. Mesmos `min`/`max`/`step`/`color`; `size` (default 240, entre 60 e 1600)
é o comprimento da trilha.

**`<dial value="volume" />`** — knob rotativo: arrasta, clica no arco ou rola a
roda.

| atributo | default |
|---|---|
| `min` / `max` / `step` | `0` / `100` / `1` |
| `size` | `96` (diâmetro) |
| `notches` | `0` — marcas ao redor do arco |
| `show_value` | `false` (ao contrário do `<gauge>`: um knob existe para ser girado) |
| `decimals`, `readonly`, `color`, `on_change`, `on_release` | |

**`<colorwheel value="cor" />`** — anel de matiz + quadrado saturação/valor;
grava `#rrggbb`. `size` default `220`, entre 80 e 640. `readonly="true"` mostra
sem deixar mexer.

**`<rating value="nota" />`** — estrelas com prévia no hover.

| atributo | default |
|---|---|
| `max` | `5` |
| `filled` / `empty` | `★` / `☆` — qualquer caractere serve |
| `size` | `20` |
| `readonly`, `color`, `on_change` | |

**`<shortcutinput value="atalho_salvar" />`** — captura uma combinação e grava na
forma canônica `ctrl+shift+alt+super+tecla`, nessa ordem, minúscula. Só um campo
captura por vez na tela.

**`<shortcut key="ctrl+s" on_press="salvar" />`** — atalho global. Mora no
**layout** (não no `<resources>`) e não desenha nada. A grafia da entrada é
livre (`"Shift+Ctrl+S"` casa com `ctrl+shift+s`); modificadores aceitos:
`ctrl`/`control`, `shift`, `alt`/`option`, `super`/`cmd`/`meta`/`win`.

**`<delaybutton text="Apagar tudo" on_press="apagar" />`** — só dispara depois de
**segurado**; soltar antes desiste, e o anel volta a zero. `delay` default
`1200` ms (entre 120 e 20000), `size` default `84`.

**`<form on_submit="salvar">`** — agrupa campos. Cada campo se liga com
`form_control="nome"`; Enter em qualquer um deles dispara o `on_submit`, e o
foco avança para o próximo campo (dá para preencher o formulário inteiro sem o
mouse). O `<form>` desenha como uma `<column>` — aceita `spacing`, `width`,
classe.

#### Validação declarada no próprio `<form>`

As regras moram nos campos (`rules="…"`) e o motor faz o ciclo inteiro **ao
enviar**: roda as regras, publica uma mensagem por campo, acende o destaque
visual e chama **um** de dois handlers.

```xml
<form
  name="cadastro"
  on_submit="salvar"
  on_validation_error="apontar"
  validate_on="submit"
>
  <input       form_control="nome"  rules="required|minlen:3" msg="informe ao menos 3 letras" />
  <maskedinput form_control="cpf"   rules="required|digits:11" mask="cpf" />
  <spinbox     form_control="idade" value="idade" rules="gte:18" min="14" max="90" />
  <select      form_control="uf"    options="ufs" rules="required" />
  <checkbox    form_control="aceite" rules="accepted" label="Aceito os termos" />

  <text class="erro" if="{erro_nome}" not_empty>{erro_nome}</text>

  <button type="reset"  text="Limpar" on_click="limpar" />
  <button type="submit" text="Salvar" />
</form>
```

**Atributos do `<form>`:**

| atributo | default | o que faz |
|---|---|---|
| `on_submit` | — | roda quando o envio **passa** em tudo. Com regras, só nesse caso; **sem** nenhuma regra no formulário, sempre (contrato antigo). |
| `on_validation_error` | — | roda quando o envio **falha**. Recebe as falhas como JSON: `[{"campo":"nome","msg":"…"}]`. |
| `validate_on` | `submit` | `submit`: regras só no envio; editar um campo **apaga** o erro dele. `change`: cada campo revalida a si mesmo a cada tecla. |
| `error_prefix` | `erro_` | onde as mensagens por campo são publicadas no contexto — `{erro_nome}`, `{erro_cpf}`, … |
| `name` | `""` | só para diferenciar dois `<form>` na mesma tela. |

**`rules="…"` num campo** — string estilo Laravel, `|` separa, `:` é o argumento:

| regra | falha quando |
|---|---|
| `required` | vazio |
| `minlen:N` / `maxlen:N` | menos / mais de N caracteres |
| `digits:N` ou `digits:MIN,MAX` | fora dessa contagem de **dígitos** (ignora ponto, traço, parênteses — feito para CPF e telefone) |
| `gte:N` / `lte:N` | número fora do limite |
| `email` | não parece e-mail (vazio passa — combine com `required`) |
| `accepted` | não é `true`/`on`/`1`/`yes`/`sim` — para o `<checkbox>` de "aceito os termos" |
| `fn:NOME` | a função global Luau `NOME(valor)` devolveu uma string (a mensagem). `nil` ou `""` = ok. O escape hatch para o que o vocabulário não cobre (dígito verificador de CPF, "senha ≠ login", …). |

- **`pattern="\d{11}"`** é atributo separado — uma regex tem `|` e `:` e não
  caberia na string de `rules`.
- **`msg="…"`** é a mensagem única do campo, no lugar do texto-padrão do motor
  (que é em inglês). É o que `{erro_<campo>}` mostra.
- **`:invalid` no `.gss`** acende sozinho enquanto `{erro_<campo>}` estiver
  preenchido — **não** é uma classe que o script liga:

  ```gss
  .campo:invalid { border_width: 1; border_color: var(--danger); }
  ```

- **`<button type="submit">`** dentro do `<form>` dispara o envio sem
  `on_click`; **`type="reset">`** apaga os `{erro_<campo>}` (e com eles o
  `:invalid`) e então roteia o próprio `on_click` — o handler só devolve os
  valores ao estado inicial.
- **`form_control` sem `value`/`on_change`** (ou `checked`/`on_toggle` num
  checkbox, `value` num select) liga o campo à chave de mesmo nome. Com eles
  explícitos, respeita o que você escreveu.
- **Regra malformada** (`minlen` sem número, nome de regra desconhecido) sai no
  stderr e é ignorada — não trava o envio, mas o campo deixa de ser validado.

Os handlers, no `.luau`:

```lua
-- on_submit: só roda quando o formulário inteiro passou.
function salvar(): ()
  toast({ message = "Cadastro salvo", kind = "success" })
end

-- on_validation_error: as falhas já vêm prontas.
function apontar(erros_json: string?): ()
  local erros = json.decode(erros_json or "[]")
  toast({ message = `Corrija {#erros} campo(s)`, kind = "warning" })
end

-- fn:validar_cpf — devolve a mensagem, ou nil quando ok.
function validar_cpf(v: string): string?
  return if #v:gsub("%D", "") == 11 then nil else "CPF inválido"
end
```

### Escolha em lista

**`<select options="regioes" value="regiao" />`** — dropdown fechado.

`options` é o nome de uma chave com um array JSON. Cada elemento pode ser uma
**string** (rótulo e valor iguais) ou um **objeto**:

```lua
ctx.regioes = json.encode(json.array({ "sa-east-1", "us-east-1" }))
-- ou
ctx.regioes = json.encode(json.array({
    { label = "São Paulo",   value = "sa-east-1" },
    { label = "N. Virginia", value = "us-east-1" },
}))
```

`labelField` (default `"label"`) e `valueField` (default `"value"`) renomeiam os
campos quando o JSON vem de fora com outros nomes:

```xml
<select options="paises" value="pais" labelField="nome" valueField="sigla" />
```

Um objeto sem o campo de valor usa o rótulo como valor. Um valor não-string
(número, booleano) é convertido para texto.

**`<comboedit options="servidores" value="host" />`** — dropdown **editável**:
`on_change` dispara a cada tecla, `on_select` só quando o usuário escolhe um
item existente. Mesmos `options`/`labelField`/`valueField` do `<select>`.

**`<autocomplete value="cidade" items="cidades" />`** — sugestões enquanto
digita, num painel ancorado ao campo. Ignora acento e caixa; ▲▼ navegam, Enter
aceita, Esc desiste.

| atributo | default |
|---|---|
| `items` | nome da chave com a lista (mesma forma do `<select>`) |
| `min_chars` | `1` — quantas letras antes de sugerir |
| `max_items` | `8` (entre 1 e 50) |
| `filter` | `true`; `filter="false"` mostra a lista inteira, para quando o filtro é do servidor |
| `placeholder`, `on_change`, `on_select` | |

**`<ListView items="servicos" value="servico" />`** — lista vertical com
seleção. Cada item é `{ id, label, sub }` — `sub` é a segunda linha, opcional.

| prop | default |
|---|---|
| `mode` | `single`; `multi` guarda um **conjunto** separado por vírgula na mesma chave |
| `height` | `240` |
| `virtualize` | `0` (desligado); ver "Listas longas" |
| `list_class`, `item_class`, `selected_class`, `label_class`, `sub_class` | ganchos de `.gss` |

**`<fontselect value="fonte" selected="{fonte}" />`** — a lista de famílias de
fonte, **cada uma desenhada nela mesma** (`QFontComboBox`). Lê `__fonts` por
padrão (a chave que o motor semeia com as famílias que o app registrou —
`GlacierDaemon::font_named`), ou o `items` que você der.

| atributo | default |
|---|---|
| `value` + `selected` | o par de sempre: **nome** da chave, e o valor atual |
| `items` | `__fonts` |
| `preview` | ausente — um texto de amostra abaixo da lista, na fonte selecionada |
| `height`, `width` | `220`, `fill` |

**`<tumbler value="mes" items="meses" />`** — roleta. Guarda o **texto** do item,
não o índice. O `items` aceita as três formas: nome de chave, JSON literal, ou
uma lista separada por vírgula (`items="jan,fev,mar"`).

| atributo | default |
|---|---|
| `visible` | `3` — quantos itens aparecem; forçado a ímpar (uma roleta par não tem centro) |
| `row` | `34` (altura de um item) |
| `size` | `120` (largura) |

**`<pagination value="pagina" total="20" />`** — `« ‹ 1 … 4 [5] 6 … 20 › »`.

| atributo | default |
|---|---|
| `total` | interpola: `total="{n_paginas}"` funciona |
| `window` | `5` — quantos números ao redor do atual; forçado a ímpar, entre 1 e 21 |
| `ends` | `true` — as setas `«`/`»` para a primeira e última |

`<pageindicator …/>` é a **outra tag**, com os mesmos atributos: desenha
bolinhas em vez de números. Não é um `dots="true"`.

**`<rating value="nota" max="5" />`** — descrito em "Entrada de dados"; `max`
interpola e fica preso entre 1 e 20.

### Data e hora

**Uma primitiva, três tags** — o que muda é quais seções o campo mostra. A chave
guarda **sempre ISO** (`2026-09-09`, `14:35`, `2026-09-09 14:35`); `format` muda
só a exibição.

| tag | seções |
|---|---|
| `<dateedit value="nascimento" />` | ano, mês, dia |
| `<timeedit value="hora" />` | hora, minuto (e segundo com `seconds="true"`) |
| `<datetimeedit value="quando" />` | as duas famílias no mesmo campo |

| atributo | valor |
|---|---|
| `format` | `br`, `dmy` ou `dd/mm/yyyy` exibem dia antes do mês; qualquer outro valor mantém ISO |
| `seconds="true"` | acrescenta a seção de segundos |
| `calendar_popup="true"` | abre a grade de mês ancorada ao campo (ignorado num `<timeedit>`, que não tem data para escrever) |
| `today` | a data de hoje, **interpolada** (`today="{hoje}"`) |
| `min`, `max` | limites em ISO |

As setas ▴▾ agem na seção ativa, e cada seção **vira dentro de si**: no minuto
59, ▴ vai para 00 sem mexer na hora.

E a grade, que é **outra** primitiva com três tags:

**`<calendar value="dia" />`** — grade 7×6, com drill-up dia → mês → ano ao
clicar no título.

| atributo | default |
|---|---|
| `value` | chave da data escolhida |
| `today` | interpolado; **sem ele nenhum dia é destacado** |
| `min`, `max` | limites em ISO |
| `first_day` | `sunday`; `monday`/`segunda`/`1` começa a semana na segunda |
| `months` | `1` (entre 1 e 4) — quantas grades lado a lado |
| `month` | nome de chave com o mês visível, para controlá-lo de fora |
| `month_names`, `day_names` | listas separadas por vírgula, para trocar o idioma |

**`<monthyearpicker value="competencia" />`** — só mês/ano; grava `YYYY-MM`.
Com `mode="year"` grava `YYYY`.

**`<daterangepicker start="de" end="ate" months="2" />`** — intervalo, com
`start` e `end` em chaves separadas.

O motor **não usa crate de data**: `today="{hoje}"` vem de `date.today()` no
Luau, e a aritmética toda está no módulo `date` (ver a seção da camada Luau).
Sem a prop, nenhum dia é destacado — degradação aceitável, não bug.

### Medidores e gráficos

**`<gauge value="cpu" />`** — medidor de arco com faixas coloridas e agulha.

| atributo | default | o que faz |
|---|---|---|
| `value` | — | **nome da chave** com o número atual |
| `min` / `max` | `0` / `100` | as pontas da escala |
| `size` | `132` | diâmetro em pixels |
| `thickness` | `14` | espessura do arco |
| `start` | `135` | ângulo inicial em graus (0 = leste, cresce no sentido horário) |
| `sweep` | `270` | quantos graus o arco varre |
| `color` | tema | cor do trecho preenchido — só tem efeito **quando não há faixas** |
| `bands` | vazio | as faixas coloridas — ver abaixo |
| `needle` | `false` | desenha a agulha em vez de só o arco preenchido |
| `show_value` | `true` | o número no meio (ao contrário do `<dial>`) |
| `decimals` | `0` | casas do número no meio |
| `unit` | vazio | sufixo colado no número: `unit="%"` → `73%` |
| `label` | vazio | uma legenda sob o número |

`start="180" sweep="180"` faz o meio-arco clássico (de oeste a leste, por cima).

#### `bands`, por inteiro

`bands` é um **array JSON de objetos**, cada um dizendo *até onde* aquela cor
vale. É uma escada, não uma lista de intervalos: cada faixa começa onde a
anterior terminou, e a primeira começa no `min`.

| campo | apelidos | obrigatório |
|---|---|---|
| `to` | `ate`, `até`, `max` | sim — o limite superior, na escala de `min`..`max` |
| `color` | `cor` | sim — `#rrggbb` ou `#rrggbbaa` |

Um objeto sem um dos dois, ou com cor que não é hexadecimal, é **descartado em
silêncio**. As faixas são ordenadas pelo limite antes de desenhar, então a
ordem em que você as escreve não importa.

Escrito direto no atributo (aspas simples por fora, porque o JSON usa as
duplas):

```xml
<gauge value="cpu" unit="%" needle="true"
       bands='[{"to":60,"color":"#A6E3A1"},
               {"to":85,"color":"#F9E2AF"},
               {"to":100,"color":"#F38BA8"}]' />
```

Isso pinta 0–60 verde, 60–85 amarelo, 85–100 vermelho.

Ou vindo do contexto, quando os limites são dado e não desenho — `bands` aceita
o **nome de uma chave** exatamente como aceita o JSON:

```xml
<gauge value="meta" bands="faixas_da_meta" />
```
```lua
ctx.faixas_da_meta = json.encode(json.array({
    { to = tonumber(ctx.limite_ok),    color = "#A6E3A1" },
    { to = tonumber(ctx.limite_alerta), color = "#F9E2AF" },
    { to = 100,                         color = "#F38BA8" },
}))
```

O motor decide entre as duas formas assim: **se o texto do atributo é o nome de
uma chave existente, usa o valor dela; senão, tenta parsear o próprio texto como
JSON.** Uma consequência prática: um `bands` com JSON inválido não dá erro, só
apaga as faixas e deixa o arco na cor de `color`.

**Faixas mudam o que o arco significa.** Sem `bands`, o arco é uma barra de
progresso curva: o trilho inteiro é desenhado em tom fraco e o `color` preenche
só até o valor atual. Com `bands`, cada faixa é pintada **inteira**, do começo
da escala até o limite dela, independentemente do valor — o arco vira a escala,
e quem aponta o valor é a agulha. Por isso `bands` quase sempre anda com
`needle="true"`: sem ela, o medidor mostra as zonas e não mostra a leitura.

E por isso também o `color` fica sem efeito quando há faixas: agulha, número e
legenda saem do tema, não dele.

#### Os gráficos

Todos leem `items` como **nome de uma chave** — aqui não vale JSON inline — com
um array de pontos:

```lua
ctx.serie = json.encode(json.array({
    { label = "seg", value = 12 },
    { label = "ter", value = 31 },
    { label = "qua", value = 24 },
}))
```

| campo do ponto | apelidos | ausente vira |
|---|---|---|
| `label` | `rotulo`, `rótulo`, `nome`, `x` | a posição do item (1, 2, 3…) |
| `value` | `valor`, `y` | `0` |

Um elemento que é **número solto** (`[12, 31, 24]`) também funciona: vira um
ponto com aquele valor e a posição como rótulo. Chave ausente, JSON inválido ou
raiz que não é array dão uma **série vazia**, que desenha a moldura sem a linha.

**`<linechart items="serie" />`**

| atributo | default |
|---|---|
| `min` / `max` | automáticos, com escala 1·2·5 |
| `color` | tema |
| `area` | `false` — preenche sob a linha |
| `points` | `false` — marca cada ponto |
| `axes` / `grid` | `true` |
| `thickness` | `2` |
| `series` | — nome de uma chave com **várias** séries (ver abaixo); presente, vence `items` |

**Série múltipla** (só o `<linechart>`/`<sparkline>`): `series="chave"`, onde a
chave guarda um array de objetos `{ name, points, color? }`. `points` aceita as
mesmas duas formas de `items`. Sem `color`, cada linha pega uma cor do ciclo do
tema e uma legenda aparece no canto (só com `axes`). `<barchart>`/`<piechart>`
seguem série única.

```lua
ctx.carga = json.encode(json.array({
    { name = "API", points = json.array({ 12, 19, 7 }) },
    { name = "DB",  points = json.array({ 20, 15, 22 }), color = "#89B4FA" },
}))
```

**`<sparkline items="serie" />`** é a mesma primitiva com `axes` e `grid`
default `false` e `thickness` `1.5`: a linha sem moldura, para caber numa célula
de tabela.

**`<barchart items="serie" />`** — mesmos `min`/`max`/`color`/`axes`/`grid`,
mais `colorful="true"` para uma cor por barra. A base é sempre o **zero** quando
`min` não é declarado, e não o menor valor — uma barra que começa em 40 mente
sobre a proporção.

**`<piechart items="fatias" />`** e **`<donut items="fatias" />`** — a mesma
primitiva; `<donut>` é `donut="0.6"`. O `label` de cada ponto vira a legenda e o
`value`, o tamanho da fatia.

| atributo | default |
|---|---|
| `size` | diâmetro |
| `donut` | `0` no `<piechart>`, `0.6` no `<donut>` — a fração do raio que fica vazada |
| `percentages` | `false` — escreve o percentual em cada fatia |
| `colors` | a paleta do tema; aceita chave, JSON (`'["#f00","#0f0"]'`) **ou** lista por vírgula (`colors="#f00,#0f0"`) |

#### `<canvas>` — o desenho declarativo

Uma superfície de desenho cujos **filhos são formas**, desenhadas na ordem do
markup. Sem `width`/`height`, é `300`×`200`.

```xml
<canvas class="tela">
  <rect x="10" y="10" w="150" h="70" rx="8" class="solido" />
  <circle cx="220" cy="45" r="30" class="contorno" />
  <line x1="10" y1="110" x2="270" y2="110" class="regua" />
  <polyline points="20,180 60,150 100,190" class="contorno" />
  <polygon points="220,150 270,150 245,195" class="solido" />
  <arc cx="80" cy="255" r="34" start="150" sweep="240" class="solido" />
  <path d="M140 290 Q 180 210 220 290 T 300 290" class="contorno" />
  <text x="16" y="315" class="rotulo">rótulo</text>
</canvas>
```

| forma | geometria |
|---|---|
| `<path>` | `d` — SVG parcial: `M L H V Z` + `C Q` (maiúsculo absoluto, minúsculo relativo). **Sem `A`** — use `<arc>` |
| `<arc>` | `cx cy r start sweep` (graus, `start=0` à direita, horário). Com `fill`, é um setor |
| `<circle>` | `cx cy r` |
| `<rect>` | `x y w h` (`rx` arredonda) |
| `<line>` | `x1 y1 x2 y2` |
| `<polyline>` / `<polygon>` | `points="x,y x,y …"` — a segunda fecha |
| `<text>` | `x y` + texto como filho; segue as regras de um `<text>` normal |

- **Geometria é dado**: `cx="{x}"`, `d="{traçado}"` — inline no `.gv`.
- **Traço e preenchimento são estilo**: `fill` / `stroke` / `stroke-width` numa
  **classe `.gss`** (apelidos de `background` / `border-color` / `border-width`).
- Sem `on_click`/hover/animação numa forma.

### Model/view: tabela e árvore

**`<tableview items="linhas" columns="colunas" value="sel" />`** — cabeçalho,
ordenação por clique, seleção e colunas arrastáveis.

`items` é o nome de uma chave com um array de **objetos**; cada coluna diz de
qual campo lê.

```lua
ctx.linhas = json.encode(json.array({
    { id = "1", servico = "api",   estado = "ok",    latencia = 42 },
    { id = "2", servico = "cache", estado = "alerta", latencia = 310 },
}))
```

`columns` aceita as **duas** formas:

1. o nome de uma chave com um array JSON de colunas, que é a forma completa:

```lua
ctx.colunas = json.encode(json.array({
    { key = "servico",  label = "Serviço" },
    { key = "estado",   label = "Estado",   width = "120" },
    { key = "latencia", label = "ms",       width = "80", align = "right" },
}))
```

| campo da coluna | apelidos | default |
|---|---|---|
| `key` | `campo`, `id` | — o campo do item que a célula mostra |
| `label` | `rotulo` | o próprio `key` |
| `width` | `largura` | `auto` — aceita os mesmos tokens da especificação de trilhas |
| `align` | `alinhamento` | `start`; aceita `right`/`direita`/`end` e `center`/`centro` |

2. ou uma **especificação de trilhas** escrita direto (`columns="fill 120 80"`),
quando os cabeçalhos não importam.

| atributo do `<tableview>` | default |
|---|---|
| `value` | chave da linha selecionada (o `id` do item) |
| `mode="multi"` | seleção múltipla, guardada como conjunto separado por vírgula |
| `sort` | nome de chave onde a ordenação é gravada; sem ela o cabeçalho não ordena |
| `widths` | nome de chave onde as larguras arrastadas são gravadas |
| `row_height` | `0` (automático) |
| `virtualize` | ver "Listas longas" |
| `on_select` | |

**`<tableheader columns="…" widths="cols" />`** — o mesmo cabeçalho **sem** o
corpo, para quem monta as linhas à mão com um `for-each`. Compartilhar a chave
de `widths` entre ele e as linhas é o que mantém tudo alinhado.

**`<treeview items="arvore" open="abertos" />`** — árvore expansível. O item:

| campo | apelidos | default |
|---|---|---|
| `id` | — | um item sem `id` **e** sem `label` é descartado |
| `label` | — | o `id` |
| `items` | `children`, `filhos` | array de filhos, recursivo |

A identidade de um nó é o **caminho** — os `id` dos ancestrais unidos por `/`.
É isso que `open` guarda, como um conjunto:

```lua
ctx.abertos = "raiz,raiz/src,raiz/src/widgets"
```

Aceita vírgula, ponto e vírgula ou espaço como separador na leitura. `value`
guarda o caminho do nó selecionado, `indent` (default `16`, entre 0 e 64) é o
recuo por nível.

**`<columnview items="arvore" value="sel" />`** — navegação Miller (as colunas
do Finder), sobre a **mesma** forma de árvore do `<treeview>`. `column_width`
default `180` (entre 60 e 800); `path` é o nome de uma chave com o caminho
aberto.

### Navegação e agrupadores

Os itens de `<TabBar>` e `<Tabs>` são `{ id, label }`; o `id` é o que a chave
recebe e o que o `<template slot="…">` casa.

```lua
ctx.abas = json.encode(json.array({
    { id = "geral", label = "Geral" },
    { id = "rede",  label = "Rede" },
}))
```

**`<TabBar items="abas" value="aba" active="{aba}" />`** — só a barra. Props de
estilo: `tab_class`, `tab_active_class`, `label_class`, `padding` (`7 14`),
`size` (13), `spacing` (2).

**`<Tabs items="abas" value="aba" active="{aba}">`** — a barra **e** a página.
Cada página é um `<template slot="id_da_aba">` no corpo:

```xml
<Tabs items="abas" value="aba" active="{aba}">
  <template slot="geral"> … </template>
  <template slot="rede">  … </template>
</Tabs>
```

Props extras: `page_class`, `page_spacing` (12), `tab_padding` (`7 14`).

**`<StackView active="{passo}">`** — as páginas **sem** a barra; escolhe pelo
nome do slot, igual ao `<Tabs>`. É o que se usa quando a navegação está noutro
lugar da tela.

**`<swipeview value="pagina">`** — páginas trocadas **arrastando**; escolhe por
**posição** (a chave guarda o índice, começando em 0), não por nome.
`threshold` default `120` px é a distância mínima para virar a página.

**`<Wizard steps="dados,rede" value="passo">`** — assistente completo: cabeçalho
com os títulos, navegação e validação.

| prop | o que é |
|---|---|
| `steps` | lista de ids separada por vírgula, na ordem |
| `titles` | os rótulos, na mesma ordem |
| `value` | nome da chave com o passo atual |
| `valid` | **interpolado** (`valid="{form_ok}"`); falso trava o botão "avançar" |
| `on_finish`, `on_cancel` | ações |
| `back_label`, `next_label`, `finish_label`, `cancel_label` | textos dos botões |
| `header="false"` | esconde o cabeçalho de passos |

Cada passo é um `<template slot="id_do_passo">`, como no `<Tabs>`.

**`<wizardnav steps="…" value="passo" valid="{ok}" />`** — só a barra de botões
(voltar inerte no primeiro, "finalizar" no último), para quem monta o resto à
mão.

**`<Accordion>` + `<AccordionItem>`** — **várias** seções abertas ao mesmo
tempo, guardadas num conjunto numa chave só:

```xml
<Accordion>
  <AccordionItem value="abertas" id="rede" title="Rede"> … </AccordionItem>
  <AccordionItem value="abertas" id="disco" title="Disco"> … </AccordionItem>
</Accordion>
```

Props do item: `id`, `title`, `sub`, `value` (a chave do conjunto), `duration`
(180), `padding` (12), e as classes `head_class`, `body_class`, `title_class`,
`sub_class`, `mark_class`.

**`<ToolBox>` + `<ToolBoxItem>`** — o mesmo, com **uma** aberta por vez (a chave
guarda um id, não um conjunto).

**`<GroupBox title="Rede">`** — moldura com título. `slot="actions"` põe
controles na linha do título; `flat="true"` tira a borda. Props: `padding` (12),
`spacing` (8), `title_size` (13), `frame_class`, `header_class`,
`content_class`, `actions_class`.

**`<Frame shape="box">`** — a moldura sozinha: `box` (default), `filled` ou
`none`. `background`, `padding` (12), `spacing` (8).

**`<Card title="Servidor" subtitle="produção">`** — superfície de um item.
`slot="footer"` só é desenhado quando preenchido. Props: `padding` (16),
`spacing` (12), `title_size` (16), `subtitle_size` (13), `header_class`,
`body_class`, `footer_class`.

**`<Drawer value="menu" open="{menu}">`** — painel lateral que **empurra** o
conteúdo (quem cobre é um `<popover>`). Props: `size` (240), `duration` (180),
`padding` (12), `panel_class`.

### Sobreposição

**`<stack>`** — descrito em "Layout e estrutura": camadas no mesmo espaço, com
`anchor` ou `x`/`y` no filho.

**`<popover value="menu">`** — conteúdo flutuante **ancorado ao gatilho**, que
vira de lado quando não cabe na janela. O gatilho é o filho com `slot="anchor"`;
o resto é o painel.

| atributo | default | valores |
|---|---|---|
| `value` | — | nome da chave que guarda aberto/fechado |
| `placement` | `bottom` | `top`, `bottom`, `left`, `right`, `center` |
| `align` | `start` | `start`, `center`, `end` — no eixo **transversal** ao `placement` |
| `offset` | `4` | folga em pixels entre gatilho e painel |
| `dismiss` | `true` | clicar fora fecha |
| `trigger` | `true` | `trigger="none"` faz o gatilho não abrir sozinho — o script controla |
| `panel_width` | natural | `anchor` copia a largura do gatilho, ou um número em pixels. **Não use `width`**: nele, `width` é a largura do gatilho, que é quem está no fluxo |
| `on_close` | | |

Sem nenhum filho marcado com `slot="anchor"`, o **primeiro** filho vira o
gatilho e o resto, o painel. Abrir, fechar por clique fora, por Esc e por novo
clique no gatilho já vêm prontos — não é preciso uma linha de script.

**`<popup value="modal">`** é a mesma primitiva com `placement="center"`: sem
âncora, centrado na janela.

**`<NotificationDot show="{tem_alerta}">`** — pontinho num canto do que ele
embrulha. Props: `show` (truthy, default `true`), `anchor` (`top-right`), `size`
(10), `dot_class`.

**`<SplashScreen show="{carregando}">`** — cobre o conteúdo principal. O
conteúdo normal é o `<slot/>`; o painel de cima é o `slot="splash"`:

```xml
<SplashScreen show="{carregando}" background="#1e1e2e">
  <template slot="splash">
    <column align_x="center" spacing="12">
      <spinner />
      <text>Carregando…</text>
    </column>
  </template>

  <column class="tela"> … o app … </column>
</SplashScreen>
```

`show` é **truthy**: qualquer valor liga, e vazio, `"false"` ou `"0"` desligam.
A forma idiomática de fechar é apagar a chave (`ctx.carregando = nil`).

Este widget já falhou de um jeito que vale conhecer: o template dele testava
`not_equals="false"`, e como o valor "desligado" é a string **vazia**, a
condição `"" != "false"` era sempre verdadeira e o painel nunca sumia. Sempre
que um `<template if>` for sobre visibilidade, deixe-o **sem** comparador.

**`<rubberband items="caixas" selection="marcados" />`** — retângulo de seleção
arrastado sobre uma área. Cada alvo é `{ id, x, y, w, h }` (o `id` cai para o
índice quando falta), e `items` aceita chave **ou** JSON inline. A seleção sai
como conjunto separado por vírgula na chave de `selection`.

**`<dock mode="lado" edge="left">`** — o `QDockWidget`: um painel + um centro.
**Dois filhos** — o painel (0) e o centro (1). N painéis = `<dock>` aninhados.

```xml
<dock mode="lado" edge="left" size="tam_painel" float_x="px" float_y="py"
      title="Explorador" on_change="salvar_layout">
  <tree items="arvore" value="no" abertos="{abertos}" />
  <texteditor value="doc" />
</dock>
```

| atributo | default | o que faz |
|---|---|---|
| `mode` | — | **nome** da chave: `left`/`right`/`top`/`bottom` (acoplado), `float`, `hidden`. Vazio = fixo em `edge`, sem cabeçalho interativo |
| `edge` | `left` | borda quando a chave está vazia |
| `size` | vazio | **nome** da chave com a trilha do `<splitter>` (`"240 fill"`). Vazio = repartem igual, sem alça |
| `float_x` / `float_y` | `__dock_<mode>_x`/`_y` | **nome** das chaves de posição flutuante |
| `title` | vazio | texto do cabeçalho |
| `on_change` | vazio | ação disparada **depois** de cada mudança (botão ou arrasto) — o gancho de persistência |
| `min` / `handle` / `float_w` / `float_h` | `120` / `6` / `280` / `220` | piso e alça do acoplado; tamanho do flutuante |

O cabeçalho tem `❒`/`▣` (flutua / reacopla, guardando o modo em `<mode>__prev`),
`✕` (esconde), e é **arrastável**: puxar para uma borda reancora **na soltura**.
Um painel `hidden` deixa uma aba `▸` que o traz de volta. Persistir o layout:
declare `on_change` e no handler grave as chaves (`storage.set` no Luau).

### Menus, barras e janela

**`<menubar>`** contém `<menu label="Arquivo">`, que contém `<menuitem>`,
`<menuseparator />` e outros `<menu>` (submenus, a profundidade arbitrária).

| tag | atributos |
|---|---|
| `<menu>` | `label`, `icon`, `disabled`, `items` |
| `<menuitem>` | `label`, `icon`, `on_click`, `checked` (nome de chave, truthy), `disabled` |
| `<menuseparator />` | — |
| `<contextmenu items="acoes">` | botão direito no **primeiro** filho; o resto é o menu |

`items`, nos três que o aceitam, é o **nome de uma chave** com um array JSON que
o motor mescla ao menu estático:

```lua
ctx.acoes = json.encode(json.array({
    { label = "Abrir",   action = "abrir" },
    { separator = true },
    { label = "Recentes", items = { { label = "app.gv", action = "abrir_recente" } } },
}))
```

| campo | apelidos |
|---|---|
| `label` | `text` |
| `action` | `onClick`, `on_click` |
| `icon`, `disabled`, `checked` | — |
| `separator` | `isSeparator` — sozinho já basta, vira uma linha |
| `items` | submenu, recursivo |

O `checked` de um `<menuitem>` só **mostra** o check: quem o alterna é o handler
do `on_click`.

Um detalhe que só morde dentro de um componente: a `action` vinda do **JSON**
não recebe o prefixo do componente que o `on_click` escrito no markup recebe.
Na prática funciona, porque uma ação sem prefixo cai de volta na tela ativa;
para um menu que pertence a outro componente, escreva o prefixo à mão
(`action = "OutroComponente::acao"`).

**`<ToolBar>` + `<ToolButton>`** — faixa de ações.

| prop do `<ToolButton>` | default |
|---|---|
| `icon` | `●` — um caractere ou emoji |
| `icon_src` | um `.svg`, no lugar do `icon` |
| `icon_size` | `16` |
| `icon_color` | tema |
| `text` | o rótulo |
| `layout` | `icon` (só o ícone), `beside` (ao lado), `under` (embaixo) |
| `on_click`, `tooltip` | |

`<ToolBar>` tem `divider` (default `true`), `padding` (`6 8`), `spacing` (4),
`align_y` (`center`).

**`<StatusBar message="{status}">`** — mensagem à esquerda, permanentes à direita
pelo `<slot/>`. Props: `divider` (true), `size` (12), `padding` (`4 10`).

**`<ButtonBox accept="Salvar" on_accept="…" reject="Cancelar" />`** — os três
papéis, na ordem da plataforma.

| papel | rótulo | ação | classe | aparência |
|---|---|---|---|---|
| aceitar | `accept` | `on_accept` | `accept_class` | destaque, cor primária |
| recusar | `reject` | `on_reject` | `reject_class` | discreto |
| destrutivo | `destructive` | `on_destructive` | `destructive_class` | vermelho, à esquerda |

**Um botão sem rótulo não aparece** — uma caixa só com `accept` é um botão só.
`order` (`gnome` ou `windows`) força a ordem; sem ele, vale a do alvo de
compilação. `class` no uso pinta a `<Row>` inteira, não os botões.

**`<CommandLink title="Instalação típica" description="…" on_click="…" />`** —
botão de duas linhas com seta, o "próximo passo" de um assistente.

**`<RoundButton text="+" color="#89B4FA" size="48" on_click="…" />`** — botão
circular. O `color` **precisa** existir: o `<Button>` só aplica `border_radius`
dentro do fecho de estilo que a cor liga, então sem cor sai um retângulo. O
default é `#45475A` justamente por isso.

**`<SizeGrip />`** — canto de redimensionar, para apps com titlebar própria.
`corner` default `se`, `size` (14).

**`<mdiarea>` / `<mdisubwindow>`** — descritos em "Layout e estrutura".

**`<shortcut key="ctrl+s" on_press="salvar" />`** — atalho global, no layout.

### Estrutura de template

Estas não desenham nada — decidem o que existe.

**Condicional.** Os comparadores valem em `<template>` **e** em qualquer tag:

| forma | testa |
|---|---|
| `if="{chave}"` | truthy: vazio, `"false"` e `"0"` são falsos |
| `if="{aba}" equals="rede"` | igualdade textual |
| `if="{estado}" not_equals="ok"` | diferença |
| `if="{papel}" one_of="admin editor"` | pertence à lista **escrita no atributo**, separada por espaço (o atributo interpola: `one_of="{permitidos}"` também vale) |
| `if="{tags}" contains="urgente"` | o simétrico: a lista está na **chave**, o item no atributo. Separadores aceitos: vírgula, ponto e vírgula, espaço |
| `if="{itens}" not_empty` | a chave guarda um **array JSON** com pelo menos um elemento (e `empty` para o inverso) |
| `platform="desktop"` | `desktop` ou `web` — não são nomes de sistema operacional |

`empty`/`not_empty` são sobre **lista JSON**, não sobre texto: um valor que não
parseia como array conta como vazio. Para testar uma string, use o teste truthy
(`if="{erro}"`) ou `not_equals=""`.

`else-if` e `else` encadeiam com o `if` **imediatamente anterior**, no mesmo
nível:

```xml
<template if="{estado}" equals="ok">      <text class="ok">no ar</text></template>
<template else-if="{estado}" equals="lento"><text class="alerta">lento</text></template>
<template else>                            <text class="erro">fora</text></template>
```

Uma escada que não casa nenhum ramo não é erro — é um buraco na tela, sem aviso.
Termine sempre com um `<template else>` quando o valor puder ser inesperado.

**Repetição.** `for-each` é um **atributo**, na própria tag repetida:

```xml
<Card for-each="servicos" var="s" title="{s.nome}" estado="{s.estado}" />
```

`for-each` recebe o **nome da chave**; `var` batiza o item. Dentro do corpo:

| forma | quando |
|---|---|
| `{s.campo}` | o item é um objeto |
| `{s}` | o item é um escalar (string ou número na lista) |
| `{s.__dragging}` | `"true"` enquanto **este** item está sendo arrastado |

Um `<template for-each>` repete o **conteúdo** sem criar uma caixa em volta.
Para reordenar arrastando, o par é `on_reorder` (a ação) + `reorder_key` (o
campo que identifica o item); `drag_handle` restringe o arrasto a um filho.

**Slots.**

| forma | lado |
|---|---|
| `<slot />` | dentro do componente: o buraco padrão |
| `<slot name="footer" />` | dentro do componente: um buraco nomeado |
| `<template slot="footer">` | no uso: etiqueta o conteúdo para aquele buraco |

Conteúdo sem `slot` vai para o `<slot/>` sem nome. Um `<slot name="x"/>` que
ninguém preencheu simplesmente não desenha nada.

**Recursos.**

| tag | onde |
|---|---|
| `<link rel="stylesheet" href="app.gss" />` | `<resources>`; a folha vale **globalmente** |
| `<link rel="theme" href="theme.json" />` | `<resources>` |
| `<link rel="import" href="views/cartao.gv" />` | `<resources>` |
| `<link rel="data" as="paises" href="paises.json" />` | `<resources>`; `as` é obrigatório |
| `<script src="scripts/app.luau"></script>` | `<resources>` |
| `<style> … </style>` | folha embutida; **global** por default, `scoped="true"` a prende ao componente |
| `<dialog name="config">` | `<resources>`; abre com a ação `dialog:config` |

Um `<style>` num componente é global a menos que você escreva
`scoped="true"` — é a inversão que mais surpreende quem vem do Vue.

### Diálogos não são tags

Um modal do sistema é uma **chamada**, não markup — ele suspende o script e
volta com a resposta:

```lua
if confirm({ title = "Apagar?", message = "Não dá para desfazer." }) then … end
local nome = prompt({ title = "Nome do serviço" })
local cor  = pick_color({ value = ctx.cor })
local arq  = open_file({ filters = { { name = "Imagens", extensions = { "png", "jpg" } } } })
toast({ kind = "success", message = "Salvo" })
progress({ label = "Enviando…" })  progress_set(40)  progress_close()
```

A seção "Todas as funções da camada Luau" documenta cada um. O único que é
markup é o `<dialog name="…">`, para um modal com **corpo próprio** — a próxima
seção o cobre inteiro.

### O `<dialog>` — o modal com corpo em markup

Um `<dialog name="X">` é uma **declaração**, não um widget: nada desenha onde a
tag está escrita. Ela registra um template sob o nome `X` (o corpo da tag) e
uma moldura ao lado. O que faz o modal aparecer é a ação **`dialog:X`** de
qualquer botão/menuitem. Ele fecha sozinho quando um botão dele é clicado.

```xml
<screen>
  <resources>
    <dialog name="editar_servico"
            title="Editar serviço"
            icon="none"
            dismissible="true"
            buttons="Cancelar::|Salvar:salvar_servico:accept">
      <column class="form">
        <text class="rotulo">Nome</text>
        <textinput value="__dialog.nome" on_change="__dialog.nome"
                   placeholder="api-gateway" class="preenche" />
        <spinbox value="__dialog.replicas" min="1" max="32" width="110" />
        <checkbox label="Reiniciar" checked="__dialog.restart"
                  on_toggle="__dialog.restart" />
      </column>
    </dialog>
  </resources>

  <button text="Editar" on_click="dialog:editar_servico" />
</screen>
```
```lua
function salvar_servico()
  -- No aceite, o rascunho AINDA está no contexto. Leia aqui.
  local nome     = ctx["__dialog.nome"]     or ""
  local replicas = tonumber(ctx["__dialog.replicas"]) or 1
  local restart  = ctx["__dialog.restart"] == "true"
  ctx.ultimo = nome .. " · " .. replicas .. (restart and " · restart" or "")
end
```

#### Atributos

| atributo | default | o que faz |
|---|---|---|
| `name` | — (**obrigatório**) | como o modal é aberto (`dialog:<name>`) e o nome do template do corpo. **Único no app inteiro** — os diálogos vivem num mapa global e são singleton (só um aberto por vez) |
| `title` | — | título do cartão; vazio esconde a linha do cabeçalho |
| `message` | — | um texto acima do corpo; vazio some (não vira linha em branco). Quase sempre ausente num diálogo com conteúdo — o conteúdo já diz o que ele pede |
| `icon` | `none` | `information` (`info`/`informacao`), `warning` (`warn`/`aviso`), `error` (`critical`/`erro`), `question` (`pergunta`), `none`. Um valor desconhecido vira `none`, sem erro |
| `buttons` | um `Fechar` | a lista compacta — ver abaixo |
| `dismissible` | `true` | se clicar no fundo escurecido fecha (sem despachar nada). `false` obriga a escolher um botão |

Qualquer outro atributo é **erro posicionado** (linha e coluna).

#### `buttons=` — a lista compacta

Botões separados por `|`; cada um é **`Rótulo:ação:papel`** (ação e papel
opcionais). O parsing:

- o **rótulo** sai do **primeiro** `:`;
- o **papel**, quando é uma palavra-chave conhecida, sai do **último** `:`;
- **o que sobra no meio é a ação inteira — `:` e tudo**. É isso que deixa
  `Voltar:dialog:editar:neutral` chegar à ação `dialog:editar` (encadear para
  outro modal) em vez de despachar só `"dialog"`.

| forma | vira |
|---|---|
| `Salvar:salvar_perfil:accept` | rótulo `Salvar`, ação `salvar_perfil`, papel `accept` |
| `Salvar:salvar_perfil` | idem — **papel ausente com ação escrita ⇒ `accept`** |
| `Cancelar::` / `Cancelar:` / `Cancelar` | rótulo `Cancelar`, **ação vazia ⇒ só fecha**, não despacha nada; papel `neutral` |
| `Voltar:dialog:editar:neutral` | encadeia: fecha este, abre o `<dialog name="editar">` |
| `Remover:remover:destructive` | papel `destructive` (tom de perigo) |
| `Salvar:MeuComp::salvar:accept` | ação `MeuComp::salvar` — o `::` de dono, para um modal encapsulado num componente (ver adiante) |

Papéis (**só mudam a cor**, nunca o roteamento): `accept`/`aceitar`/`principal`,
`neutral`/`neutro`/`cancel`/`cancelar`, `destructive`/`destrutivo`/`perigo`/`danger`.

Casos de borda: `buttons=""` (presente e vazio) → **nenhum** botão, só o fundo
fecha (útil num `progress` que não dá para cancelar). Sem o atributo → um único
`Fechar` neutro que só fecha.

#### O corpo e as chaves `__dialog.*`

O corpo do `<dialog>` é um template comum, **avaliado no contexto do app** — ele
enxerga toda chave que a tela enxerga (as `options` de um `<select>`, um
`{titulo}`…). É isso que faz um diálogo com campo **dispensar estado por
instância**: o que o usuário digita mora numa chave comum, como em qualquer
`<textinput>`.

- **Convenção:** prefixe as chaves do corpo com `__dialog.` (`__dialog.nome`,
  `__dialog.cor`). Um `<textinput value="__dialog.nome" on_change="__dialog.nome">`
  grava nessa chave pelo binding legado (a ação é o nome da chave; sem um
  handler com esse nome, o motor escreve o valor ali).
- **O rascunho sobrevive até o handler ler.** Quando o botão de aceite despacha
  a ação, as chaves `__dialog.*` **ainda estão no contexto**; o handler as lê; o
  motor as apaga **depois**. (Numa etapa em que o handler abre OUTRO diálogo, o
  rascunho novo é preservado.)
- **A segunda abertura vem limpa** — a limpeza no fechamento é o que impede o
  modal de reabrir preenchido com a resposta da vez anterior. Para abrir
  **semeado** de propósito, escreva as chaves antes do `dialog:X` (de um handler,
  ou `ctx.show_dialog` no Rust).

#### Abrir, fechar, encadear

| como | de onde |
|---|---|
| `on_click="dialog:X"` | qualquer `<button>`/`<menuitem>`, e um botão de outro diálogo |
| `dialog:close` / `dialog:fechar` | fecha o que estiver aberto |
| um botão com ação `dialog:Y` no `buttons=` | fecha este e abre o `Y` (wizard em modal) |
| `ctx.show_dialog(DialogSpec::…)` | do Rust — recebe o **nome** de um template já registrado em `with_body` |
| `confirm{}` / `prompt{}` / `pick_color{}` / `progress{}` | do Luau — os suspensivos, que **não** são markup |

Um `dialog:X` cujo `X` não existe é **ignorado em silêncio** (a alternativa
seria derrubar o app por um typo; quem aponta isso é a validação de template).

#### Onde o `<dialog>` pode ser declarado

A coleta das declarações é uma **varredura recursiva** da árvore — não só do
`<resources>` da tela. Duas composições saem disso:

**1. Um componente que encapsula o próprio modal.** Declare o `<dialog>`, o
botão que o abre e o `<script>` do handler **dentro do arquivo do componente**:

```xml
<!-- views/editor_rotulo.gv -->
<component>
  <resources>
    <script src="editor_rotulo.luau"></script>
    <dialog name="editor_rotulo_dlg" title="Editar rótulo"
            buttons="Cancelar::|Salvar:EditorRotulo::salvar:accept">
      <column class="form">
        <textinput value="__dialog.texto" on_change="__dialog.texto" class="preenche" />
      </column>
    </dialog>
  </resources>
  <button text="Editar…" on_click="dialog:editor_rotulo_dlg" />
</component>
```

- O `dialog:` do `on_click` **não é namespaceado** — ele é um prefixo que o
  motor consome sozinho (como `window:`/`clipboard:`), então funciona igual
  dentro de um componente com `<script>`.
- O botão de aceite **precisa do `::` de dono** (`EditorRotulo::salvar`) para a
  ação voltar ao componente, e não à tela. `EditorRotulo` é o `name=` do
  `<import>` que trouxe o arquivo. Isso só resolve se o componente **tem
  `<script>`** — sem ele, `MeuComp::salvar` cai na tela ativa (é o comportamento
  correto: um componente sem script não é dono de handler nenhum, e aí o
  handler mora na tela e o `buttons=` usa a forma simples `Salvar:salvar:accept`).

**2. Um `<dialog>` cujo corpo usa um componente.** O corpo é template comum:

```xml
<dialog name="editar_perfil" buttons="Cancelar::|Salvar:salvar_perfil:accept">
  <column class="form">
    <CampoForm label="Nome">
      <textinput value="__dialog.nome" on_change="__dialog.nome" class="preenche" />
    </CampoForm>
  </column>
</dialog>
```

O conteúdo passado como `<slot/>` de `<CampoForm>` pertence a **quem escreveu**
(a tela), então `on_change="__dialog.nome"` fica sem prefixo e grava a chave
normal. Um componente no corpo que tenha `<script>` próprio segue namespaceando
as ações dele como sempre.

Exemplo completo das duas direções: `examples/onda8b_luau`.

#### Largura dos campos — a armadilha de sempre

O cartão do diálogo é limitado, mas os containers do corpo nascem `shrink`. Para
um campo esticar, a **cadeia inteira** até ele precisa ser `width: fill` (um
`fill` dentro de um pai `shrink` colapsa o campo — ver PRIMITIVAS.md). Na
prática: `.form`, cada `.campo`/`.row` intermediário e a classe do próprio
`<textinput>` todos com `width: fill`.

## A folha de estilo (`.gss`), por inteiro

O `.gss` é CSS **de propósito reduzido**: não há herança em cascata por
ancestral, nem seletor descendente, nem shorthand. Uma regra casa um nó e
aplica as propriedades que esse nó entende.

### Os três seletores

| forma | casa |
|---|---|
| `.cartao { }` | qualquer nó com `class="cartao"` (o atributo aceita várias, separadas por espaço) |
| `#salvar { }` | o nó com `id="salvar"` |
| `Button { }` | o **tipo** do nó: uma primitiva (`column`, `text`, `button`) ou o nome de um componente no uso (`Card`) |

Não existe `.a .b`, `.a > .b`, `.a.b` nem `*`. Uma lista separada por vírgula
vale (`.a, .b { }`) e é expandida em regras independentes.

**A ordem de especificidade**, do mais fraco ao mais forte:

```
tag  <  classe  <  id  <  atributo inline no .gv
```

Um `#salvar` fora de `@media` ainda vence uma `.botao` dentro de `@media` — o
tier mais alto ganha, a `@media` só desempata dentro do mesmo tier. E o atributo
escrito no markup vence tudo, o que é a razão de a convenção deste projeto
tirar estilo do `.gv`: um `size="12"` inline torna a classe inalcançável.

Regras de mesmo seletor **mesclam**, não se sobrescrevem: um segundo bloco
`.cartao { }` acrescenta o que declara e preserva o resto.

### Todas as propriedades

São 21, e **só estas**. Qualquer outra é ignorada com um aviso no terminal —
`border-bottom`, `margin`, `display: flex`, `box-shadow` não existem.

Numa forma de `<canvas>` (Onda 13), `fill` é apelido de `background`, `stroke`
de `border-color` e `stroke-width` de `border-width` — não são propriedades
novas, é o mesmo campo com o nome do domínio.

| propriedade | apelidos | valor |
|---|---|---|
| `width` | `w` | `fill`, `fill 2`, `shrink`, número |
| `height` | `h` | idem |
| `padding` | — | 1, 2 ou 4 números |
| `spacing` | — | número |
| `align_x` | `align-x` | `start`, `center`, `end` |
| `align_y` | `align-y` | idem |
| `background` | `bg` | `#rrggbb`, `#rrggbbaa` |
| `gradient` | — | `"180 #a #b"` — ângulo opcional + 2 ou mais cores |
| `border_radius` | `border-radius` | número |
| `border_width` | `border-width` | número |
| `border_color` | `border-color` | cor |
| `color` | — | cor do texto — **mas num `<button>` é a cor de FUNDO** |
| `text_color` | `text-color` | cor do rótulo de um `<button>` (default branco) |
| `size` | — | corpo da fonte |
| `bold` | — | `true`/`false` |
| `font` | `font-family` | nome da família carregada |
| `text_align` | `text-align` | `start`, `center`, `end` |
| `cursor` | `cursor-icon` | ver a tabela de `cursor` acima |
| `max_width` | `max-width` | número |
| `max_height` | `max-height` | número |
| `hidden` | — | `true`/`false`; `display: none` é apelido de `hidden: true` |

O motor aceita a forma com hífen como apelido de todas. A convenção deste
projeto escreve **sublinhado**, para casar com os atributos do `.gv`.

### Pseudo-estados

Cinco, e só em seletor de classe, id ou tag — nunca aninhados:

```gss
.botao          { background: #313244; }
.botao:hover    { background: #45475A; }
.botao:active   { background: #585B70; }   /* `:pressed` é apelido */
.botao:focus    { border_color: #89B4FA; }
.botao:disabled { color: #6C7086; }
.campo:invalid  { border_color: #F38BA8; } /* controle de <form> reprovado */
```

Um estado declara só o que **muda**; o resto vem da regra base.

`:hover`/`:focus`/`:active`/`:disabled` são estados nativos do widget. `:invalid`
é do motor: acende num `form_control` enquanto o `{erro_<campo>}` dele estiver
preenchido (ver "Validação declarada no próprio `<form>`"). Hoje pega em campos
de texto (`<input>`, `<maskedinput>`) e no campo de um `<spinbox>`; o
`<checkbox>` não tem gancho de estilo — ele se destaca só pelo `{erro_<campo>}`.

### Variáveis

`:root` é o único seletor que não casa nó nenhum: ele declara tokens.

```gss
:root {
  --fundo:  #1E1E2E;
  --texto:  #CDD6F4;
  --acento: #89B4FA;
  --fraco:  #7F849C;
}

.rotulo { color: var(--fraco); size: 12; }
.cta    { background: var(--acento); color: var(--fundo); }
```

`var(--nome, #fallback)` aceita um valor de reserva. Os tokens de **todas** as
folhas ativas são juntados antes da substituição, então uma paleta declarada uma
vez no `app.gss` global resolve `var()` dentro de um `<style scoped>` de
componente.

### `@media`

```gss
@media (max-width: 720) {
  .painel { width: fill; }
  .lateral { hidden: true; }
}

@media (min-width: 900) and (min-height: 600) { … }
```

As features são quatro: `min-width`, `max-width`, `min-height`, `max-height`,
medidas em pixels da **janela** (o sufixo `px` é tolerado e ignorado). Todas as
condições de uma consulta são combinadas com E — o `and` é opcional na escrita, e
não existe `or`, `not` nem `only screen`. Uma feature fora dessas quatro é erro
de parse, com o nome dela na mensagem.

**Dentro de `@media` só a forma com hífen é aceita** — `max_width` ali é erro de
parse, porque o nome é uma feature de CSS, não uma propriedade do motor. É a
única exceção à regra do sublinhado neste projeto.

### O que o `.gss` **não** faz

- **Não pinta a janela.** O fundo da janela vem do `theme.json`; um
  `background` numa `<column>` raiz `fill` desenha um retângulo do tamanho da
  janela a cada quadro, por cima do que o tema já pintou.
- **Não herda.** Um `color` numa `<column>` não desce para os `<text>` dentro
  dela; a classe vai no `<text>`.
- **Não tem margem.** O espaço entre irmãos é o `spacing` do pai; a margem
  interna é o `padding` do próprio nó.
- **Não tem sombra nem borda por lado.** A borda do motor é dos quatro lados.

## O `theme.json`

Uma paleta, carregada com `<link rel="theme" href="theme.json" />`. É o que
pinta a janela e o que dá cor aos widgets que não recebem `color`.

```json
{
  "name": "Meu app",
  "background": "#0F1117",
  "text": "#E6EDF3",
  "primary": "#58A6FF",
  "success": "#3FB950",
  "warning": "#D29922",
  "danger": "#F85149"
}
```

| campo | obrigatório |
|---|---|
| `background`, `text`, `primary`, `success`, `danger` | **sim** — faltar um é erro na carga, com o nome do campo na mensagem |
| `warning` | não; default `#D29922` |
| `name` | não; default `"custom"` — só rotula o tema |

Todas as cores em `#rrggbb` ou `#rrggbbaa`. Um valor que não é hexadecimal
válido também é erro na carga, não um silêncio.

O `theme.json` entra no hot-reload: salvar o arquivo repinta o app aberto.

## As convenções que atravessam o catálogo inteiro

**1. `value`/`items` são NOME DE CHAVE, não interpolação.** `value="volume"`,
sem chaves. É o que faz duas instâncias do mesmo widget não colidirem sem estado
por instância. `value="{volume}"` manda o widget procurar uma chave chamada
"42" — e não dá erro.

**2. O par `value` + `active`/`open`/`selected`.** Um é a chave que a ação
escreve, o outro é o valor que o markup lê para destacar. Ver acima.

**3. `on_change` vazio = o widget grava sozinho.** O motor cai em
`ctx[ação] = valor` quando não existe função global com aquele nome. Preencha só
para interceptar.

**4. `{prop|default}` dentro de um componente** usa o default quando a prop não
veio. É como um builtin se configura sem semear nada no contexto global — e é a
forma que você usa nos seus próprios componentes.

**5. Conjunto nomeado = uma chave com itens separados por vírgula.** Seleção
múltipla, `<Accordion>`, nós abertos de uma árvore, `<rubberband>`: todos usam a
mesma ideia, e o teste no markup é `contains`. A escrita normaliza para vírgula;
a leitura aceita vírgula, ponto e vírgula e espaço.

**6. Todo builtin expõe ganchos de classe.** `*_class` em qualquer prop
(`item_class`, `head_class`, `panel_class`) acrescenta classes ao nó interno
correspondente, sem você precisar reescrever o template. É como se estiliza um
builtin sem forkar.

**7. Dado ausente não é erro.** Chave que não existe, JSON inválido, lista
vazia: o widget desenha vazio. Isso é deliberado — uma tela que ainda não
carregou é uma moldura, não um pânico — e é por isso que semear as chaves no
`init` importa.

## Armadilhas que já custaram tempo

Todas silenciosas — nenhuma dá erro:

- **`fill` dentro de `shrink` colapsa.** Um filho `width="fill"` só mede o
  espaço real se **todo** ancestral até um limite determinado também for `fill`.
  Uma `<column>` sem `width` é `shrink`, e mede pelo irmão mais largo.
- **`fill` dentro de `<scrollable>` some.** O scrollable oferece altura
  infinita; um `height="fill"` ali mede infinito e empurra o resto para fora.
  Dentro de um scrollable, altura **declarada**.
- **`fill` numa prop de builtin não é largura de caixa.** No `<SpinBox>` o
  `width` desce para o campo, dentro de uma `<row>` `shrink` — `fill` ali vira
  um risco entre os dois botões.
- **`padding` com três números vira zero.** O motor aceita 1, 2 ou 4; três é
  descartado em silêncio.
- **`align_x="left"` não existe.** Os valores são `start`, `center`, `end`;
  qualquer outra coisa cai no default sem aviso.
- **Uma propriedade de `.gss` que o motor não conhece é ignorada.**
  `border-bottom`, `margin`, `box-shadow` somem no meio de um arquivo grande. O
  aviso vai para o terminal.
- **Um atributo de estilo inline vence a classe.** Um `size="12"` esquecido no
  `.gv` torna `.rotulo { size: 14 }` inalcançável — e a busca começa no `.gss`,
  que é o lugar errado.
- **Desligar uma chave é gravar vazio nela.** Por isso um `<template if>` de
  visibilidade não leva comparador: sem ele a condição é **truthy**. Com
  `not_equals="false"`, o vazio passa — e o painel abre e nunca fecha. Foi
  exatamente esse o bug que deixou o `<SplashScreen>` visível para sempre.
- **`empty`/`not_empty` testam array JSON, não texto.** Num valor que não
  parseia como array, `empty` é sempre verdadeiro.
- **`<pageindicator>` é uma tag, não um `dots="true"`.**
- **Conteúdo que passa da janela some sem barra.** Se a tela pode crescer, ela
  precisa de `<scrollable>` — e a coluna dentro dele **não** pode ter
  `height="fill"`.
- **`<link rel="theme">` e `.gss` são hot-reload; `.luau` não é.** Mudança de
  comportamento pede reiniciar o app.

Antes de dizer que um widget está quebrado, olhe a **árvore avaliada**: o ramo
existe? O `value` é o nome da chave ou o valor já interpolado? A largura é um
número, ou um `fill` dentro de um `shrink`?

## Como escrever os scripts

O motor não importa o seu script nem instancia nada dele: ele carrega o arquivo
e depois **procura funções globais pelo nome**. Isso decide quase tudo sobre
como um script é escrito.

### A forma de um handler

```lua
--!strict
--!nolint FunctionUnused   -- sem isto, o lsp acusa todo handler como código morto

-- HANDLER: global, porque é o motor que chama, pelo nome da ação.
function salvar(): ()
    ctx.status = "salvo"
end

-- AUXILIAR: local, porque só este arquivo usa.
local function normalizar(t: string): string
    local sem_espaco = string.gsub(t, "^%s+", "")   -- gsub devolve DOIS valores
    return string.lower(sem_espaco)
end
```

**O erro mais comum, e ele é silencioso:** escrever `local function salvar()`.
O motor não acha a função, cai no passo 5 do ciclo de ações e grava
`ctx.salvar = …` (ou nada, se a ação não trouxer valor). O botão não faz nada,
e não há erro nenhum. Handler é `function nome()`; auxiliar é
`local function nome()`.

O `--!nolint FunctionUnused` existe porque o luau-lsp não enxerga a chamada
vinda do motor e reportaria todos os handlers como não usados — é o único aviso
falso que um projeto novo produz.

### `init` roda no registro, não ao aparecer a tela

```lua
function init(): ()
    ctx.view = "home"
    publicar()
end
```

`init` é a única função com nome reservado, e ela roda quando o componente é
**registrado** — ou seja, na subida do app, no `main()`. Duas consequências:

- Se o `main()` registra três telas, os três `init` rodam no start, mesmo o das
  telas que ninguém abriu ainda.
- Navegar para uma tela **não** roda o `init` dela de novo. Se algo precisa
  acontecer toda vez que a tela aparece, dispare de uma ação (o clique que
  navegou), não do `init`.

Semear no `init` toda chave que o markup lê é o hábito que evita telas com
buracos: um `{total}` que ninguém escreveu renderiza vazio, sem aviso.

### Ler e escrever o contexto

```lua
-- LER: sempre texto, e `nil` se a chave nunca foi escrita.
local busca = ctx.busca or ""                 -- o `or ""` não é paranoia
local n     = tonumber(ctx.total) or 0        -- compare com número, não com "3"

-- ESCREVER: texto, número ou tabela (o motor serializa).
ctx.total  = 12                                -- vira "12"
ctx.itens  = json.encode(json.array(linhas))   -- a forma que os widgets leem
ctx.status = nil                               -- REMOVE a chave
```

Três coisas que mordem:

1. **Chave nunca escrita é `nil`, não `""`.** `string.lower(ctx.busca)` estoura
   se ninguém escreveu `busca`. Use `ctx.busca or ""`, ou semeie no `init`.
2. **Gravar `nil` apaga a chave** — e é assim que se desliga uma flag. Combina
   com o teste truthy do markup: chave ausente, `""`, `"false"` e `"0"` são
   falsos para um `if=` sem comparador.
3. **`json.array(t)` antes de encodar lista.** Sem ele, uma lista vazia vira
   `{}` (objeto) em vez de `[]`, e o widget de coleção não acha itens.

### Os dois ganchos opcionais

Além do `init` e dos seus handlers, o motor procura mais dois nomes — os dois
opcionais:

```lua
-- Chamado quando QUALQUER script deste componente estoura.
function on_error(msg: string): ()
    ctx.status = "erro interno"
end

-- Chamado quando outra janela fez `broadcast("evento", carga)`.
function on_broadcast(evento: string, carga: string): ()
    if evento == "config_mudou" then recarregar() end
end
```

### Quando um script quebra

O app **não** morre. O motor sempre escreve o erro no terminal (com o nome do
componente e da função) e, além disso:

- se você definiu `on_error`, chama ele;
- senão, mostra um **toast de erro** na tela.

Isso é a rede de segurança, não o método de trabalho: rode `make luau` (o
type-check do luau-lsp) antes de considerar um script pronto. Para inspecionar
algo no meio da execução, `print(...)` vai para o terminal como em Lua comum.

### O que suspende, e o que isso significa

`fetch`, `confirm`, `prompt`, `pick_color`, `open_file` e afins **suspendem**: o
motor pausa a corrotina do script e a retoma quando a resposta chega. O código
parece síncrono e a janela continua respondendo:

```lua
function buscar(): ()
    ctx.status = "buscando…"        -- pinta ANTES de suspender: a tela atualiza
    local res = fetch(url)          -- a janela continua viva aqui
    ctx.status = if res.ok then "" else `falhou: {res.error}`
end
```

Duas regras práticas:

- **Escreva o estado "carregando" antes da chamada** e o resultado depois. Entre
  as duas, o usuário vê a tela normalmente e pode clicar em outras coisas.
- **Proteja contra a segunda chamada**, porque ela pode acontecer: um clique
  duplo no botão dispara dois `fetch`. Uma flag no módulo resolve —
  `if State.carregando then return end`.

Já `progress{}` **não** suspende: ele acompanha um trabalho que continua. Você
abre, vai chamando `progress_set(n)` e fecha com `progress_close()`.

### Módulos, e onde o estado tipado mora

`require` usa caminho relativo ao arquivo, sem extensão:

```lua
local State = require("../state")        -- views/scripts/state.luau
local Dados = require("handlers/dados")  -- views/scripts/handlers/dados.luau
```

Um módulo devolve uma tabela (`return Dados`), e é onde ficam o estado tipado e
as funções que você chama de outros arquivos. Os **handlers continuam globais**,
mesmo dentro de um módulo — a tabela é para o seu código, os globais são para o
motor:

```lua
local Dados = {}

function Dados.publicar(): ()  …  end   -- chamada por outros arquivos
function alternar_item(id: string): () … end  -- chamada pelo MOTOR (on_click)

return Dados
```

### Hot-reload não cobre `.luau`

Salvar um `.gv`, um `.gss`, o `theme.json` ou um `<link rel="data">` aplica com
o app aberto. **Mudança em script pede reiniciar** — o motor troca a árvore do
template no lugar, mas não recria a VM do Luau nem roda o `init` de novo.

Se uma alteração de comportamento "não fez efeito", esta é a primeira coisa a
conferir.

## Todas as funções da camada Luau

Tudo abaixo é **global** — não há `import`. Os tipos vivem em
`views/scripts/glacier.d.luau` (só o luau-lsp lê; o motor ignora anotações).

A distinção que organiza a lista: **suspende** quer dizer que o motor pausa a
corrotina e a retoma com a resposta — o código fica síncrono e a janela continua
viva. As demais cedem um pedido e retomam na hora.

| suspendem | não suspendem |
|---|---|
| `fetch`, `confirm`, `prompt`, `pick_color`, `open_file`, `open_files`, `save_file`, `pick_folder` | todo o resto |

### Rede

#### `fetch(url, opts?) -> { ok, status, body, error }` — **suspende**

```lua
local res = fetch("https://api.exemplo/itens")
if not res.ok then
    toast({ message = `falhou: {res.error}`, kind = "error" })
    return
end
local dados = json.decode(res.body)
```

```lua
-- POST com corpo e cabeçalhos
local res = fetch(url, {
    method = "POST",                                  -- default "GET"
    headers = { ["Content-Type"] = "application/json",
                Authorization = `Bearer {token}` },
    body = json.encode({ nome = "api" }),
    user_agent = "meu-app/1.0",                       -- atalho para o header
})
```

| campo de `opts` | o que é |
|---|---|
| `method` | `"GET"` (default), `"POST"`, … |
| `headers` | tabela `{ [nome] = valor }` |
| `body` | corpo textual |
| `body_base64` | corpo **binário** em base64; vence o `body` |
| `user_agent` | atalho para o header (um `headers` explícito ganha) |
| `timeout` | teto em **milissegundos** para a requisição inteira; estourado, `ok=false`, `status=0`, `error="timeout após …"` |
| `response = "base64"` | só para `file://`: devolve bytes em base64 em vez de texto |

`res.ok` é o que se testa — `status` é o código HTTP e `error` traz a mensagem
quando a requisição nem chegou a responder. **`url` aceita `file://`**, que é
como se lê um arquivo local (a escrita é `write_file`).

#### `http(base_url?, opts?) -> client` — um cliente reutilizável sobre o `fetch`

Quando um script fala com a **mesma API em vários lugares**, criar um `http`
uma vez tira a repetição de base_url, cabeçalhos, timeout e tratamento de erro
de cada chamada. É "orientado a objeto": um construtor, setters encadeáveis,
interceptors e derivação. Todo método de chamada (`:get`, `:post`, …)
**suspende**, como o `fetch` cru.

```lua
-- Um cliente para a API inteira (num módulo, para reusar entre handlers).
local api = http("https://api.exemplo.com/v1", {
    headers = { Accept = "application/json" },
    timeout = 8000,        -- ms, por requisição
    retries = 2,           -- tentativas EXTRAS em falha de rede / 429 / 5xx
})

api:set_header("Authorization", `Bearer {token}`)   -- encadeável (devolve o cliente)
   :on_request(function(req)                         -- roda antes de cada fetch
       req.headers["X-Trace-Id"] = trace_id()
       return req                                    -- devolva a tabela (mutada ou nova)
   end)
   :on_response(function(res) return res end)        -- roda depois, com res.json pronto
   :on_error(function(err)                           -- resultado final não-ok, após os retries
       toast({ message = err.error, kind = "error" })
   end)

local r = api:get("/itens", { query = { page = 1 } })   -- ?page=1, já url-encoded
local r = api:post("/itens", { nome = "x" })            -- body tabela → JSON + Content-Type
if r.ok then usar(r.json) end                           -- r.json = corpo já decodificado
```

**O construtor e o `opts`:**

| campo | o que é |
|---|---|
| `base_url` (1º arg) | prefixo de todo `path`. Um `path` que já é `http(s)://…` **ignora** a base |
| `headers` | cabeçalhos de base; um `headers` na chamada tem prioridade, chave a chave |
| `query` | query params de base; idem, mesclados com os da chamada |
| `timeout` | ms, por requisição — desce para o `fetch` |
| `retries` | tentativas **extras** (0 = uma tentativa). Reenvia enquanto `status == 0`, `429` ou `>= 500` |
| `retry_on` | `function(res) -> boolean` — sobrescreve o critério de retry |

**Setters (encadeáveis, cada um devolve o cliente):** `set_base_url`,
`set_header(k, v)`, `set_headers(t)`, `remove_header(k)`, `set_query(k, v)`,
`set_timeout(ms)`, `set_retries(n)`, `set_retry_on(fn)`.

**Interceptors** (rodam na ordem de registro):

- `on_request(fn)` — `fn(req)` recebe `{ method, path, headers, query, body, timeout }`; muta e/ou devolve a tabela.
- `on_response(fn)` — `fn(res)` recebe a resposta já enriquecida (com `res.json`); pode devolver outra.
- `on_error(fn)` — `fn(err)` com `{ status, error, url, method, attempt, body }`, quando o resultado final (depois dos retries) tem `ok == false`.

**Chamadas** — todas suspendem e devolvem a resposta:

| método | |
|---|---|
| `client:get(path, spec?)` / `:delete` / `:head` | |
| `client:post(path, body?, spec?)` / `:put` / `:patch` | `body` tabela → `json.encode` + `Content-Type: application/json` |
| `client:request(spec)` | a forma geral: `{ method, path, url?, headers?, query?, body?, timeout? }` |

**A resposta** é a do `fetch` (`{ ok, status, body, error }`) mais:

- `res.json` — o corpo decodificado, ou `nil` se não era JSON;
- `res.request` — `{ method, url }` da chamada que a produziu.

**Clientes derivados:** `api:extend("/admin", { headers = { ["X-Role"] = "root" } })`
devolve um cliente novo com a `base_url` estendida, os headers/query/timeout/
retries mesclados e **os interceptors do pai copiados** (o filho acrescenta sem
afetar o pai).

**O que ele não faz:** cabeçalhos da resposta (o `fetch` não os devolve),
cancelamento e backoff **entre** retries (os reenvios são imediatos — para
espaçar, componha com `after`).

#### `sse(url, opts?) -> handle` e `websocket(url, opts?) -> handle`

Não suspendem: abrem o stream e devolvem o handle na hora. Os eventos chegam
pelos callbacks.

```lua
local stream = sse("https://api.exemplo/eventos", {
    headers    = { Authorization = `Bearer {token}` },
    on_open    = function() ctx.status = "conectado" end,
    on_message = function(data)
        local ev = json.decode(data)
        ctx.ultimo = ev.texto
    end,
    on_error   = function(msg) ctx.status = `erro: {msg}` end,
    on_close   = function() ctx.status = "desconectado" end,
})

stream:close()
```

`websocket` tem a mesma forma, mais `stream:send("texto")` para escrever na
conexão viva. Guarde o handle (num módulo) se precisar fechar depois.

### Diálogos

#### `confirm(opts) -> boolean` — **suspende**

```lua
if confirm({ title = "Remover?", message = "Não dá para desfazer.",
             confirm_label = "Remover", destructive = true }) then
    remover()
end
```
`destructive = true` pinta o botão como perigoso. Dispensar (Esc, clique fora)
devolve `false`.

#### `prompt(opts) -> string?` — **suspende**

```lua
local nome = prompt({ title = "Renomear", label = "Novo nome", value = atual })
if nome then ctx.servico = nome end        -- nil = desistiu
```

`kind` escolhe o campo — as quatro variantes do `QInputDialog`:

| `kind` | campo | opções que valem |
|---|---|---|
| `"text"` (default) | texto | `placeholder` |
| `"int"` | spinbox inteiro | `min`, `max`, `step` |
| `"double"` | spinbox decimal | `min`, `max`, `step`, `decimals` |
| `"item"` | lista suspensa | `items` |

Mais `title`, `message`, `label`, `value`, `confirm_label`, `cancel_label`.
**O retorno é sempre string**, inclusive nos numéricos — `tonumber()` é de quem
sabe o que o valor significa. E `nil` (desistiu) é diferente de `""`
(respondeu vazio).

#### `pick_color(opts?) -> string?` — **suspende**

```lua
local cor = pick_color({ title = "Cor do tema", value = ctx.cor })
if cor then ctx.cor = cor end              -- "#rrggbb"
```

#### `pick_font(opts?) -> string?` — **suspende**

O `QFontDialog`. Devolve a **família** escolhida (ou `nil` se cancelou). O
campo de tamanho e a amostra são pré-visualização — o retorno é só o nome.

```lua
local f = pick_font({ title = "Fonte do editor", value = ctx.fonte, size = 15 })
if f then ctx.fonte = f end
```

#### `open_file / open_files / save_file / pick_folder(opts?)` — **suspendem**

```lua
local caminho = open_file({
    title = "Escolha a imagem",
    filters = { { name = "Imagens", extensions = { "png", "jpg" } } },
    starting_dir = "/home/ana",
})
if not caminho then return end             -- nil = cancelou
```

`open_files` devolve uma **tabela** de caminhos; `save_file` aceita
`default_name`; `pick_folder` escolhe um diretório. São os diálogos **nativos do
SO**, não desenhados pelo motor.

#### `progress(opts)`, `progress_set(valor?, label?)`, `progress_close()`

**Não suspendem** — de propósito: eles acompanham um trabalho que continua.

```lua
progress({ title = "Baixando", label = "conectando…", max = #pacotes,
           on_cancel = "cancelar_download" })
for i, p in pacotes do
    if ctx.cancelado == "true" then break end
    progress_set(i, `baixando {p.nome}`)
    baixar(p)
end
progress_close()
```

Sem `value` na abertura, a barra nasce **indeterminada** (um spinner) — e
`progress_set(nil)` volta a esse estado. Sem `on_cancel`, o diálogo não tem
botão: é a etapa que não dá para interromper, e um "Cancelar" que não cancela
seria pior que botão nenhum.

### Avisos

#### `toast(opts | "mensagem")`

Efêmero, desenhado **dentro** da janela.

```lua
toast("Salvo")                                          -- kind "info"
toast({ message = "Falhou", kind = "error", title = "Rede" })
```
`kind`: `info` (default), `success`, `warning`, `error`.

#### `notify(opts | "mensagem")`

Notificação **do sistema operacional** — aparece mesmo com o app minimizado.

```lua
notify({ title = "Backup", body = "Terminou", icon = "drive-harddisk" })
```
Mais `app_name`, útil quando o desktop filtra por identidade do app.

#### `console.*` — log para o TERMINAL

`toast`/`notify` são para o **usuário**; `console.*` é para **você**, no
`stdout` do processo (o mesmo lugar do `print`), com cor ANSI, glifo, rótulo e
hora. Os erros de runtime do motor já saem sozinhos no `stderr` — o `console`
não os substitui, é o seu log.

```lua
console.log("carregou", n_itens, { origem = "cache" })   -- vários args; tabela é inspecionada
console.info("igual ao log")
console.warn("cache velho, revalidando")
console.error("deu ruim:", res.error)
console.debug("passo interno")                            -- escondido no nível default
console.table(res.json)                                   -- lista de objetos → grade
```

| método | nível | cor |
|---|---|---|
| `console.debug(...)` | `debug` (0) | cinza |
| `console.log` / `console.info(...)` | `info` (1) | ciano |
| `console.warn(...)` | `warn` (2) | amarelo |
| `console.error(...)` | `error` (3) | vermelho |
| `console.table(rows, columns?)` | `info` | grade `┌─┬─┐`, cabeçalho em negrito |

**Filtro de nível** — só o que for `>=` ao nível configurado imprime:

```lua
console.set_level("warn")        -- daqui pra frente, só warn e error
console.set_level("silent")      -- cala tudo, inclusive error
```

**`console.config(opts)`** — mexe só no que vier, e devolve o próprio `console`:

| opção | default | o que faz |
|---|---|---|
| `level` | `"info"` | `"debug"`/`"info"`(`"log"`)/`"warn"`/`"error"`/`"silent"`, ou `0`–`4` |
| `color` | `true` | `false` tira os códigos ANSI (para um log que vai a arquivo) |
| `timestamp` | `true` | o `HH:MM:SS` no começo da linha |
| `label` | `true` | o glifo + `INFO`/`WARN`/… |
| `prefix` | `""` | texto (em magenta) antes de tudo — bom para marcar o módulo/serviço |

```lua
console.config({ prefix = "[api]", timestamp = false })
```

**`console.table`**: `rows` é uma lista de tabelas (uma linha cada) ou de
escalares (viram a coluna `valor`). `columns` opcional escolhe e ordena as
chaves; sem ele, a união das chaves na ordem em que aparecem. A primeira coluna
é sempre `(índice)` — a chave/posição da linha.

### Navegação e janelas

```lua
navigate("sobre")        -- troca a tela desta janela
navigate_back()          -- volta uma no histórico

open_window("views/detalhe.gv")
open_window({ file = "views/detalhe.gv", title = "Detalhe", width = 400, height = 300 })
open_window({ component = "perfil", title = "Perfil" })   -- já registrado

broadcast("item_criado", { id = "42", nome = "api" })     -- para as OUTRAS janelas
close_window()                                            -- fecha a própria
```

`broadcast` **não** volta para quem enviou; ele cai no `on_broadcast(evento,
carga)` de cada outra janela. Uma tabela vira JSON na ida e chega decodificada
do outro lado. O par `broadcast` + `close_window` é como uma janela auxiliar
(um formulário) avisa e se dispensa.

### Tempo

```lua
local t = after(2000, function() ctx.dica = "" end)   -- uma vez
t:cancel()                                            -- se ainda não venceu

local p = every(5000, atualizar)                      -- repetido (nome de função também vale)
p:cancel()                                            -- interrompe as próximas
```

`every` é construído sobre `after`: cada disparo reagenda o seguinte. O
`:cancel()` impede as próximas repetições — o disparo já em curso termina.

### Arquivos e persistência

```lua
local ok, erro = write_file("saida/relatorio.txt", texto)   -- sobrescreve
local ok, erro = append_file("saida/log.txt", linha .. "\n") -- acrescenta
zip_dir("pasta/origem", "saida/pacote.zip")                  -- compacta a árvore

storage.set("ultimo_projeto", { id = "42", nome = "api" })   -- persiste entre execuções
local ultimo = storage.get("ultimo_projeto")                 -- volta decodificado
storage.remove("ultimo_projeto")
```

Nenhum deles suspende — é I/O local. `write_file`/`append_file` devolvem
`(true)` ou `(false, mensagem)`; para **ler** um arquivo, use
`fetch("file://caminho")`.

`storage` é um JSON chaveado que o motor gerencia (a pasta sai do
`.storage_dir(...)` no `main.rs`); ao contrário do `ctx`, ele sobrevive ao
fechar do app e aceita tabelas de volta como tabelas.

### JSON

```lua
local t = json.decode(res.body)            -- string -> tabela
local s = json.encode(t)                   -- tabela -> string
ctx.itens = json.encode(json.array(lista)) -- marca como ARRAY
```

`json.array(t)` resolve a ambiguidade da tabela vazia: sem ele,
`json.encode({})` produz `{}` (objeto) e o widget de coleção não acha itens.
Tabelas vindas de `json.decode` já vêm marcadas.

### Data e hora

Aritmética sobre strings ISO — o formato que `<dateedit>`/`<timeedit>`/
`<datetimeedit>` gravam. Tudo devolve `nil` se a entrada não for ISO válida,
inclusive uma data que não existe (31/02).

```lua
date.today()            -- "2026-09-09"
date.now(true)          -- "2026-09-09 14:35:02"  (com segundos)
date.time()             -- "14:35"

date.parse(iso)         -- { year, month, day, hour, min, sec }
date.valid(iso)         -- boolean
date.weekday(iso)       -- 1 = domingo
date.date_of(iso)       -- só a parte da data
date.time_of(iso)       -- só a parte da hora
date.days_in_month(2026, 2)

date.compare(a, b)      -- -1/0/1 pelo INSTANTE, não pelo texto
date.is_before(a, b)    date.is_after(a, b)

date.add(iso, { months = 1, days = -3 })  -- devolve na MESMA forma da entrada
date.diff(a, b)                            -- em dias de calendário
date.diff_seconds(a, b)

date.format(iso, "DD/MM/YYYY HH:mm")       -- tokens YYYY YY MM DD HH mm SS
date.epoch(iso)         date.from_epoch(s, utc?)
date.to_local(iso)      date.to_utc(iso)
```

Duas coisas que economizam depuração: `add` anda pelo **calendário** (31/01 + 1
mês = 28/02, não 03/03), e `compare` funciona entre formas diferentes
(`"2026-09-10 08:00"` vs. `"2026-09-10"`) porque compara o instante.

### O resto

```lua
viewport()                              -- { width, height } da janela agora
append_textarea("meus_logs", linha)     -- acrescenta ao <textarea> ligado à chave
print("depurando", valor)               -- vai para o terminal
```

`append_textarea` é **incremental**: o motor insere no fim do buffer em vez de
recriá-lo, então o scroll é preservado e o custo é do texto novo, não do
conteúdo todo. É o que torna um log vivo viável — reescrever `ctx.meus_logs`
inteiro a cada linha faria a área pular para o topo.

## O que o Rust te dá

Só é necessário quando o comportamento quer tipos de verdade, uma thread, ou
uma crate. Um app inteiro pode não ter Rust nenhum além do `main`.

```rust
use glacier_ui::{Component, Context, Template};

pub struct Contador { valor: i32 }

impl Component for Contador {
    fn name(&self) -> &str { "contador" }                       // o nome da tag/tela
    fn template(&self) -> Template { Template::File("views/contador.gv".into()) }

    fn init(&mut self, ctx: &mut Context) {                      // uma vez, ao montar
        ctx.set("contador", self.valor.to_string());
    }

    fn update(&mut self, acao: &str, valor: Option<&str>, ctx: &mut Context) {
        match acao {
            "somar"    => self.valor += 1,
            "subtrair" => self.valor -= 1,
            "passo" => {                                        // ação com valor
                let Some(t) = valor else { return };
                if let Ok(n) = t.trim().parse::<i32>() { self.valor = n; }
            }
            _ => return,
        }
        ctx.set("contador", self.valor.to_string());             // publique ao fim
    }
}
```

O `GlacierDaemon` é o que abre a janela:

```rust
GlacierDaemon::new()
    .title("Meu app")
    .main_size(980, 640)
    .main_window(window::Settings { decorations: false, ..Default::default() })  // titlebar própria
    .remember_window_geometry(true)      // lembra posição/tamanho entre execuções
    .storage_dir(dir)                    // onde `storage.*` grava
    .font_named("Inter", include_bytes!("Inter.ttf"))   // `font="Inter"` no .gv/.gss
    .main(|motor| {
        motor.register_component("app", "views/app.gv").ok();   // tela vinda de .gv
        motor.register(Box::new(Contador::new())).ok();          // tela vinda de Rust
        motor.set_initial_screen("app");
    })
    .run()
```

Rust e Luau convivem: um componente Rust cujo `.gv` tenha `<script>` roda o
Luau **primeiro** e cai no `update` do Rust só para as ações que o script não
define.

### Expor uma função ou objeto Rust ao `<script>`

O motor injeta um punhado de globais no Luau (`fetch`, `json`, `storage`, …). O
app acrescenta os seus com `GlacierDaemon::lua_extension` — um closure
`Fn(&mlua::Lua) -> mlua::Result<()>` que roda em **cada VM Luau nova** (uma por
componente com `<script>`, em qualquer janela), **depois** dos globais do motor e
**antes** do `<script>` do usuário. É a ponte para acoplar um banco de dados, um
cofre de segredos, um SDK — coisas que o motor não traz e não deveria. O `mlua`
sai reexportado como `glacier_ui::mlua`, então o app não fixa uma versão dele.

Uma **função** solta:

```rust
use glacier_ui::{mlua, GlacierDaemon};

GlacierDaemon::new()
    .lua_extension(|lua: &mlua::Lua| {
        let somar = lua.create_function(|_, (a, b): (i64, i64)| Ok(a + b))?;
        lua.globals().set("somar", somar)      // → `somar(2, 3)` no <script>
    })
    // …
```

Um **objeto** com métodos (o padrão de um client): uma `struct` que implementa
`mlua::UserData`, devolvida por uma função-fábrica registrada como global.

```rust
use std::cell::RefCell;
use glacier_ui::mlua::{self, UserData, UserDataMethods};

struct Kv(RefCell<std::collections::HashMap<String, String>>);

impl UserData for Kv {
    fn add_methods<M: UserDataMethods<Self>>(m: &mut M) {
        m.add_method("get", |_, this, k: String| {
            Ok(this.0.borrow().get(&k).cloned())          // Option<String> → string | nil
        });
        m.add_method("set", |_, this, (k, v): (String, String)| {
            this.0.borrow_mut().insert(k, v);
            Ok(())
        });
    }
}

// no builder:
.lua_extension(|lua: &mlua::Lua| {
    let abrir = lua.create_function(|lua, ()| {
        lua.create_userdata(Kv(RefCell::new(Default::default())))
    })?;
    let kv = lua.create_table()?;
    kv.set("abrir", abrir)?;
    lua.globals().set("kv", kv)                 // → `local d = kv.abrir(); d:set("a","1")`
})
```

`RefCell` (não `&mut self`) porque `add_method` entrega `&self`; o app é
single-thread (a thread da UI), então não há disputa. Um `Err` na extensão
aborta a construção do componente com a mesma cara de um `<script>` malformado —
melhor que um componente meio-instalado.

Também há a função livre `glacier_ui::register_lua_extension(ext)`, idêntica, para
quem não tem o builder à mão. Registrar duas vezes instala duas vezes.

O exemplo `sqlite_crud` do repositório do glacier-ui leva isso ao fim: um global
`sqlite` com `connect`/`execute`/`query`/`begin`/`commit`/`close`, e um CRUD
escrito só no `<script>`.

## Receitas

**Um formulário que valida antes de enviar** — as regras no `<form>`, o motor
valida ao enviar (ver "Validação declarada no próprio `<form>`"):

```xml
<form on_submit="salvar" on_validation_error="apontar">
  <input form_control="email" rules="required|email" msg="e-mail inválido" />
  <input form_control="senha" secure="true" rules="required|minlen:6" msg="mínimo 6" />
  <text class="erro" if="{erro_email}" not_empty>{erro_email}</text>
  <text class="erro" if="{erro_senha}" not_empty>{erro_senha}</text>
  <button type="submit" text="Entrar" />
</form>
```
`salvar` só roda se tudo passou; `apontar` recebe as falhas em JSON. O
`.campo:invalid` no `.gss` acende sozinho.

**Carregar dados ao abrir a tela** — chame do `init`; o `fetch` suspende sem
travar a janela.

**Uma lista mestre-detalhe** — a lista escreve o id numa chave, o detalhe lê:

```xml
<ListView items="servicos" value="sel" selected="{sel}" />
<column if="{sel}" class="detalhe"> … {sel_nome} … </column>
```
O script observa a ação de seleção e publica os campos do detalhe.

**Um item que abre um modal** — declare o `<dialog>` no `<resources>` e dispare
`dialog:nome`; ou use `confirm{}`/`prompt{}` no script, que suspendem.

**Trabalho longo com progresso** — `progress{}` no começo, `progress_set(n)` no
meio, `progress_close()` no fim. Ele não suspende: o trabalho continua.

**Polling** — `every(5000, atualizar)` no `init`, guardando o handle se precisar
cancelar depois.

## Antes de dizer que está pronto

- `make lint` passa (clippy + type-check dos `.luau`).
- O app **abre**: `make run`. Um `.gv` com erro de XML falha na carga com a linha
  e a coluna; um `UnknownComponent` é tag com a caixa errada.
- Toda chave que o markup lê é escrita em algum lugar — um `{total}` que ninguém
  publica renderiza **vazio**, sem aviso.
- Nenhum `width="fill"` dentro de um ancestral `shrink`, e nenhum
  `height="fill"` dentro de um `<scrollable>`.
- Toda tela que pode crescer tem `<scrollable>`.
- O estilo está no `.gss`, não inline (as três exceções estão na seção de
  convenções).

## Convenções deste projeto

- **Templates são `.gv`**; folhas de estilo, `.gss`. Não existe `.kdl`, `.iss`
  nem `.rss` — se vir menção a esses, é documentação velha.
- **Scripts são Luau**, em `views/scripts/`. Os tipos de tudo que o motor injeta
  estão em `views/scripts/glacier.d.luau`.
- **Um nome em `globals` no `.luaurc` perde o tipo.** O luau-lsp trata todo nome
  listado ali como `any`, o que **anula** a declaração correspondente do
  `glacier.d.luau`: com `fetch` na lista, `fetch(…).campo_que_nao_existe` deixa
  de ser erro. O `.luaurc` que vem no template lista os globais do motor para
  que nenhum apareça como "desconhecido"; o preço é que esses nomes não são
  checados. Se quiser o type-check de verdade num deles, tire o nome da lista —
  o `.d.luau` já o declara. E um global **novo** se declara no `.d.luau`, não
  aqui.
- **Um valor que o app nomeia não precisa de estado por instância.** A chave
  entra por prop e a ação carrega a chave — é como `SpinBox`, `TabBar` e
  `Pagination` funcionam sem colidir entre instâncias.
