--!strict
-- Cache em memória com TTL, para toda chamada de rede deste app. Motivo
-- duplo: menos consumo de cota da API em navegação normal (voltar para "Em
-- alta" depois de ver um vídeo, refazer a mesma busca) e — o que importa
-- ainda mais nesta rede — menos chamadas de rede é menos chance de esbarrar
-- num `fetch` que demora demais para resolver. Só vive na memória do
-- processo: fecha o app, esvazia — não precisa ser mais que isso.

local Cache = {}

type Entrada = { valor: any, expira_em: number }

local entradas: { [string]: Entrada } = {}

-- Instante atual em segundos, na mesma escala de `date.epoch` — a única
-- fonte de "agora" que a camada Luau expõe (não há `os.time`).
local function agora(): number
    return date.epoch(date.now(true)) or 0
end

-- Valor em cache para `chave`, ou `nil` se nunca guardado ou já expirado.
function Cache.pegar(chave: string): any
    local e = entradas[chave]
    if not e then
        return nil
    end
    if agora() > e.expira_em then
        entradas[chave] = nil
        return nil
    end
    return e.valor
end

-- Guarda `valor` sob `chave` por `ttl_segundos` (default 600 = 10 min).
function Cache.guardar(chave: string, valor: any, ttl_segundos: number?): ()
    entradas[chave] = {
        valor = valor,
        expira_em = agora() + (ttl_segundos or 600),
    }
end

function Cache.invalidar(chave: string): ()
    entradas[chave] = nil
end

return Cache
