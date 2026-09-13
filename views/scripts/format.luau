--!strict
-- Formatação de números/duração vindos da API do YouTube — puro, sem estado.
-- Nada aqui toca `ctx`; é usado pelos módulos que projetam dado na vitrine.

local Format = {}

-- "1234567" -> "1,2 mi" · "8340" -> "8,3 mil" · "512" -> "512"
function Format.contagem(valor: string | number): string
    local n = tonumber(valor) or 0
    if n >= 1000000 then
        return string.format("%.1f mi", n / 1000000):gsub("%.0", "")
    elseif n >= 1000 then
        return string.format("%.1f mil", n / 1000):gsub("%.0", "")
    end
    return tostring(math.floor(n))
end

-- Duração ISO 8601 do `contentDetails.duration` ("PT4M13S", "PT1H2M") -> "4:13"/"1:02:00".
function Format.duracao(iso: string?): string
    if not iso then
        return ""
    end
    local h = tonumber(string.match(iso, "(%d+)H")) or 0
    local m = tonumber(string.match(iso, "(%d+)M")) or 0
    local s = tonumber(string.match(iso, "(%d+)S")) or 0
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, s)
    end
    return string.format("%d:%02d", m, s)
end

-- "2026-09-01T12:00:00Z" -> "2026-09-01" (o que `date.*` sabe ler).
function Format.so_data(publicado_em: string?): string
    if not publicado_em then
        return ""
    end
    return date.date_of(publicado_em) or publicado_em
end

-- "há quanto tempo", grosseiro (dias/meses/anos) — o suficiente para uma
-- listagem; não pretende ser exato ao segundo.
function Format.ha_quanto_tempo(publicado_em: string?): string
    local d = Format.so_data(publicado_em)
    if d == "" then
        return ""
    end
    local bruto = date.diff(date.today(), d)
    if bruto == nil then
        return d
    end
    local dias = math.abs(bruto)
    if dias < 1 then
        return "hoje"
    elseif dias < 30 then
        return `há {dias} dia{if dias == 1 then "" else "s"}`
    elseif dias < 365 then
        local meses = math.floor(dias / 30)
        return `há {meses} {if meses == 1 then "mês" else "meses"}`
    end
    local anos = math.floor(dias / 365)
    return `há {anos} ano{if anos == 1 then "" else "s"}`
end

return Format
