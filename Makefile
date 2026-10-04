# =====================================================================
#  Makefile - hello world GRAFICO per Commodore 64
# ---------------------------------------------------------------------
#  Comandi:
#     make             -> assembla graphic.asm in graphic.prg
#     make run         -> assembla (se serve) e avvia in VICE
#     make screenshot  -> esegue in VICE e salva screenshot.png
#     make clean       -> rimuove i file generati
#
#  Requisiti:
#     acme   (assembler)  - su Arch/CachyOS:  sudo pacman -S acme
#     x64sc  (VICE)       - su Arch/CachyOS:  sudo pacman -S vice
# =====================================================================

ACME ?= $(shell command -v acme 2>/dev/null || echo $(HOME)/.local/bin/acme)
X64  ?= x64sc

PRG := graphic.prg
SRC := graphic.asm

.PHONY: all run screenshot clean

all: $(PRG)

$(PRG): $(SRC)
	@if [ ! -x "$(ACME)" ]; then \
		echo "ERRORE: ACME non trovato ('$(ACME)')."; \
		echo "Installalo con:  sudo pacman -S acme"; \
		exit 1; \
	fi
	$(ACME) $(SRC)
	@echo "-> $(PRG) creato."

run: $(PRG)
	@command -v $(X64) >/dev/null 2>&1 || { \
		echo "ERRORE: '$(X64)' non trovato. Installa VICE: sudo pacman -S vice"; \
		exit 1; \
	}
	$(X64) -autostart $(PRG)

# Esegue in VICE in modalita' warp e salva la schermata all'uscita.
# (VICE esce con codice 1 quando raggiunge -limitcycles: lo ignoriamo.)
screenshot: $(PRG)
	$(X64) -autostart $(PRG) -warp -limitcycles 20000000 \
		-exitscreenshot screenshot.png >/dev/null 2>&1 || true
	@echo "-> screenshot.png creato."

clean:
	rm -f $(PRG) screenshot.png
