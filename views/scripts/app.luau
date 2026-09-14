--!strict
--!nolint FunctionUnused
-- Handlers da tela única do app (ver AGENTS.md: "muitos apps de uma janela só
-- nem navegam"). Tudo abaixo segue uma ordem que IMPORTA em Luau: um `local
-- function` só enxerga outro `local` declarado ANTES dele no arquivo — não
-- pela ordem em que são CHAMADOS (isso só acontece bem depois, quando o motor
-- despacha uma ação), mas pela ordem em que aparecem no texto. Por isso os
-- auxiliares vêm primeiro, em ordem de dependência, e os handlers GLOBAIS
-- (que o motor chama pelo nome) vêm todos no fim.

local Api = require("api")
local State = require("state")
local Thumbs = require("thumbs")
local Format = require("format")

-- ===========================================================================
-- Auxiliares (locais, em ordem de dependência)
-- ===========================================================================

local function mensagem_de_erro(e: string): string
    if e == "sem_chave" then
        return "Configure uma chave de API em ⚙ Configurações."
    end
    return e
end

local function video_de_populares(item: any): State.Video
    local id = item.id
    local sn = item.snippet
    local stats = item.statistics or {}
    local cd = item.contentDetails or {}
    local thumb = sn.thumbnails and (sn.thumbnails.medium or sn.thumbnails.default)
    local partes = {}
    if stats.viewCount then
        table.insert(partes, `{Format.contagem(stats.viewCount)} visualizações`)
    end
    table.insert(partes, Format.ha_quanto_tempo(sn.publishedAt))
    local dur = Format.duracao(cd.duration)
    if dur ~= "" then
        table.insert(partes, dur)
    end
    return {
        id = id,
        titulo = sn.title,
        canal = sn.channelTitle,
        canal_id = sn.channelId,
        thumb = Thumbs.caminho(thumb and thumb.url, id),
        meta = table.concat(partes, " · "),
    }
end

local function video_de_busca(item: any): State.Video
    local id = item.id.videoId
    local sn = item.snippet
    local thumb = sn.thumbnails and (sn.thumbnails.medium or sn.thumbnails.default)
    return {
        id = id,
        titulo = sn.title,
        canal = sn.channelTitle,
        canal_id = sn.channelId,
        thumb = Thumbs.caminho(thumb and thumb.url, id),
        meta = Format.ha_quanto_tempo(sn.publishedAt),
    }
end

local function video_de_upload(item: any): State.Video
    local sn = item.snippet
    local id = sn.resourceId.videoId
    local thumb = sn.thumbnails and (sn.thumbnails.medium or sn.thumbnails.default)
    return {
        id = id,
        titulo = sn.title,
        canal = sn.channelTitle or "",
        canal_id = sn.channelId or "",
        thumb = Thumbs.caminho(thumb and thumb.url, id),
        meta = Format.ha_quanto_tempo(sn.publishedAt),
    }
end

local function publicar_home(): ()
    ctx.home_itens = json.encode(json.array(State.home.itens))
    ctx.home_carregando = if State.home.carregando then "1" else ""
    ctx.home_erro = mensagem_de_erro(State.home.erro)
    ctx.home_tem_mais = if State.home.pagina then "1" else ""
end

local function publicar_busca(): ()
    -- Termo de VERDADE buscado — distinto de `ctx.busca` (o texto ao vivo do
    -- campo, que o usuário pode seguir editando enquanto olha os resultados
    -- da busca anterior).
    ctx.busca_termo = State.busca_texto
    ctx.busca_itens = json.encode(json.array(State.busca.itens))
    ctx.busca_carregando = if State.busca.carregando then "1" else ""
    ctx.busca_erro = mensagem_de_erro(State.busca.erro)
    ctx.busca_tem_mais = if State.busca.pagina then "1" else ""
end

local function publicar_video(): ()
    ctx.video_carregando = if State.video_carregando then "1" else ""
    ctx.video_erro = mensagem_de_erro(State.video_erro)
    local v = State.video
    ctx.video_titulo = if v then v.titulo else ""
    ctx.video_canal = if v then v.canal else ""
    ctx.video_canal_id = if v then v.canal_id else ""
    ctx.video_thumb = if v then (v.thumb or "") else ""
    ctx.video_meta = if v then v.meta else ""
    ctx.video_descricao = if v then v.descricao else ""
end

local function publicar_comentarios(): ()
    ctx.comentarios_itens = json.encode(json.array(State.comentarios.itens))
    ctx.comentarios_carregando = if State.comentarios.carregando then "1" else ""
    ctx.comentarios_tem_mais = if State.comentarios.pagina then "1" else ""
end

local function publicar_canal(): ()
    ctx.canal_carregando = if State.canal_carregando then "1" else ""
    ctx.canal_erro = mensagem_de_erro(State.canal_erro)
    local c = State.canal
    ctx.canal_titulo = if c then c.titulo else ""
    ctx.canal_avatar = if c then (c.avatar or "") else ""
    ctx.canal_inscritos = if c then c.inscritos else ""
    ctx.canal_descricao = if c then c.descricao else ""
    ctx.canal_videos_itens = json.encode(json.array(State.canal_videos.itens))
    ctx.canal_tem_mais = if State.canal_videos.pagina then "1" else ""
end

-- Troca de tela com histórico — o par de `voltar` (handler global, lá embaixo).
local function ir_para(novo: string): ()
    table.insert(State.historico, ctx.view or "home")
    ctx.view = novo
end

local function carregar_populares(pagina: string?): ()
    if State.home.carregando then
        return
    end
    State.home.carregando = true
    State.home.erro = ""
    publicar_home()
    local r = Api.populares(pagina)
    State.home.carregando = false
    if not r.ok then
        State.home.erro = r.error
        publicar_home()
        return
    end
    local novos = {}
    for _, item in r.items do
        table.insert(novos, video_de_populares(item))
    end
    if pagina then
        for _, v in novos do
            table.insert(State.home.itens, v)
        end
    else
        State.home.itens = novos
    end
    State.home.pagina = r.next_page_token
    publicar_home()
end

local function carregar_busca(pagina: string?): ()
    if State.busca.carregando then
        return
    end
    State.busca.carregando = true
    State.busca.erro = ""
    publicar_busca()
    local r = Api.buscar(State.busca_texto, pagina)
    State.busca.carregando = false
    if not r.ok then
        State.busca.erro = r.error
        publicar_busca()
        return
    end
    local novos = {}
    for _, item in r.items do
        table.insert(novos, video_de_busca(item))
    end
    if pagina then
        for _, v in novos do
            table.insert(State.busca.itens, v)
        end
    else
        State.busca.itens = novos
    end
    State.busca.pagina = r.next_page_token
    publicar_busca()
end

local function carregar_comentarios(video_id: string, pagina: string?): ()
    if State.comentarios.carregando then
        return
    end
    State.comentarios.carregando = true
    publicar_comentarios()
    local r = Api.comentarios(video_id, pagina)
    State.comentarios.carregando = false
    if not r.ok then
        publicar_comentarios()
        return
    end
    local novos = {}
    for _, item in r.items do
        local sn = item.snippet.topLevelComment.snippet
        table.insert(novos, {
            autor = sn.authorDisplayName,
            avatar = Thumbs.caminho(
                sn.authorProfileImageUrl,
                `autor_{string.gsub(sn.authorDisplayName, "%W", "")}`
            ),
            texto = sn.textDisplay,
            curtidas = Format.contagem(sn.likeCount or 0),
            quando = Format.ha_quanto_tempo(sn.publishedAt),
        })
    end
    if pagina then
        for _, c in novos do
            table.insert(State.comentarios.itens, c)
        end
    else
        State.comentarios.itens = novos
    end
    State.comentarios.pagina = r.next_page_token
    publicar_comentarios()
end

local function carregar_video(id: string): ()
    State.video_id = id
    State.video = nil
    State.video_carregando = true
    State.video_erro = ""
    State.comentarios = { itens = {}, pagina = nil, carregando = false }
    publicar_video()
    publicar_comentarios()
    local r = Api.video(id)
    State.video_carregando = false
    if not r.ok then
        State.video_erro = r.error
        publicar_video()
        return
    end
    local item = r.items[1]
    local sn = item.snippet
    local stats = item.statistics or {}
    local cd = item.contentDetails or {}
    local thumb = sn.thumbnails and (sn.thumbnails.high or sn.thumbnails.medium or sn.thumbnails.default)
    local partes = {}
    if stats.viewCount then
        table.insert(partes, `{Format.contagem(stats.viewCount)} visualizações`)
    end
    table.insert(partes, Format.ha_quanto_tempo(sn.publishedAt))
    local dur = Format.duracao(cd.duration)
    if dur ~= "" then
        table.insert(partes, dur)
    end
    State.video = {
        titulo = sn.title,
        canal = sn.channelTitle,
        canal_id = sn.channelId,
        thumb = Thumbs.caminho(thumb and thumb.url, `{id}_grande`),
        meta = table.concat(partes, " · "),
        descricao = sn.description or "",
    }
    publicar_video()
    carregar_comentarios(id, nil)
end

local function carregar_uploads(pagina: string?): ()
    if not (State.canal and State.canal.uploads_playlist) then
        return
    end
    if State.canal_videos.carregando then
        return
    end
    State.canal_videos.carregando = true
    publicar_canal()
    local r = Api.uploads_do_canal(State.canal.uploads_playlist :: string, pagina)
    State.canal_videos.carregando = false
    if not r.ok then
        State.canal_videos.erro = r.error
        publicar_canal()
        return
    end
    local novos = {}
    for _, item in r.items do
        table.insert(novos, video_de_upload(item))
    end
    if pagina then
        for _, v in novos do
            table.insert(State.canal_videos.itens, v)
        end
    else
        State.canal_videos.itens = novos
    end
    State.canal_videos.pagina = r.next_page_token
    publicar_canal()
end

local function carregar_canal(id: string): ()
    State.canal_id = id
    State.canal = nil
    State.canal_carregando = true
    State.canal_erro = ""
    State.canal_videos = { itens = {}, pagina = nil, carregando = false, erro = "" }
    publicar_canal()
    local r = Api.canal(id)
    State.canal_carregando = false
    if not r.ok then
        State.canal_erro = r.error
        publicar_canal()
        return
    end
    local item = r.items[1]
    local sn = item.snippet
    local stats = item.statistics or {}
    local cd = item.contentDetails or {}
    local avatar = sn.thumbnails and (sn.thumbnails.medium or sn.thumbnails.default)
    local uploads = cd.relatedPlaylists and cd.relatedPlaylists.uploads
    State.canal = {
        titulo = sn.title,
        avatar = Thumbs.caminho(avatar and avatar.url, `canal_{id}`),
        inscritos = if stats.hiddenSubscriberCount
            then "inscritos ocultos"
            elseif stats.subscriberCount then `{Format.contagem(stats.subscriberCount)} inscritos`
            else "",
        descricao = sn.description or "",
        uploads_playlist = uploads,
    }
    publicar_canal()
    carregar_uploads(nil)
end

-- ===========================================================================
-- Handlers (globais — o motor os chama pelo nome)
-- ===========================================================================

function init(): ()
    ctx.busca = ""
    ctx.config_chave = Api.chave_atual()
    ctx.config_erro = ""
    publicar_home()
    publicar_busca()
    publicar_video()
    publicar_canal()
    publicar_comentarios()
    if Api.chave_ok() then
        ctx.view = "home"
        carregar_populares(nil)
    else
        ctx.view = "config"
    end
end

function pesquisar(): ()
    local q = string.gsub(string.gsub(ctx.busca or "", "^%s+", ""), "%s+$", "")
    if q == "" then
        return
    end
    State.busca_texto = q
    State.busca = { itens = {}, pagina = nil, carregando = false, erro = "" }
    ir_para("busca")
    carregar_busca(nil)
end

function carregar_mais_home(): ()
    if State.home.pagina then
        carregar_populares(State.home.pagina)
    end
end

function carregar_mais_busca(): ()
    if State.busca.pagina then
        carregar_busca(State.busca.pagina)
    end
end

function carregar_mais_comentarios(): ()
    if State.video_id and State.comentarios.pagina then
        carregar_comentarios(State.video_id, State.comentarios.pagina)
    end
end

function carregar_mais_canal(): ()
    if State.canal_videos.pagina then
        carregar_uploads(State.canal_videos.pagina)
    end
end

function abrir_video(id: string): ()
    ir_para("video")
    carregar_video(id)
end

function abrir_canal(id: string): ()
    ir_para("canal")
    carregar_canal(id)
end

function voltar(): ()
    local anterior = table.remove(State.historico)
    ctx.view = anterior or "home"
end

function ir_config(): ()
    ctx.config_chave = Api.chave_atual()
    ctx.config_erro = ""
    ir_para("config")
end

function salvar_chave(): ()
    local k = string.gsub(string.gsub(ctx.config_chave or "", "^%s+", ""), "%s+$", "")
    if k == "" then
        ctx.config_erro = "Cole uma chave de API válida."
        return
    end
    Api.definir_chave(k)
    ctx.config_erro = ""
    voltar()
    if #State.home.itens == 0 then
        carregar_populares(nil)
    end
end

-- Abre a página DE VERDADE do YouTube (não o IFrame Player embutido — ver o
-- comentário no `Cargo.toml` sobre por quê) numa webview nativa. É aqui que
-- o vídeo de fato toca: a API de Dados não devolve stream nenhum, só
-- metadados, e o motor não tem decodificador de vídeo — a webview É o
-- player, o mesmo que o navegador usaria.
function assistir(): ()
    if not State.video_id then
        return
    end
    open_window({
        webview_url = `https://www.youtube.com/watch?v={State.video_id}`,
        title = if State.video then State.video.titulo else "YouTube",
        width = 1280,
        height = 800,
    })
end
