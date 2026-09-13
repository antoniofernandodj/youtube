--!strict
-- O depósito: tipado, com a forma real do dado. `app.luau` é a vitrine — lê
-- daqui e escreve o `ctx` já filtrado/formatado (ver AGENTS.md, "Onde mora o
-- estado que não é texto").

export type Video = {
    id: string,
    titulo: string,
    canal: string,
    canal_id: string,
    thumb: string?,
    meta: string,
}

export type Comentario = {
    autor: string,
    avatar: string?,
    texto: string,
    curtidas: string,
    quando: string,
}

export type Lista = {
    itens: { Video },
    pagina: string?,       -- nextPageToken da última chamada
    carregando: boolean,
    erro: string,
}

export type ListaComentarios = {
    itens: { Comentario },
    pagina: string?,
    carregando: boolean,
}

local function lista_vazia(): Lista
    return { itens = {}, pagina = nil, carregando = false, erro = "" }
end

export type State = {
    historico: { string },           -- pilha de views, para "voltar"
    busca_texto: string,
    home: Lista,
    busca: Lista,
    video_id: string?,
    video: {
        titulo: string,
        canal: string,
        canal_id: string,
        thumb: string?,
        meta: string,
        descricao: string,
    }?,
    video_carregando: boolean,
    video_erro: string,
    comentarios: ListaComentarios,
    canal_id: string?,
    canal: {
        titulo: string,
        avatar: string?,
        inscritos: string,
        descricao: string,
        uploads_playlist: string?,
    }?,
    canal_carregando: boolean,
    canal_erro: string,
    canal_videos: Lista,
}

local State: State = {
    historico = {},
    busca_texto = "",
    home = lista_vazia(),
    busca = lista_vazia(),
    video_id = nil,
    video = nil,
    video_carregando = false,
    video_erro = "",
    comentarios = { itens = {}, pagina = nil, carregando = false },
    canal_id = nil,
    canal = nil,
    canal_carregando = false,
    canal_erro = "",
    canal_videos = lista_vazia(),
}

return State
