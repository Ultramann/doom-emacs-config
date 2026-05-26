## 1. Prerequisites

Before installing Emacs, ensure the system has the necessary tools and dependencies.

* **Git** (for Doom)
* **Ripgrep & FD** (for fast searching)
* **CMake & Libtool** (required for `vterm` compilation)
* **A Nerd Font** (for icons in tab-line, treemacs, modeline — e.g. `brew install --cask font-symbols-only-nerd-font`)

---

## 2. Emacs Installation

Install **Emacs 30+** via `emacs-plus` for native-comp, vterm, and tree-sitter support.

```bash
brew tap d12frosted/emacs-plus
brew install emacs-plus@30 --with-native-comp
```

---

## 3. Doom Emacs Installation

Doom is a configuration framework that provides the `map!`, `def-doom-theme`, and module system.

1. **Clone the Doom repo:**
   `git clone --depth 1 https://github.com/doomemacs/doomemacs ~/.config/emacs`
2. **Install Doom:**
   `~/.config/emacs/bin/doom install`
3. **Add Doom to your PATH:**
   Add `~/.config/emacs/bin` to your `.zshrc` or `.bashrc`.

---

## 4. Python Setup

The Python module is configured as `(python +pyenv +lsp +tree-sitter)`.

### Pyright (LSP Server)

Install pyright in the global pyenv Python so it's available everywhere via shims:

```bash
pyenv shell $(pyenv global)
pip install pyright
```

The eglot config tells pyright which project-specific Python to use per-project, so it doesn't need to be installed per-virtualenv.

### Tree-sitter Grammar

The `+tree-sitter` flag on the python module enables `python-ts-mode`, but the grammar must be installed manually on first use:

```
SPC ; (add-to-list 'treesit-language-source-alist '(python "https://github.com/tree-sitter/tree-sitter-python"))
SPC ; (treesit-install-language-grammar 'python)
```

After installing, reopen the Python file — it should be in `python-ts-mode` (check modeline). Other languages can be installed similarly from [tree-sitter grammars](https://github.com/tree-sitter).

---

## 5. Eglot (LSP Client)

Eglot is the LSP client, enabled via `(lsp +eglot)` in init.el. Key configuration:

* **File watching is disabled** — Pyright tries to watch thousands of files. The `workspace/didChangeWatchedFiles` capability is overridden to no-op.
* **Async connection** — `eglot-sync-connect` is nil so opening files doesn't block while the server starts.
* **Xref integration** — `eglot-extend-to-xref` is enabled so `g d` into library code reuses the running server instead of prompting for a new one.
* **Library file support** — `eglot-current-server` is advised to return any running server for `.pyenv` library files, so navigation (`g d`) into installed packages works with full LSP features.
* **Per-service LSP** — `cmg/python-project-root` finds the nearest `.python-version` file via `project-find-functions`, so each service in a monorepo gets its own LSP instance.
* **Treemacs file watching disabled** — `treemacs-filewatch-mode` is turned off to avoid additional fd exhaustion.

---

## 6. Google Calendar (Top Bar)

The top bar displays the next calendar event via `read-cal.scpt`, which queries the macOS Calendar app (Google Calendar "Cary" account). Ensure:

1. macOS Calendar is configured with the Google account
2. `read-cal.scpt` is present in the config directory

---

## 7. Configuring Modules

In `~/.config/doom/init.el`, key enabled modules:
* `:term vterm` — high-performance terminal
* `:ui treemacs` — file sidebar
* `:ui workspaces` — per-project workspace isolation
* `:editor (evil +everywhere)` — vim emulation
* `:tools (lsp +eglot)` — LSP via eglot
* `:tools (magit +forge)` — git porcelain + GitHub integration
* `:lang (python +pyenv +lsp +tree-sitter)` — Python with pyenv, eglot, and tree-sitter

---

## 8. Interactive Updates

If there's new code you want to test in your config.el file, you can select it (highlight/visual mode — try `v a )` to select the sexp) and type `g r`.
