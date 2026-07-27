FASM     ?= fasm
SRC_DIR   = src
TESTS_DIR = tests
BIN_DIR   = bin

TEST_SRCS = $(wildcard $(TESTS_DIR)/test_*.asm)
TEST_BINS = $(patsubst $(TESTS_DIR)/%.asm,$(BIN_DIR)/%,$(TEST_SRCS))

.PHONY: all test smoke writhdeck clean

all: test writhdeck

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

smoke: $(BIN_DIR)
	$(FASM) $(TESTS_DIR)/smoke.asm $(BIN_DIR)/smoke
	chmod +x $(BIN_DIR)/smoke
	$(BIN_DIR)/smoke

writhdeck: $(BIN_DIR)
	$(FASM) $(SRC_DIR)/main.asm $(BIN_DIR)/writhdeck
	chmod +x $(BIN_DIR)/writhdeck

$(BIN_DIR)/%: $(TESTS_DIR)/%.asm | $(BIN_DIR)
	$(FASM) $< $@
	chmod +x $@

test: $(TEST_BINS)
	@for b in $(TEST_BINS); do \
	    echo "== $$b =="; \
	    $$b; status=$$?; \
	    if [ $$status -ne 0 ]; then echo "ECHEC: $$b (exit $$status)"; exit 1; fi; \
	done
	@echo "tous les tests sont passes"

clean:
	rm -rf $(BIN_DIR)
