ifneq (,$(wildcard .env))
include .env
export
endif

HOST ?= 172.16.1.13
SSH_USER ?=
SSH_TARGET := $(if $(SSH_USER),$(SSH_USER)@$(HOST),$(HOST))
SCRIPT := scripts/vscode-server-cleanup.sh

ALIAS_SCRIPT := scripts/setup-shell-aliases.sh
# Optional overrides for the alias installer; both are auto-detected by default.
ALIAS_SHELL ?=
RC_FILE ?=
ALIAS_ARGS := $(if $(ALIAS_SHELL),--shell $(ALIAS_SHELL)) $(if $(RC_FILE),--rc-file $(RC_FILE))

.PHONY: help vscode-status vscode-clean vscode-clean-apply \
        aliases-status aliases-install aliases-install-apply aliases-uninstall-apply

help:
	@echo "sre-toolkit targets:"
	@echo "  make vscode-status      Report vscode-server versions/size (read-only)"
	@echo "  make vscode-clean       Same as above: dry-run, shows what would be removed"
	@echo "  make vscode-clean-apply Kill stale process trees and delete old version installs"
	@echo ""
	@echo "  make aliases-status     Show detected platform/shell/rc file and install state"
	@echo "  make aliases-install    Dry-run: show what would be added to your shell rc file"
	@echo "  make aliases-install-apply    Source shell/aliases.sh from your shell rc file"
	@echo "  make aliases-uninstall-apply  Remove the sre-toolkit block from your rc file"
	@echo ""
	@echo "HOST/SSH_USER are read from .env (see .env.example), or override on the"
	@echo "command line, e.g. make vscode-status HOST=other-host SSH_USER=someone"
	@echo ""
	@echo "The alias targets auto-detect macOS/Linux and bash/zsh; override with"
	@echo "ALIAS_SHELL=zsh or RC_FILE=~/.bashrc if needed."
	@echo ""
	@echo "Currently: HOST=$(HOST) SSH_USER=$(SSH_USER)"

vscode-status vscode-clean:
	@bash $(SCRIPT) --host $(SSH_TARGET)

vscode-clean-apply:
	@bash $(SCRIPT) --host $(SSH_TARGET) --apply --yes

aliases-status aliases-install:
	@bash $(ALIAS_SCRIPT) $(ALIAS_ARGS)

aliases-install-apply:
	@bash $(ALIAS_SCRIPT) $(ALIAS_ARGS) --apply

aliases-uninstall-apply:
	@bash $(ALIAS_SCRIPT) $(ALIAS_ARGS) --uninstall --apply
