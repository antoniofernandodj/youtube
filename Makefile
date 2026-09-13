VERSION := $(shell grep '^version' Cargo.toml | head -1 | cut -d'"' -f2)
APP     := youtube

BOLD  := \033[1m
RESET := \033[0m
GREEN := \033[32m
CYAN  := \033[36m
RED   := \033[31m

export CARGO_TERM_COLOR := never

.DEFAULT_GOAL := help

# O app NÃO é autocontido: os `.gv`, o `.gss` e os `.luau` de `views/` são lidos
# em runtime — é o que dá o hot-reload. Todo pacote daqui leva a pasta junto, e
# todo alvo de pacote CONFERE que ela foi: um pacote sem `views/` compila,
# instala, abre — e mostra uma janela vazia, na máquina de outra pessoa.
VIEWS := views

# ── Build ─────────────────────────────────────────────────────────────────────

.PHONY: build
build: ## Compila em modo release (Linux)
	cargo build --release

.PHONY: run
run: ## Roda em modo debug
	cargo run

.PHONY: check
check: ## Verifica sem linkar (mais rápido que build)
	cargo check

# ── Qualidade ─────────────────────────────────────────────────────────────────

.PHONY: fmt
fmt: ## Formata o código com rustfmt
	cargo fmt --all

.PHONY: clippy
clippy: ## Roda o clippy com warnings como erro
	cargo clippy --all-targets -- -D warnings

.PHONY: luau
luau: ## Type-check dos scripts Luau com luau-lsp
	@command -v luau-lsp >/dev/null 2>&1 || \
		(echo "$(RED)luau-lsp não encontrado$(RESET) — https://github.com/JohnnyMorganz/luau-lsp" && exit 1)
	@n=$$(find $(VIEWS) -name '*.luau' ! -name '*.d.luau' | wc -l); \
	if [ "$$n" = 0 ]; then \
		echo "  (nenhum .luau em $(VIEWS)/ — o comportamento está embutido nos .gv)"; \
	else \
		luau-lsp analyze --platform=standard \
			--definitions=$(VIEWS)/scripts/glacier.d.luau \
			$$(find $(VIEWS) -name '*.luau' ! -name '*.d.luau'); \
	fi

.PHONY: lint
lint: clippy luau ## Tudo que precisa passar antes de commitar

# ── Windows (cross-compile a partir do Linux) ─────────────────────────────────
#
# Para compilar DE dentro do Windows, use o `fazer.bat` ao lado deste arquivo:
# lá não há make, e o cargo-xwin não é necessário (o MSVC já é nativo).

WIN_TARGET   := x86_64-pc-windows-msvc
WIN_BIN      := target/$(WIN_TARGET)/release/$(APP).exe
WIN_DIST_DIR := dist/$(APP)-windows
WIN_DIST_ZIP := dist/$(APP)-$(VERSION)-windows.zip

# `+crt-static` embute a CRT: sem isso o .exe exige o Visual C++ Redistributable
# na máquina de destino, e falha com uma caixa de erro que não diz qual DLL
# faltou.
WIN_RUSTFLAGS := -C target-feature=+crt-static

.PHONY: win-deps
win-deps: ## Instala cargo-xwin e o target MSVC, se faltarem
	@command -v cargo-xwin >/dev/null 2>&1 || \
		(echo "$(BOLD)Instalando cargo-xwin...$(RESET)" && cargo install cargo-xwin)
	@rustup target list --installed | grep -q '^$(WIN_TARGET)$$' || \
		rustup target add $(WIN_TARGET)

.PHONY: windows
windows: win-deps ## Compila o .exe para Windows via cargo-xwin
	RUSTFLAGS="$(WIN_RUSTFLAGS)" cargo xwin build --release --target $(WIN_TARGET)
	@echo ""
	@echo "$(GREEN)Executável Windows:$(RESET)"
	@ls -lh $(WIN_BIN)

.PHONY: windows-dist
windows-dist: windows ## Monta o .zip do Windows (exe + views/ + instalador)
	@command -v zip >/dev/null 2>&1 || \
		(echo "$(RED)Instale 'zip' (sudo apt install zip)$(RESET)" && exit 1)
	@rm -rf $(WIN_DIST_DIR) $(WIN_DIST_ZIP)
	@mkdir -p $(WIN_DIST_DIR)
	@cp $(WIN_BIN) $(WIN_DIST_DIR)/
	@# `views/` INTEIRO, nunca sub-pasta por sub-pasta: copiar item a item faz
	@# este alvo esquecer em silêncio um diretório novo.
	@cp -r $(VIEWS) $(WIN_DIST_DIR)/
	@# O storage do glacier é estado da máquina de quem desenvolveu.
	@find $(WIN_DIST_DIR) -name '.glacier-storage' -type d -exec rm -rf {} + 2>/dev/null || true
	@cp packaging/windows/instalar.bat packaging/windows/desinstalar.bat $(WIN_DIST_DIR)/
	@# CRLF: o LEIA-ME é aberto no Notepad, que mostra um arquivo LF como uma
	@# linha só nas versões mais antigas do Windows.
	@sed 's/$$/\r/' packaging/windows/LEIA-ME.txt > $(WIN_DIST_DIR)/LEIA-ME.txt
	@$(MAKE) --no-print-directory conferir-pacote DIR=$(WIN_DIST_DIR)
	@cd dist && zip -qr $(notdir $(WIN_DIST_ZIP)) $(notdir $(WIN_DIST_DIR))
	@echo ""
	@echo "$(GREEN)Pacote Windows:$(RESET)"
	@ls -lh $(WIN_DIST_ZIP)

# ── Linux ─────────────────────────────────────────────────────────────────────

LIN_DIST_DIR := dist/$(APP)-linux
LIN_DIST_TGZ := dist/$(APP)-$(VERSION)-linux-x86_64.tar.gz

.PHONY: linux-dist
linux-dist: build ## Monta o .tar.gz portátil do Linux (binário + views/ + instalador)
	@rm -rf $(LIN_DIST_DIR) $(LIN_DIST_TGZ)
	@mkdir -p $(LIN_DIST_DIR)
	@cp target/release/$(APP) $(LIN_DIST_DIR)/
	@cp -r $(VIEWS) $(LIN_DIST_DIR)/
	@find $(LIN_DIST_DIR) -name '.glacier-storage' -type d -exec rm -rf {} + 2>/dev/null || true
	@cp packaging/linux/instalar.sh $(LIN_DIST_DIR)/
	@chmod +x $(LIN_DIST_DIR)/instalar.sh
	@cp packaging/linux/LEIA-ME.txt $(LIN_DIST_DIR)/
	@$(MAKE) --no-print-directory conferir-pacote DIR=$(LIN_DIST_DIR)
	@cd dist && tar czf $(notdir $(LIN_DIST_TGZ)) $(notdir $(LIN_DIST_DIR))
	@echo ""
	@echo "$(GREEN)Pacote Linux:$(RESET)"
	@ls -lh $(LIN_DIST_TGZ)

.PHONY: deb
deb: build ## Gera o .deb (wrapper em /usr/bin, programa e views/ em /usr/share)
	@command -v cargo-deb >/dev/null 2>&1 || \
		(echo "$(BOLD)Instalando cargo-deb...$(RESET)" && cargo install cargo-deb)
	@find $(VIEWS) -name '.glacier-storage' -type d -exec rm -rf {} + 2>/dev/null || true
	cargo deb --no-build -o dist/
	@echo ""
	@echo "$(GREEN)Pacote .deb:$(RESET)"
	@ls -lh dist/*.deb

# Vazio quando já se está como root (container/CI); senão usa sudo.
SUDO := $(shell [ "$$(id -u)" = 0 ] || command -v sudo)

.PHONY: install
install: linux-dist ## Instala em ~/.local (sem sudo)
	@cd $(LIN_DIST_DIR) && ./instalar.sh

.PHONY: install-sistema
install-sistema: linux-dist ## Instala em /usr/local para todos os usuários (sudo)
	@cd $(LIN_DIST_DIR) && ./instalar.sh --sistema

.PHONY: uninstall
uninstall: ## Remove o que foi instalado em ~/.local
	@test -x $(LIN_DIST_DIR)/instalar.sh \
		&& (cd $(LIN_DIST_DIR) && ./instalar.sh --remover) \
		|| (rm -f  $$HOME/.local/bin/$(APP) \
		            $$HOME/.local/share/applications/$(APP).desktop; \
		    rm -rf $$HOME/.local/share/$(APP); \
		    echo "$(APP) removido de ~/.local.")

# ── Conferência de pacote ─────────────────────────────────────────────────────

# Cada alvo de pacote termina aqui, e falha ALTO. Um pacote sem `views/` só dá
# sintoma na máquina de quem baixou, e sem nenhuma mensagem que aponte a causa.
.PHONY: conferir-pacote
conferir-pacote:
	@test -n "$(DIR)" || (echo "$(RED)conferir-pacote precisa de DIR=$(RESET)" && exit 1)
	@test -d "$(DIR)/$(VIEWS)" || \
		(echo "$(RED)PACOTE INCOMPLETO: falta $(VIEWS)/ em $(DIR)$(RESET)" && exit 1)
	@orig=$$(find $(VIEWS) -type f ! -path '*/.glacier-storage/*' | wc -l); \
	 novo=$$(find $(DIR)/$(VIEWS) -type f | wc -l); \
	 test "$$novo" -ge "$$orig" || \
		(echo "$(RED)PACOTE INCOMPLETO: $(VIEWS)/ tem $$orig arquivos, o pacote levou $$novo$(RESET)" && exit 1); \
	 echo "$(GREEN)  pacote ok$(RESET) — $$novo arquivos de $(VIEWS)/ empacotados"

# ── Limpeza ───────────────────────────────────────────────────────────────────

.PHONY: clean
clean: ## Remove artefatos de build
	cargo clean

.PHONY: clean-dist
clean-dist: ## Remove só os pacotes gerados
	rm -rf dist

# ── Info ──────────────────────────────────────────────────────────────────────

.PHONY: version
version: ## Exibe a versão atual
	@echo "$(VERSION)"

.PHONY: help
help: ## Lista todos os targets disponíveis
	@echo ""
	@echo "$(BOLD)$(APP) $(VERSION) — targets disponíveis$(RESET)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { \
		printf "  $(CYAN)%-16s$(RESET) %s\n", $$1, $$2 \
	}' $(MAKEFILE_LIST)
	@echo ""
	@echo "  $(BOLD)No Windows:$(RESET) use  fazer.bat  (não há make lá)"
	@echo ""
