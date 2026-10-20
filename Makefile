SRC_DIR := src
DIST_DIR := dist
STAGE_DIR := $(DIST_DIR)/sdcard
# Shown in the tools: at most 8 characters fit the B&W EXIT labels.
VERSION ?= $(or $(shell git rev-parse HEAD 2>/dev/null | cut -c1-7),dev)
ZIP_NAME ?= expresslrs-lua-$(VERSION)

STYLUA_VERSION := 2.3.1
STYLUA := bin/stylua
STYLUA_URL := https://github.com/JohnnyMorganz/StyLua/releases/download/v$(STYLUA_VERSION)/stylua-linux-x86_64.zip

LUALS_VERSION := 3.17.1
LUALS_DIR := bin/lua-language-server
LUALS := $(LUALS_DIR)/bin/lua-language-server
LUALS_URL := https://github.com/LuaLS/lua-language-server/releases/download/$(LUALS_VERSION)/lua-language-server-$(LUALS_VERSION)-linux-x64.tar.gz

LUAC_VERSION := 1.0.0
LUAC_DIR := bin/edgetx-luac
LUAC := $(LUAC_DIR)/edgetx-luac
LUAC_URL := https://github.com/EdgeTX/edgetx-luac-action/releases/download/v$(LUAC_VERSION)/edgetx-luac-v$(LUAC_VERSION)-linux-x64.tar.gz

.PHONY: help install-tools install-stylua install-luals install-luac format format-check typecheck check build sync push

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  install-tools   Install stylua, lua-language-server and edgetx-luac"
	@echo "  install-stylua  Install stylua"
	@echo "  install-luals   Install lua-language-server"
	@echo "  install-luac    Install the EdgeTX Lua compiler"
	@echo "  format          Format Lua files with stylua"
	@echo "  format-check    Check formatting without modifying files"
	@echo "  typecheck       Run lua-language-server type checking"
	@echo "  check           Run format-check and typecheck"
	@echo "  build           Build an SD card zip with compiled bytecode (VERSION=, ZIP_NAME=)"
	@echo "  sync            Sync source files to EdgeTX simulator SD card"
	@echo "  push            Install package to EdgeTX radio and eject"

install-stylua:
	mkdir -p bin
	curl -fSL -o bin/stylua.zip $(STYLUA_URL)
	unzip -o -q bin/stylua.zip -d bin
	rm bin/stylua.zip
	chmod +x $(STYLUA)

install-luals:
	mkdir -p $(LUALS_DIR)
	curl -fSL $(LUALS_URL) | tar xz -C $(LUALS_DIR)

install-luac:
	mkdir -p $(LUAC_DIR)
	curl -fSL $(LUAC_URL) | tar xz -C $(LUAC_DIR)

install-tools: install-stylua install-luals install-luac

format:
	$(STYLUA) $(SRC_DIR)

format-check:
	$(STYLUA) --check $(SRC_DIR)

typecheck:
	$(LUALS) --check .

check: format-check typecheck

# Keep in sync with the dev libraries and excludes in edgetx.yml.
build:
	rm -rf $(DIST_DIR)
	mkdir -p $(STAGE_DIR)
	cp -r $(SRC_DIR)/SCRIPTS $(SRC_DIR)/WIDGETS $(STAGE_DIR)/
	rm -rf $(STAGE_DIR)/SCRIPTS/CRSFSimulator
	rm -f $(STAGE_DIR)/SCRIPTS/TOOLS/ExpressLRSBind/history.txt $(STAGE_DIR)/WIDGETS/ELRSVTXAdmin/presets.txt
	find $(STAGE_DIR) -name '*.luac' -delete
	printf 'return "%s"\n' '$(VERSION)' > $(STAGE_DIR)/SCRIPTS/ELRS/version.lua
	find $(STAGE_DIR) -name '*.lua' | while read -r f; do $(LUAC) -s -o "$${f}c" "$$f" || exit 1; done
	cd $(STAGE_DIR) && zip -q -r ../$(ZIP_NAME).zip SCRIPTS WIDGETS
	@echo "Built $(DIST_DIR)/$(ZIP_NAME).zip (version $(VERSION))"

sync:
	edgetx-cli dev sync ../edgetx-sdcard

push:
	edgetx-cli pkg install . --eject
