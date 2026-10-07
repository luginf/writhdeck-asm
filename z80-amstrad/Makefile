SJASMPLUS ?= sjasmplus
PYTHON    ?= python3
IDSK      ?= iDSK
TESTS_DIR  = tests
CPC_DIR    = cpc
LOAD_ADDR  = 8000

TEST_SRCS = $(wildcard $(TESTS_DIR)/test_*.asm)
TEST_BINS = $(patsubst %.asm,%.bin,$(TEST_SRCS))

.PHONY: all test writhdeck dsk clean

all: test writhdeck dsk

%.bin: %.asm
	$(SJASMPLUS) --outprefix=$(TESTS_DIR)/ --sym=$(basename $@).sym $<

writhdeck: $(CPC_DIR)/main.asm
	rm -f $(CPC_DIR)/writhdeck.bin
	$(SJASMPLUS) --outprefix=$(CPC_DIR)/ --sym=$(CPC_DIR)/main.sym $(CPC_DIR)/main.asm
	@echo "-> $(CPC_DIR)/writhdeck.bin (charge par tests/zrcp_harness.py, injection memoire)"

# Image disquette CPC (AMSDOS), livrable reel pour materiel/emulateur
# (xcpc, WinAPE, CPCEMU, RVM, materiel reel...) -- zesarux dans cet
# environnement n'emule aucun lecteur de disquette CPC (voir README),
# donc PAS verifiee ici par le harnais de test, seulement par un
# aller-retour d'extraction (iDSK -g) compare octet a octet au .bin
# source lors de sa creation initiale.
dsk: writhdeck
	rm -f $(CPC_DIR)/writhdeck.dsk
	$(eval EXEC_ADDR := $(shell grep '^_start:' $(CPC_DIR)/main.sym | grep -oE '0x[0-9A-Fa-f]+' | sed 's/0x0*/0x/'))
	cp $(CPC_DIR)/writhdeck.bin $(CPC_DIR)/WRITHDEK.BIN
	$(IDSK) $(CPC_DIR)/writhdeck.dsk -n
	$(IDSK) $(CPC_DIR)/writhdeck.dsk -i $(CPC_DIR)/WRITHDEK.BIN -t 1 -c $(LOAD_ADDR) -e $(subst 0x,,$(EXEC_ADDR)) -f
	rm -f $(CPC_DIR)/WRITHDEK.BIN
	@echo "-> $(CPC_DIR)/writhdeck.dsk (livrable reel : demarrer, RUN\"WRITHDEK\")"

test: $(TEST_BINS) writhdeck
	@for t in $(TEST_SRCS); do \
	    py="$${t%.asm}.py"; \
	    if [ -f "$$py" ]; then \
	        echo "== $$py =="; \
	        (cd $(TESTS_DIR) && $(PYTHON) "$$(basename "$$py")") || exit 1; \
	    fi; \
	done
	@echo "tous les tests sont passes"

clean:
	rm -f $(TESTS_DIR)/*.bin $(TESTS_DIR)/*.sym
	rm -f $(CPC_DIR)/*.bin $(CPC_DIR)/*.dsk $(CPC_DIR)/*.sym $(CPC_DIR)/WRITHDEK.BIN
