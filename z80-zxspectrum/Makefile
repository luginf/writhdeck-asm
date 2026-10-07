SJASMPLUS ?= sjasmplus
PYTHON    ?= python3
TESTS_DIR  = tests
SPECTRUM_DIR = spectrum

TEST_SRCS = $(wildcard $(TESTS_DIR)/test_*.asm)
TEST_SNAS = $(patsubst %.asm,%.sna,$(TEST_SRCS))

.PHONY: all test smoke writhdeck clean

all: test writhdeck

smoke: $(TESTS_DIR)/smoke.sna
	$(PYTHON) $(TESTS_DIR)/zrcp_harness.py $(TESTS_DIR)/smoke.sna 36864:aa42

%.sna: %.asm
	$(SJASMPLUS) --outprefix=$(TESTS_DIR)/ --sym=$(basename $@).sym $<

writhdeck: $(SPECTRUM_DIR)/main.asm tests/gen_loader.py
	rm -f $(SPECTRUM_DIR)/writhdeck.tap $(SPECTRUM_DIR)/writhdeck.sna
	$(SJASMPLUS) --outprefix=$(SPECTRUM_DIR)/ --sym=$(SPECTRUM_DIR)/main.sym $(SPECTRUM_DIR)/main.asm
	$(PYTHON) tests/gen_loader.py $(SPECTRUM_DIR)/main.sym $(SPECTRUM_DIR)/writhdeck.tap
	@echo "-> $(SPECTRUM_DIR)/writhdeck.tap (livrable reel, autoloader BASIC inclus) + writhdeck.sna (tests automatises uniquement)"

test: $(TEST_SNAS) writhdeck
	@for t in $(TEST_SRCS); do \
	    py="$${t%.asm}.py"; \
	    if [ -f "$$py" ]; then \
	        echo "== $$py =="; \
	        (cd $(TESTS_DIR) && $(PYTHON) "$$(basename "$$py")") || exit 1; \
	    fi; \
	done
	@echo "== tests/test_tape.py =="
	@(cd $(TESTS_DIR) && $(PYTHON) test_tape.py) || exit 1
	@echo "== tests/test_main.py =="
	@(cd $(TESTS_DIR) && $(PYTHON) test_main.py) || exit 1
	@echo "== tests/test_autoload.py =="
	@(cd $(TESTS_DIR) && $(PYTHON) test_autoload.py) || exit 1
	@echo "tous les tests sont passes"

clean:
	rm -f $(TESTS_DIR)/*.sna $(TESTS_DIR)/*.sym core/*.sna
	rm -f $(SPECTRUM_DIR)/*.tap $(SPECTRUM_DIR)/*.sna $(SPECTRUM_DIR)/*.sym
