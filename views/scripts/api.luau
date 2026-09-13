--!strict
-- Cliente para a API de Dados do YouTube v3 — só os endpoints que este app usa
-- (busca, populares, vídeo, canal, uploads, comentários). A chave de API mora
-- no `storage` (persiste entre execuções), nunca no código. Sem chave
-- configurada, toda função devolve `{ ok = false, error = "sem_chave" }` sem
-- tentar a rede.
--
-- Pegar uma chave: console.cloud.google.com → criar projeto → ativar
-- "YouTube Data API v3" → Credenciais → Criar credenciais → Chave de API.

local Api = {}

local BASE = "https://www.googleapis.com/youtube/v3"
local cliente = http(BASE, { timeout = 10000, retries = 1 })

local function chave(): string?
    local k = storage.get("youtube_api_key")
    if type(k) == "string" and k ~= "" then
        return k
    end
    return nil
end

function Api.chave_ok(): boolean
    return chave() ~= nil
end

function Api.chave_atual(): string
    return chave() or ""
end

function Api.definir_chave(k: string): ()
    storage.set("youtube_api_key", k)
end

-- Resultado uniforme de toda chamada de listagem: `{ ok, items, next_page_token, error, status }`.
local function chamar(caminho: string, query: { [string]: any }): any
    local k = chave()
    if not k then
        return { ok = false, error = "sem_chave" }
    end
    query.key = k
    local res = cliente:get(caminho, { query = query })
    if not res.ok then
        local msg = "falha na rede"
        if res.json and res.json.error and res.json.error.message then
            msg = res.json.error.message
        elseif res.error ~= "" then
            msg = res.error
        end
        return { ok = false, error = msg, status = res.status }
    end
    return {
        ok = true,
        items = res.json.items or {},
        next_page_token = res.json.nextPageToken,
    }
end

-- Vídeos em alta no Brasil. `pagina` = `next_page_token` de uma chamada
-- anterior (`nil` = primeira página).
function Api.populares(pagina: string?): any
    return chamar("/videos", {
        part = "snippet,statistics,contentDetails",
        chart = "mostPopular",
        regionCode = "BR",
        maxResults = 24,
        pageToken = pagina,
    })
end

function Api.buscar(consulta: string, pagina: string?): any
    return chamar("/search", {
        part = "snippet",
        type = "video",
        q = consulta,
        maxResults = 24,
        pageToken = pagina,
    })
end

function Api.video(id: string): any
    local r = chamar("/videos", { part = "snippet,statistics,contentDetails", id = id })
    if r.ok and #r.items == 0 then
        return { ok = false, error = "vídeo não encontrado (removido ou privado)" }
    end
    return r
end

function Api.canal(id: string): any
    local r = chamar("/channels", { part = "snippet,statistics,contentDetails", id = id })
    if r.ok and #r.items == 0 then
        return { ok = false, error = "canal não encontrado" }
    end
    return r
end

function Api.uploads_do_canal(playlist_id: string, pagina: string?): any
    return chamar("/playlistItems", {
        part = "snippet",
        playlistId = playlist_id,
        maxResults = 24,
        pageToken = pagina,
    })
end

function Api.comentarios(video_id: string, pagina: string?): any
    local r = chamar("/commentThreads", {
        part = "snippet",
        videoId = video_id,
        maxResults = 20,
        order = "relevance",
        pageToken = pagina,
    })
    if not r.ok and r.status == 403 then
        -- Comentários desligados no vídeo: não é falha, é uma lista vazia.
        return { ok = true, items = {} }
    end
    return r
end

return Api
