--!strict
-- Cliente para a API de Dados do YouTube v3 — só os endpoints que este app usa
-- (busca, populares, vídeo, canal, uploads, comentários). A chave de API mora
-- no `storage` (persiste entre execuções), nunca no código. Sem chave
-- configurada, toda função devolve `{ ok = false, error = "sem_chave" }` sem
-- tentar a rede.
--
-- Pegar uma chave: console.cloud.google.com → criar projeto → ativar
-- "YouTube Data API v3" → Credenciais → Criar credenciais → Chave de API.

local Cache = require("cache")

local Api = {}

local BASE = "https://www.googleapis.com/youtube/v3"
local cliente = http(BASE, { timeout = 10000, retries = 1 })

-- Chave de cache estável: caminho + query ORDENADA (a ordem de inserção da
-- tabela não é garantida, então sem ordenar a mesma chamada podia gerar duas
-- chaves diferentes e nunca bater no cache).
local function chave_de_cache(caminho: string, query: { [string]: any }): string
    local nomes = {}
    for nome in query do
        table.insert(nomes, nome)
    end
    table.sort(nomes)
    local partes = { caminho }
    for _, nome in nomes do
        table.insert(partes, `{nome}={query[nome]}`)
    end
    return table.concat(partes, "&")
end

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
-- Passa por `Cache` primeiro — 10 minutos por chamada bem-sucedida (a chave
-- de cache é montada ANTES de `query.key` entrar, então trocar a chave de
-- API não invalida nada). Erro nunca é cacheado: uma falha de rede passageira
-- não deve ficar "grudada" por 10 minutos.
local function chamar(caminho: string, query: { [string]: any }): any
    local k = chave()
    if not k then
        return { ok = false, error = "sem_chave" }
    end
    local chave_cache = chave_de_cache(caminho, query)
    local em_cache = Cache.pegar(chave_cache)
    if em_cache then
        return em_cache
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
    local resultado = {
        ok = true,
        items = res.json.items or {},
        next_page_token = res.json.nextPageToken,
    }
    Cache.guardar(chave_cache, resultado, 600)
    return resultado
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
