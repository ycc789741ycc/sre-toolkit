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

INFRA_SCRIPT := scripts/install-infra-tools.sh

.PHONY: help vscode-status vscode-clean vscode-clean-apply \
        aliases-status aliases-install aliases-install-apply aliases-uninstall-apply \
        infra-status infra-install infra-install-apply

help:
	@echo "sre-toolkit targets:"
	@echo "  make vscode-status      Report vscode-server versions/size (read-only)"
	@echo "  make vscode-clean       Same as above: dry-run, shows what would be removed"
	@echo "  make vscode-clean-apply Kill stale process trees and delete old version installs"
	@echo ""
	@echo "  make aliases-status     Show detected platform/shell/rc file and install state"
	@echo "  make aliases-install    Dry-run: show what would be added to your shell rc file"
	@echo "  make aliases-install-apply    Source shell/aliases.sh from your shell rc file"
	@echo "                                (~/.bashrc for bash), and point the login file"
	@echo "                                at it so every bash session gets the aliases"
	@echo "  make aliases-uninstall-apply  Remove the sre-toolkit block from your rc file"
	@echo ""
	@echo "  make infra-status       Show which infra tools are installed (macOS via Homebrew)"
	@echo "  make infra-install      Dry-run: show which infra tools would be installed"
	@echo "  make infra-install-apply    Install missing infra tools (skips ones already installed),"
	@echo "                              then wire up their shell completions via the alias installer"
	@echo ""
	@echo "HOST/SSH_USER are read from .env (see .env.example), or override on the"
	@echo "command line, e.g. make vscode-status HOST=other-host SSH_USER=someone"
	@echo ""
	@echo "The alias targets auto-detect macOS/Linux and bash/zsh; override with"
	@echo "ALIAS_SHELL=zsh or RC_FILE=~/.bashrc if needed. For bash the block goes in"
	@echo "~/.bashrc, and the login file (~/.bash_profile or ~/.profile) is made to"
	@echo "source it unless it already does."
	@echo ""
	@echo "The infra targets auto-detect macOS/Linux; Linux is a placeholder for now."
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

infra-status infra-install:
	@bash $(INFRA_SCRIPT)

infra-install-apply:
	-@bash $(INFRA_SCRIPT) --apply
	@echo ""
	@echo "wiring up shell completions for the installed CLI tools..."
	@bash $(ALIAS_SCRIPT) $(ALIAS_ARGS) --apply
