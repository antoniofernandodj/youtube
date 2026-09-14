--!strict
-- Cache em disco de imagens remotas (thumbnails, avatares de canal). O motor
-- não baixa imagem por URL: `<image>` só lê do sistema de arquivos (ver
-- AGENTS.md). `download_file` grava os bytes crus direto no caminho — ao
-- contrário de `fetch`, que decodifica a resposta como texto e corromperia um
-- JPEG.

local Thumbs = {}

local function extensao(url: string): string
    return string.match(url, "%.([%a]+)$") or "jpg"
end

-- Devolve o caminho LOCAL da imagem em `url`, baixando-a na primeira vez.
-- `chave` identifica o arquivo em cache (o id do vídeo/canal — estável, sem
-- caractere que confunda um nome de arquivo). Chamadas seguintes acham o
-- arquivo já no disco e nem tocam a rede.
function Thumbs.caminho(url: string?, chave: string): string?
    if not url or url == "" then
        return nil
    end
    local caminho = `{ctx.cache_dir}/{chave}.{extensao(url)}`
    local ja_existe = fetch(`file://{caminho}`)
    if ja_existe.ok then
        return caminho
    end
    local res = download_file(url, caminho)
    if not res.ok then
        console.warn("thumbs: falha ao baixar", url, "->", caminho, "erro:", res.error)
        return nil
    end
    return caminho
end

return Thumbs
