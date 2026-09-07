PLUGIN_ID := tpelicano.obsnote
PLUGINS_DIR := $(HOME)/.config/omarchy/plugins
INSTALL_PATH := $(PLUGINS_DIR)/$(PLUGIN_ID)
REPO_DIR := $(CURDIR)

.PHONY: test link unlink enable disable reload watch

test:
	@bash test/all

link:
	@mkdir -p $(PLUGINS_DIR)
	@ln -sfn $(REPO_DIR) $(INSTALL_PATH)
	@omarchy-shell shell rescanPlugins
	@echo "linked $(INSTALL_PATH) -> $(REPO_DIR)"

unlink:
	@rm -f $(INSTALL_PATH)
	@omarchy-shell shell rescanPlugins
	@echo "unlinked $(INSTALL_PATH)"

enable:
	@omarchy plugin enable $(PLUGIN_ID)

disable:
	@omarchy plugin disable $(PLUGIN_ID)

# `rescanPlugins` re-walks the plugin dirs but does not swap the code of an
# already-mounted bar widget, so a restart is the only reliable way to see a
# QML edit. It takes a second and only restarts the shell.
reload:
	@omarchy restart shell

# The shell watches the plugins dir with `inotifywait -r`, which does not
# traverse symlinks, so edits in this repo never reach it.
watch:
	@echo "watching $(REPO_DIR) -- Ctrl-C to stop"
	@while inotifywait -q -r -e close_write,create,delete,move \
		--exclude '(\.git/|node_modules/)' $(REPO_DIR) >/dev/null; do \
		omarchy restart shell >/dev/null 2>&1 && echo "shell restarted $$(date +%H:%M:%S)"; \
	done
