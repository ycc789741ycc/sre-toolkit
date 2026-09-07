ifneq (,$(wildcard .env))
include .env
export
endif

HOST ?= 172.16.1.13
SSH_USER ?=
SSH_TARGET := $(if $(SSH_USER),$(SSH_USER)@$(HOST),$(HOST))
SCRIPT := scripts/vscode-server-cleanup.sh

.PHONY: help vscode-status vscode-clean vscode-clean-apply

help:
	@echo "sre-toolkit targets:"
	@echo "  make vscode-status      Report vscode-server versions/size (read-only)"
	@echo "  make vscode-clean       Same as above: dry-run, shows what would be removed"
	@echo "  make vscode-clean-apply Kill stale process trees and delete old version installs"
	@echo ""
	@echo "HOST/SSH_USER are read from .env (see .env.example), or override on the"
	@echo "command line, e.g. make vscode-status HOST=other-host SSH_USER=someone"
	@echo ""
	@echo "Currently: HOST=$(HOST) SSH_USER=$(SSH_USER)"

vscode-status vscode-clean:
	@bash $(SCRIPT) --host $(SSH_TARGET)

vscode-clean-apply:
	@bash $(SCRIPT) --host $(SSH_TARGET) --apply --yes
