## 1. Prerequisites
Before installing Emacs, ensure the system has the necessary build tools and dependencies.

* **Git** (for Doom)
* **Ripgrep & FD** (for fast searching)
* **CMake & Libtool** (required for `vterm` compilation)

---

## 2. Emacs Installation
We installed **Emacs 30+** via `emacs-plus` to ensure compatibility with modern features like `vterm`, `native-comp`, and `tree-sitter`.

```bash
brew tap d12frosted/emacs-plus
brew install emacs-plus@30 --with-native-comp
```

### macOS File Descriptor Limit

** I don't think this is necessary, but am unsure **

macOS GUI apps inherit a soft file descriptor limit of **256** from launchd. This is too low for Emacs + LSP (pyright, eglot) + vterm and causes `"File watching not possible, no file descriptor left"` errors. emacs-plus is compiled with `-DFD_SETSIZE=10000` but the OS must also raise the runtime limit.

**Create a LaunchDaemon** to raise the limit to 10240 (persists across reboots):

```bash
sudo tee /Library/LaunchDaemons/limit.maxfiles.plist > /dev/null << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple/DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>limit.maxfiles</string>
    <key>ProgramArguments</key>
    <array>
      <string>launchctl</string>
      <string>limit</string>
      <string>maxfiles</string>
      <string>10240</string>
      <string>524288</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
  </dict>
</plist>
EOF
sudo chown root:wheel /Library/LaunchDaemons/limit.maxfiles.plist
sudo chmod 644 /Library/LaunchDaemons/limit.maxfiles.plist
sudo launchctl load -w /Library/LaunchDaemons/limit.maxfiles.plist
```

Reboot to apply. Verify with `launchctl limit maxfiles` (should show `10240 524288`).

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

## 4. Tree-sitter Grammars

Tree-sitter provides better syntax highlighting (function calls, properties, etc.) but requires language grammars to be installed. Doom's `tree-sitter` module is enabled but grammars must be installed manually on first use.

In Emacs, run:

```
SPC ; (add-to-list 'treesit-language-source-alist '(python "https://github.com/tree-sitter/tree-sitter-python"))
SPC ; (treesit-install-language-grammar 'python)
```

After installing, reopen the Python file — it should be in `python-ts-mode` (check modeline). Other languages can be installed similarly from [tree-sitter grammars](https://github.com/tree-sitter).

---

## 5. Configuring Modules
In `~/.config/doom/init.el`, we enabled key modules:
* `:term vterm` (The high-performance terminal)
* `:ui (treemacs +lsp)` (The file sidebar)
* `:editor (evil +everywhere)` (Vim emulation)

## Interactive updates
if there's new code you want to test in your config.el file, you can select it and type `g r`
