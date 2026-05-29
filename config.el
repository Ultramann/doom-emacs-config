;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; ——————————————————————————————————————————————————————————————————
;; Basics
;; ——————————————————————————————————————————————————————————————————

;; Must be set before nerd-icons theme loads (treemacs icon alignment)
(defvar treemacs-nerd-icons-tab " ")

(add-to-list 'custom-theme-load-path (expand-file-name "~/.config/doom/"))
(setq doom-theme 'boss)
(setq doom-font (font-spec :family "Menlo" :size 13)
      doom-font-increment 1)
(setq default-directory "~/.config/doom/")
(setq org-directory "~/org/")
(global-visual-line-mode 1)
(setq max-mini-window-height 1)
(setq eldoc-echo-area-use-multiline-p 1)

(defvar cmg/sidebar-width 90
  "The default width for all sidebar windows (Terminals, Claude, etc).")
;; Declare dynamic var for lexical-binding compatibility
(defvar vterm-shell)

;; ——————————————————————————————————————————————————————————————————
;; Core Functions
;; Utility functions used throughout the config — must be defined early.
(defun cmg/workspace-name ()
  "Return the current workspace name for terminal prefixing."
  (if (bound-and-true-p persp-mode)
      (+workspace-current-name)
    (file-name-nondirectory
     (directory-file-name (or (doom-project-root) default-directory)))))

(defun cmg/set-sidebar-window-params (win)
  "Set window parameters on WIN to protect it like treemacs."
  (set-window-parameter win 'side-drawer t)
  (set-window-parameter win 'no-delete-other-windows t))

(defun cmg/project-root ()
  "Return the current workspace's project root reliably.
Uses the workspace parameter set by +workspaces-switch-to-project-h,
falling back to doom-project-root and default-directory."
  (or (and (bound-and-true-p persp-mode)
           (persp-parameter '+workspace-project))
      (doom-project-root)
      default-directory))

(defun cmg/terminal-display-name (buf)
  "Return the display name of BUF (strip workspace prefix)."
  (let ((name (if (bufferp buf) (buffer-name buf) buf)))
    (cond ((string-match "^\\*deadgrep " name) "Search")
          ((string-match "^[^:]+:\\(.*\\)" name) (match-string 1 name))
          (t name))))

(defun cmg/terminal-buffer-name (display-name)
  "Return the full buffer name for DISPLAY-NAME in the current workspace."
  (format "%s:%s" (cmg/workspace-name) display-name))

(defun cmg/sidebar-buffer-p (buf)
  "Return non-nil if BUF is any sidebar buffer (any workspace)."
  (let ((name (buffer-name buf)))
    (or (string-match-p "^[^:]+:Term:" name)
        (string-match-p "^[^:]+:Claude$" name)
        (string-match-p "^\\*deadgrep " name))))

(defun cmg/workspace-sidebar-buffers ()
  "Return sidebar buffers belonging to the current workspace."
  (let ((prefix (concat (cmg/workspace-name) ":")))
    (cl-remove-if-not
     (lambda (buf)
       (and (buffer-live-p buf)
            (cmg/sidebar-buffer-p buf)
            (or (string-prefix-p prefix (buffer-name buf))
                (and (string-match-p "^\\*deadgrep " (buffer-name buf))
                     (with-current-buffer buf
                       (string-prefix-p (or (cmg/project-root) "") default-directory))))))
     (buffer-list))))

(defun cmg/kill-workspace-buffers ()
  "Kill all file-visiting buffers in the current workspace, then show dashboard."
  (interactive)
  (let ((bufs (cl-remove-if-not #'buffer-file-name (persp-buffer-list))))
    (mapc #'kill-buffer bufs)
    (+dashboard/open (selected-frame))
    (message "Killed %d buffer%s" (length bufs) (if (= (length bufs) 1) "" "s"))))

;; Must be defined before doom-after-init-hook (startup) because
;; the hook fires while config.el is still loading via Doom's init sequence.
(defun cmg/create-sidebar-terminal (&optional project-dir)
  "Create a new terminal buffer in a fresh sidebar split.
PROJECT-DIR overrides the terminal's working directory."
  (let* ((ws (cmg/workspace-name))
         (buf (generate-new-buffer (format "%s:Term:new" ws)))
         (win (split-window (frame-root-window) (- cmg/sidebar-width) 'right)))
    (cmg/set-sidebar-window-params win)
    (select-window win)
    (switch-to-buffer buf)
    (set-window-fringes win 15 0)
    (with-current-buffer buf
      (setq default-directory (or project-dir (cmg/project-root))))
    (vterm-mode)
    (when (bound-and-true-p persp-mode)
      (persp-add-buffer buf))
    (cmg/reindex-terminals)))

;; ——————————————————————————————————————————————————————————————————
;; Windows
;; ——————————————————————————————————————————————————————————————————

(setq display-line-numbers-width 2)
(setq display-line-numbers-type 'relative)
(setq auto-revert-interval 1)
(global-auto-revert-mode 1)
(setq initial-frame-alist '((fullscreen . fullboth) (vertical-scroll-bars . nil) (horizontal-scroll-bars . nil)))
;; Enable line numbers and hl-line for fundamental-mode (Doom only enables for prog/text modes)
(add-hook 'fundamental-mode-hook #'display-line-numbers-mode)
(add-hook 'fundamental-mode-hook #'hl-line-mode)

;; Disable hl-line in visual mode (selection highlight is enough)
(add-hook 'evil-visual-state-entry-hook (lambda () (hl-line-mode -1)))
(add-hook 'evil-visual-state-exit-hook (lambda () (hl-line-mode 1)))

;; Lock sidebar width on frame resize
(defun cmg/enforce-sidebar-width (&rest _)
  "Ensure the sidebar window stays at cmg/sidebar-width columns."
  (when-let ((win (or (cl-find-if (lambda (w) (window-parameter w 'side-drawer)) (window-list))
                      (cl-find-if (lambda (w) (cmg/sidebar-buffer-p (window-buffer w))) (window-list)))))
    (let ((delta (- cmg/sidebar-width (window-total-width win))))
      (unless (zerop delta)
        (with-selected-window win
          (window-resize win delta t))))))

(add-hook 'window-size-change-functions #'cmg/enforce-sidebar-width)
(setq default-frame-alist '((fullscreen . fullboth) (vertical-scroll-bars . nil) (horizontal-scroll-bars . nil)))

;; Shift-Enter in vertico opens file in other split
(defvar cmg/open-in-other-window nil)
(after! vertico
  (define-key vertico-map (kbd "S-<return>")
              (lambda () (interactive)
                (setq cmg/open-in-other-window t)
                (vertico-exit))))

(defadvice! +open-in-other-window-a (fn file &rest args)
  :around #'find-file
  (if cmg/open-in-other-window
      (let ((cmg/open-in-other-window nil)
            (non-sidebar-wins (cl-remove-if
                               (lambda (w)
                                 (or (window-parameter w 'side-drawer)
                                     (and (fboundp 'treemacs-get-local-buffer) (eq (window-buffer w) (treemacs-get-local-buffer)))))
                               (window-list))))
        (let* ((other-win (cl-find-if (lambda (w) (not (eq w (selected-window))))
                                      non-sidebar-wins))
               (target (or other-win
                           (split-window (car non-sidebar-wins) nil 'right))))
          (select-window target)
          (apply fn file args)))
    (apply fn file args)))

;; ——————————————————————————————————————————————————————————————————
;; Keybindings
;; ——————————————————————————————————————————————————————————————————

;; Window navigation
(map! "C-h" #'evil-window-left
      "C-j" #'evil-window-down
      "C-k" #'evil-window-up
      "C-l" #'evil-window-right
      "C-t" nil)  ; unbind workspace-new

(map! :n "g x" #'browse-url-at-point
      :n "g e" #'flycheck-next-error
      :n "g E" #'flycheck-previous-error)
(after! eglot
  (map! :map eglot-mode-map :n "g r" #'+lookup/references))

;; ——————————————————————————————————————————————————————————————————
;; Dashboard
;; ——————————————————————————————————————————————————————————————————
(defun cmg/dashboard-ascii-banner ()
  "Project header as the dashboard banner."
  (let* ((project-root (cmg/project-root))
         (project-name (file-name-nondirectory (directory-file-name project-root)))
         (git-branch (string-trim
                      (shell-command-to-string
                       (format "git -C %s rev-parse --abbrev-ref HEAD 2>/dev/null"
                               (shell-quote-argument project-root))))))
    (string-join
     (delq nil
           (list ""
                 (propertize project-name 'face '(:height 1.8 :weight bold))
                 (propertize (abbreviate-file-name project-root) 'face `(:foreground ,(doom-color 'base5)))
                 (when (and git-branch (not (string-empty-p git-branch)))
                   (propertize (format "branch: %s" git-branch) 'face `(:foreground ,(doom-color 'bright-blue))))
                 ""))
     "\n")))

(setq +dashboard-ascii-banner-fn #'cmg/dashboard-ascii-banner)
(setq fancy-splash-image "none")
(setq +dashboard-pwd-policy 'last-project)
;; Replace menu sections with our keybindings
(setq +dashboard-menu-sections
      '(("Find file"
         :icon (nerd-icons-faicon "nf-fa-file_text" :face '+dashboard-menu-title)
         :action find-file
         :key "SPC .  ")
        ("Project files"
         :icon (nerd-icons-octicon "nf-oct-briefcase" :face '+dashboard-menu-title)
         :action projectile-find-file
         :key "SPC p f")
        ("Magit status"
         :icon (nerd-icons-octicon "nf-oct-git_branch" :face '+dashboard-menu-title)
         :action magit-status
         :key "SPC g g")
        ("Open Claude"
         :icon (nerd-icons-mdicon "nf-md-brain" :face '+dashboard-menu-title)
         :action cmg/open-claude-sidebar
         :key "SPC l c")
        ("Toggle terminal"
         :icon (nerd-icons-octicon "nf-oct-terminal" :face '+dashboard-menu-title)
         :action cmg/toggle-terminal-sidebar
         :key "SPC o t")))

;; Remove footer and loaded widgets
(remove-hook '+dashboard-functions #'+dashboard-widget-loaded)
(remove-hook '+dashboard-functions #'+dashboard-widget-footer)

(defun cmg/refresh-dashboard (&optional dir)
  "Update the dashboard to reflect DIR or the current workspace's project."
  (when-let ((buf (get-buffer +dashboard-name)))
    (let ((project-dir (or dir (cmg/project-root))))
      (with-current-buffer buf
        (setq-local default-directory project-dir))
      (setq +dashboard-pwd-policy project-dir)
      ;; Set the persp parameter that +dashboard-reload reads internally
      (when (bound-and-true-p persp-mode)
        (set-persp-parameter 'last-project-root project-dir))
      (+dashboard-reload t))))

;; Hide hl-line in dashboard
(add-hook '+dashboard-mode-hook
          (lambda ()
            (face-remap-add-relative 'hl-line :background (doom-color 'bg))))

(defun cmg/project-layout (&optional dir)
  "Set up the default 3-pane layout: treemacs | dashboard | terminal.
Skips if the current workspace already has sidebar buffers."
  (interactive)
  (let ((project-dir (or dir (cmg/project-root) default-directory)))
    (unless (cmg/workspace-sidebar-buffers)
      ;; Suppress doom-switch-buffer-hook during layout setup to prevent
      ;; +dashboard-reload-maybe-h from rendering with stale data
      (let ((doom-switch-buffer-hook nil))
        ;; Undedicate all windows so delete-other-windows can clean up
        (dolist (win (window-list))
          (set-window-dedicated-p win nil))
        (delete-other-windows)
        (switch-to-buffer (doom-fallback-buffer))
        (setq default-directory project-dir)
        (cmg/create-sidebar-terminal project-dir)
        (windmove-left))
      ;; One clean reload with the correct project
      (cmg/refresh-dashboard project-dir))))

;; ——————————————————————————————————————————————————————————————————
;; Workspaces
;; ——————————————————————————————————————————————————————————————————

(after! persp-mode
  (setq +workspaces-switch-project-function #'cmg/project-layout)
  ;; Undedicate sidebar windows before killing workspace to prevent errors
  (advice-add 'persp-kill :before
              (lambda (&rest _)
                (dolist (win (window-list))
                  (when (window-parameter win 'side-drawer)
                    (set-window-dedicated-p win nil)))))
  ;; Save last workspace project on quit, restore on startup
  (setq persp-auto-save-opt 0          ; don't auto-save full workspace state
        persp-auto-resume-time -1)     ; don't auto-restore
  ;; Remove numbers from workspace tab display
  (defadvice! +workspace-tabline-no-numbers-a ()
    :override #'+workspace--tabline
    (let* ((current-name (+workspace-current-name))
           (names (+workspace-list-names)))
      (mapconcat
       #'identity
       (cl-loop for name in names
                collect
                (propertize (format " %s " name)
                            'face (if (equal current-name name)
                                      '+workspace-tab-selected-face
                                    '+workspace-tab-face)))
       " ")))
  ;; Don't try to save winner-mode ring data per workspace (too complex to serialize)
  (setq persp-not-persp-minor-modes-to-persist
        (cons 'winner-mode (bound-and-true-p persp-not-persp-minor-modes-to-persist)))
  ;; Only refresh dashboard for workspaces that already have a project set.
  ;; New workspaces get their dashboard refreshed by cmg/project-layout instead.
  (add-hook 'persp-activated-functions
            (lambda (_)
              (when (persp-parameter '+workspace-project)
                (cmg/refresh-dashboard)
                ;; Recreate terminal sidebar if workspace was restored without one
                (unless (cmg/workspace-sidebar-buffers)
                  (run-with-idle-timer 0.3 nil
                    (lambda ()
                      (when (and (persp-parameter '+workspace-project)
                                 (not (cmg/workspace-sidebar-buffers)))
                        (save-selected-window
                          (cmg/create-sidebar-terminal
                           (persp-parameter '+workspace-project)))))))
                ;; Force vterm resize after workspace switch
                (dolist (win (window-list))
                  (when (with-current-buffer (window-buffer win)
                          (derived-mode-p 'vterm-mode))
                    (with-selected-window win
                      (vterm--window-adjust-process-window-size
                       (get-buffer-process (current-buffer))
                       (list win))))))))

  ;; Filter vterm buffers from persp save (they can't be serialized)
  (setq persp-filter-save-buffers-functions
        (list (lambda (buf) (with-current-buffer buf
                              (derived-mode-p 'vterm-mode)))))
)

(defvar cmg/last-project-file
  (expand-file-name "last-project" doom-cache-dir)
  "File storing the last active project path.")

(defun cmg/save-last-project ()
  "Save the current workspace's project to disk."
  (when-let ((project (persp-parameter '+workspace-project)))
    (with-temp-file cmg/last-project-file
      (insert project))))

(add-hook 'kill-emacs-hook #'cmg/save-last-project)

;; Startup: restore workspace immediately, defer terminal until frame is sized
(defvar cmg/startup-dir nil)
(add-hook 'doom-after-init-hook
          (lambda ()
            (let* ((last-project (when (file-exists-p cmg/last-project-file)
                                   (string-trim (with-temp-buffer
                                                  (insert-file-contents cmg/last-project-file)
                                                  (buffer-string))))))
              (setq cmg/startup-dir (if (and last-project
                                             (file-directory-p last-project)
                                             (not (string= last-project "~/.config/doom/")))
                                       last-project
                                     "~/.config/doom/"))
              (setq default-directory cmg/startup-dir)
              ;; Defer rename + dashboard + terminal until persp-mode is fully initialized
              (run-with-idle-timer 0.1 nil
                (lambda ()
                  (when (bound-and-true-p persp-mode)
                    (+workspace-rename "main"
                                       (file-name-nondirectory
                                        (directory-file-name cmg/startup-dir)))
                    (set-persp-parameter '+workspace-project cmg/startup-dir))
                  (cmg/refresh-dashboard cmg/startup-dir)
                  ;; Wait for fullscreen frame before creating terminal
                  (defun cmg/startup-create-terminal (&optional _frame)
                    (when (and (not (cmg/workspace-sidebar-buffers))
                               (> (frame-width) (+ cmg/sidebar-width 40)))
                      (cmg/create-sidebar-terminal cmg/startup-dir)
                      (windmove-left)
                      (remove-hook 'window-size-change-functions #'cmg/startup-create-terminal)))
                  (if (> (frame-width) (+ cmg/sidebar-width 40))
                      (cmg/startup-create-terminal)
                    (add-hook 'window-size-change-functions #'cmg/startup-create-terminal))))))
          100)

;; ——————————————————————————————————————————————————————————————————
;; Buffers
;; Ex commands: context-aware :q/:wq/:q!/:qa/:wqa
;; ——————————————————————————————————————————————————————————————————

(evil-ex-define-cmd "q" (lambda ()
                          (interactive)
                          (cond
                           ;; Commit message: abort
                           ((bound-and-true-p with-editor-mode)
                            (with-editor-cancel nil)
                            (run-at-time "0.1 sec" nil (lambda () (message nil))))
                           ;; Treemacs: do nothing
                           ((derived-mode-p 'treemacs-mode) nil)
                           ;; Sidebar buffer: kill and switch to next sidebar tab
                           ((cmg/sidebar-buffer-p (current-buffer))
                            (let ((buf (current-buffer))
                                  (others (remove (current-buffer) (cmg/workspace-sidebar-buffers))))
                              (set-window-dedicated-p (selected-window) nil)
                              (if others
                                  (progn
                                    (switch-to-buffer (car others))
                                    (kill-buffer buf))
                                (kill-buffer buf))))
                           ;; Everything else
                           (t
                            (let ((main-wins (cmg/main-windows)))
                              (kill-current-buffer)
                              ;; If multiple main windows and no unique real buffer
                              ;; left for this window, close the split
                              (if (and (> (length main-wins) 1)
                                       (or (cmg/sidebar-buffer-p (current-buffer))
                                           (not (doom-real-buffer-p (current-buffer)))
                                           (cl-find-if (lambda (w)
                                                         (and (not (eq w (selected-window)))
                                                              (eq (window-buffer w) (current-buffer))))
                                                       main-wins)))
                                  (delete-window)
                                ;; Single window: fall back to dashboard
                                (when (or (cmg/sidebar-buffer-p (current-buffer))
                                          (not (doom-real-buffer-p (current-buffer))))
                                  (previous-buffer)
                                  (when (or (cmg/sidebar-buffer-p (current-buffer))
                                            (not (doom-real-buffer-p (current-buffer))))
                                    (switch-to-buffer (doom-fallback-buffer))))))))))
(evil-ex-define-cmd "wq" (lambda ()
                          (interactive)
                          (if (bound-and-true-p with-editor-mode)
                              (with-editor-finish nil)
                            (save-buffer)
                            (kill-current-buffer))))
(evil-ex-define-cmd "q!" (lambda ()
                           (interactive)
                           (if (bound-and-true-p with-editor-mode)
                               (with-editor-cancel nil)
                             (set-buffer-modified-p nil)
                             (kill-current-buffer))))
(evil-ex-define-cmd "Q" 'evil-quit)
(evil-ex-define-cmd "qa[ll]" (lambda ()
                               (interactive)
                               (when (bound-and-true-p with-editor-mode)
                                 (with-editor-cancel nil))
                               (evil-quit-all)))
(evil-ex-define-cmd "wqa[ll]" (lambda ()
                                (interactive)
                                (if (bound-and-true-p with-editor-mode)
                                    (with-editor-finish nil)
                                  (evil-save-and-quit))))

;; ——————————————————————————————————————————————————————————————————
;; Git
;; ——————————————————————————————————————————————————————————————————
(defun cmg/git-blame-line ()
  "Show git blame info for the current line in the minibuffer with PR link."
  (interactive)
  (let* ((line (line-number-at-pos))
         (file (buffer-file-name))
         (result (string-trim
                  (shell-command-to-string
                   (format "git blame -L %d,%d --porcelain %s 2>/dev/null"
                           line line (shell-quote-argument file))))))
    (if (string-empty-p result)
        (message "No blame info available")
      (let* ((commit (when (string-match "^\\([0-9a-f]+\\) " result) (match-string 1 result)))
             (author (when (string-match "^author \\(.*\\)$" result) (match-string 1 result)))
             (date (when (string-match "^author-time \\([0-9]+\\)" result)
                     (format-time-string "%Y-%m-%d" (seconds-to-time (string-to-number (match-string 1 result))))))
             (summary (when (string-match "^summary \\(.*\\)$" result) (match-string 1 result)))
             (pr-num (when (and summary (string-match "(#\\([0-9]+\\))" summary))
                       (match-string 1 summary)))
             (remote-url (string-trim (shell-command-to-string "git remote get-url origin 2>/dev/null")))
             (repo (when (string-match "github\\.com[:/]\\(.+?\\)\\(\\.git\\)?$" remote-url)
                     (match-string 1 remote-url)))
             (pr-url (when (and pr-num repo) (format "https://github.com/%s/pull/%s" repo pr-num)))
             (short-hash (when commit (substring commit 0 (min 8 (length commit))))))
        (message "%s  %s  %s  %s%s"
                 (propertize (or short-hash "?") 'face `(:foreground ,(doom-color 'fg)))
                 (propertize (or author "?") 'face `(:foreground ,(doom-color 'blue)))
                 (propertize (or date "?") 'face `(:foreground ,(doom-color 'yellow)))
                 (or summary "?")
                 (if pr-url
                     (format "  [%s — RET to open]"
                             (propertize (format "PR #%s" pr-num)
                                         'face `(:foreground ,(doom-color 'bright-blue))))
                   ""))
        (when pr-url
          (when (eq (read-key) ?\r)
            (browse-url pr-url)))))))

;; Remote URL helpers
(defun cmg/browse-at-remote-kill-symbolic ()
  "Copy remote URL using branch name instead of commit hash."
  (interactive)
  (let ((browse-at-remote-prefer-symbolic t))
    (call-interactively #'+vc/browse-at-remote-kill)))

(defun cmg/browse-at-remote-symbolic ()
  "Open remote URL using branch name instead of commit hash."
  (interactive)
  (let ((browse-at-remote-prefer-symbolic t))
    (call-interactively #'+vc/browse-at-remote)))

;; Magit
(after! magit
  ;; Open magit in a split — reuse existing magit window, or split
  (setq magit-display-buffer-function
        (lambda (buffer)
          (let* ((is-commit (string-match-p "COMMIT_EDITMSG" (buffer-name buffer)))
                 (existing-win (cl-find-if
                                (lambda (w)
                                  (with-current-buffer (window-buffer w)
                                    (derived-mode-p 'magit-mode)))
                                (window-list)))
                 (non-sidebar-wins (cl-remove-if
                                    (lambda (w)
                                      (or (window-parameter w 'side-drawer)
                                          (and (fboundp 'treemacs-get-local-buffer) (eq (window-buffer w) (treemacs-get-local-buffer)))))
                                    (window-list)))
                 (target-win (cond
                              ;; Commit message: use selected window so it gets focus
                              (is-commit (selected-window))
                              ;; Reuse existing magit window
                              (existing-win existing-win)
                              ;; Two+ main windows: use the other one
                              ((>= (length non-sidebar-wins) 2)
                               (cl-find-if (lambda (w) (not (eq w (selected-window))))
                                           non-sidebar-wins))
                              ;; One window: split
                              (t (split-window (car non-sidebar-wins) nil 'right)))))
            (set-window-buffer target-win buffer)
            ;; After displaying diff, refocus commit message if visible
            (let ((commit-win (cl-find-if
                               (lambda (w) (string-match-p "COMMIT_EDITMSG" (buffer-name (window-buffer w))))
                               (window-list))))
              (select-window (or commit-win target-win))))))

  ;; Refresh magit status when saving a buffer
  (add-hook 'after-save-hook #'magit-after-save-refresh-status)
  ;; Always expand these sections in magit status
  (setq magit-section-initial-visibility-alist
        '((unstaged . show)
          (staged . show)
          (unpushed . show)
          (unpulled . show)
          (recent . show)))
  ;; Don't warn about long commit summaries
  (setq git-commit-summary-max-length 100)
  (add-hook 'git-commit-setup-hook
            (lambda ()
              (setq-local display-fill-column-indicator-column (1+ git-commit-summary-max-length))
              (display-fill-column-indicator-mode 1)
))
  ;; Save all buffers and fetch when entering magit status
  (add-hook 'doom-switch-buffer-hook
            (lambda ()
              (when (derived-mode-p 'magit-status-mode)
                (save-some-buffers t)
                (magit-fetch-all-prune))))
  ;; Toggle parent file section from anywhere in a diff
  (evil-define-key* 'normal magit-diff-mode-map
    (kbd "<backtab>") (lambda () (interactive)
                        (when-let ((section (magit-current-section)))
                          (while (and section (not (magit-file-section-p section)))
                            (setq section (oref section parent)))
                          (when section
                            (goto-char (oref section start))
                            (magit-section-toggle section)))))
  ;; Open files from diff in the other window
  (evil-define-key* 'normal magit-diff-mode-map
    (kbd "RET") #'magit-diff-visit-file-other-window)
  (evil-define-key* 'normal magit-status-mode-map
    (kbd "RET") #'magit-diff-visit-file-other-window)
  ;; Swap f (Fetch->Pull) and F (Pull->Fetch) in magit-dispatch and magit-mode-map
  (define-key magit-mode-map "f" #'magit-pull)
  (define-key magit-mode-map "F" #'magit-fetch)
  (transient-replace-suffix 'magit-dispatch "f"
    '("f" "Pull" magit-pull))
  (transient-replace-suffix 'magit-dispatch "F"
    '("F" "Fetch" magit-fetch))
  ;; In pull menu: f = upstream (first), u = pushRemote
  (transient-replace-suffix 'magit-pull "p"
    '("f" magit-pull-from-upstream))
  (transient-replace-suffix 'magit-pull "u"
    '("u" "pushRemote, setting that" magit-pull-from-pushremote))
  ;; In fetch menu: f = pushRemote (instead of p)
  (transient-replace-suffix 'magit-fetch "p"
    '("f" "pushRemote, setting that" magit-fetch-from-pushremote))
  ;; Add "diff with main" to magit diff menu
  (transient-append-suffix 'magit-diff "d"
    '("m" "Diff with main" cmg/magit-diff-main)))

(defun cmg/magit-diff-main ()
  "Show diff of current branch against main (merge-base)."
  (interactive)
  (magit-diff-range (concat "main...")))


;; ——————————————————————————————————————————————————————————————————
;; Modeline
;; ——————————————————————————————————————————————————————————————————
(after! doom-modeline
  (setq doom-modeline-env-version nil)  ; hide pyenv version from major-mode segment
  ;; Hide checker segment when no checker is active
  (advice-add 'doom-modeline-update-flycheck :after
              (lambda (&optional status &rest _)
                (when (eq (or status flycheck-last-status-change) 'no-checker)
                  (setq doom-modeline--flycheck nil))))
  (doom-modeline-def-modeline 'main
    '(bar modals matches buffer-info buffer-position word-count selection-info)
    '(major-mode lsp check " "))
  ;; Match magit/vcs modeline to main style
  (doom-modeline-def-modeline 'vcs
    '(bar modals matches buffer-info buffer-position)
    '(major-mode check "  "))
  ;; Clean dashboard modeline
  (doom-modeline-def-modeline 'dashboard
    '(bar modals buffer-default-directory-simple)
    '(major-mode))
  ;; Vterm modeline: just the evil state icon, right-aligned
  (doom-modeline-def-segment vterm-evil-state
    (let* ((state (if (bound-and-true-p evil-local-mode) evil-state 'insert))
           (icon (pcase state
                   ('normal "\xf0c13")
                   ('insert "\xf0c04")
                   ('visual "\xf0c2b")
                   (_       "\xf0c04")))
           (face (if cmg/vterm-focused
                     (pcase state
                       ('normal 'doom-modeline-evil-normal-state)
                       ('insert 'doom-modeline-evil-insert-state)
                       ('visual 'doom-modeline-evil-visual-state)
                       (_       'doom-modeline-evil-insert-state))
                   `(:foreground ,(doom-color 'base5)))))
      (propertize (format " %s   " icon) 'face face)))
  (doom-modeline-def-modeline 'vterm
    '(bar)
    '(vterm-evil-state)))

;; Leader map
(map! :leader
      ;; Buffer — switch to last buffer, but stay in sidebar if in sidebar
      :desc "Switch to last buffer" "b l"
      (cmd! (if (window-parameter (selected-window) 'side-drawer)
                (cmg/sidebar-prev-tab)
              (evil-switch-to-windows-last-buffer)))

      ;; Workspace overrides
      (:prefix "TAB"
       "x" nil "`" nil
       "0" nil "1" nil "2" nil "3" nil "4" nil
       "5" nil "6" nil "7" nil "8" nil "9" nil
       :desc "Last workspace" "l" #'+workspace/other
       :desc "Load workspace" "L" #'+workspace/load)

      ;; Window overrides — remove clutter
      (:prefix "w"
       "0" nil "1" nil "2" nil "3" nil "4" nil
       "5" nil "6" nil "7" nil "8" nil "9" nil
       "c" nil
       "C-_" nil "C-b" nil "C-c" nil "C-d" nil "C-f" nil
       "C-h" nil "C-j" nil "C-k" nil "C-l" nil "C-n" nil
       "C-p" nil "C-q" nil "C-r" nil "C-s" nil "C-t" nil
       "C-u" nil "C-v" nil "C-x" nil
       "C-S-h" nil "C-S-j" nil "C-S-k" nil "C-S-l" nil
       "C-S-r" nil "C-S-s" nil "C-S-w" nil
       "C-o" nil "C-w" nil
       "C-<right>" nil "C-<left>" nil "C-<up>" nil "C-<down>" nil
       "<right>" nil "<left>" nil "<up>" nil "<down>" nil
       "C-=" nil "g" nil
       "H" nil "J" nil "K" nil "L" nil
       :desc "Move buffer left"  "h" #'cmg/move-buffer-left
       :desc "Move buffer down"  "j" #'cmg/move-buffer-down
       :desc "Move buffer up"    "k" #'cmg/move-buffer-up
       :desc "Move buffer right" "l" #'cmg/move-buffer-right
       :desc "Kill workspace buffers" "D" #'cmg/kill-workspace-buffers
       :desc "Exchange buffers"       "x" #'cmg/exchange-main-buffers)
      ;; Toggle
      :desc "Toggle Treemacs"          "t t" #'treemacs

      ;; Git
      :desc "Show hunk diff"           "g d" #'diff-hl-show-hunk
      :desc "Blame line"               "g b" #'cmg/git-blame-line
      :desc "Blame buffer"             "g B" #'magit-blame-addition
      :desc "Copy link (commit)"       "g y" #'+vc/browse-at-remote-kill
      :desc "Copy link (branch)"       "g Y" #'cmg/browse-at-remote-kill-symbolic
      :desc "Open link (commit)"       "g o" #'+vc/browse-at-remote
      :desc "Open link (branch)"       "g O" #'cmg/browse-at-remote-symbolic

      ;; Search
      :desc "Search project"           "/" (cmd! (deadgrep ""))
      (:prefix "s"
       "O" nil
       :desc "Clear highlights"  "o" #'evil-ex-nohighlight
       :desc "Look up online"    "w" #'+lookup/online
       :desc "Look up online (w/ prompt)" "W" #'+lookup/online-select)

      ;; Open
      :desc "Toggle Terminal Sidebar"  "o t" #'cmg/toggle-terminal-sidebar
      :desc "Open URL at point"        "o b" #'browse-url-at-point

      ;; LLM
      (:prefix ("l" . "llm")
       :desc "Open Claude"  "c" #'cmg/open-claude-sidebar
       :desc "Send Region"  "s" #'cmg/claude-send-region
       :desc "Fix Error"    "f" #'cmg/claude-fix-error)

      ;; Code
      :desc "LSP Reconnect"            "c R" #'eglot-reconnect

      ;; File
      :desc "Find file in project"     "f /" #'projectile-find-file

      ;; Buffer
      :desc "Log buffers"              "b L" #'cmg/switch-to-log-buffer
      :desc "Kill all buffers"         "b K" #'cmg/kill-non-sidebar-buffers
      :desc "Clone buffer"             "b c" (cmd! (switch-to-buffer-other-window (current-buffer)))
      :desc "Cone split buffer here"   "b C" (cmd!
                                              (let* ((other (cl-find-if
                                                             (lambda (w)
                                                               (and (not (eq w (selected-window)))
                                                                    (not (window-parameter w 'side-drawer))))
                                                             (window-list))))
                                                (when other
                                                  (switch-to-buffer (window-buffer other)))))

      ;; View
      (:prefix ("v" . "view")
       :desc "Font larger"   "k" #'doom/increase-font-size
       :desc "Font smaller"  "j" #'doom/decrease-font-size))

(after! which-key
  (push '(("override-state" . nil) . t) which-key-replacement-alist))

;; ——————————————————————————————————————————————————————————————————
;; Treemacs
;; ——————————————————————————————————————————————————————————————————

(defun cmg/treemacs-open-in-split ()
  "Open treemacs file at point in the other main split, or create one."
  (interactive)
  (let ((file (treemacs--prop-at-point :path)))
    (when (and file (stringp file) (file-regular-p file))
      (let* ((main-wins (cl-remove-if (lambda (w)
                                        (or (window-parameter w 'side-drawer)
                                            (eq w (treemacs-get-local-window))))
                                      (window-list)))
             (target (if (> (length main-wins) 1)
                         ;; Multiple main splits — use the one without focus
                         (or (cl-find-if-not (lambda (w) (eq w (get-mru-window))) main-wins)
                             (cadr main-wins))
                       ;; Single main window — split it side-by-side
                       (let ((win (car main-wins)))
                         (when win
                           (select-window win)
                           (split-window-right))))))
        (when target
          (select-window target)
          (find-file file))))))

(after! treemacs
  ;; Disable file watching — hits macOS fd limits and causes arrayp errors
  (treemacs-filewatch-mode -1)
  (cancel-function-timers #'treemacs--process-file-events)
  ;; Always open files in a non-sidebar window (not terminal/deadgrep)
  (defadvice! +treemacs-open-in-main-window-a (fn &rest args)
    :around #'get-mru-window
    (let ((win (apply fn args)))
      (if (and win (window-parameter win 'side-drawer))
          (cl-find-if (lambda (w)
                        (and (not (window-parameter w 'side-drawer))
                             (not (eq w (treemacs-get-local-window)))))
                      (window-list))
        win)))
  ;; Guard against treemacs falling back to $HOME when path can't be resolved (bug #1028)
  (defadvice! +treemacs-no-home-fallback-a (fn btn prompt &optional dir-only)
    :around #'treemacs--select-file-from-btn
    (let ((result (funcall fn btn prompt dir-only)))
      (if (string= (expand-file-name result) (expand-file-name "~"))
          (user-error "Cannot resolve file path for this node")
        result)))

  ;; Auto-expand tree to follow the current buffer's file, collapse others
  (treemacs-follow-mode 1)
  (setq treemacs-project-follow-cleanup t)
  ;; Disable soft wrapping in treemacs
  (add-hook 'treemacs-mode-hook (lambda () (visual-line-mode -1) (setq-local truncate-lines t)))
  (defvar-local cmg/treemacs-hl-cookie nil)
  (add-hook 'treemacs-mode-hook
            (lambda ()
              (setq cmg/treemacs-hl-cookie
                    (face-remap-add-relative 'hl-line :background (doom-color 'base4)))
              (display-line-numbers-mode -1)))
  (add-hook 'window-selection-change-functions
            (lambda (_)
              (when-let ((buf (treemacs-get-local-buffer)))
                (with-current-buffer buf
                  (when cmg/treemacs-hl-cookie
                    (face-remap-remove-relative cmg/treemacs-hl-cookie))
                  (setq cmg/treemacs-hl-cookie
                        (face-remap-add-relative
                         'hl-line :background
                         (if (eq (current-buffer) (window-buffer (selected-window)))
                             (doom-color 'base4)
                           (doom-color 'bg))))))))
  ;; Prevent all forms of q from killing treemacs
  (evil-define-key* '(normal motion) treemacs-mode-map
    "q" #'ignore
    "Q" #'ignore
    (kbd "<S-return>") #'cmg/treemacs-open-in-split)
  ;; Rebuild file icons without leading space, remove chevrons from directory icons.
  (let ((gui-icons (treemacs-theme->gui-icons treemacs--current-theme)))
    (maphash (lambda (ext icon)
               (when (and (stringp icon) (string-prefix-p " " icon))
                 (puthash ext (substring icon 1) gui-icons)))
             gui-icons))
  ;; Remove root project icon (after strip so it doesn't lose its space)
  (treemacs-create-icon :icon " " :extensions (root-open root-closed))
  (let* ((face 'treemacs-nerd-icons-file-face)
         (size (or (bound-and-true-p treemacs-nerd-icons-icon-size) 1.0))
         (sep treemacs-nerd-icons-tab)
         (open-icon (format "%s%s%s" sep (nerd-icons-sucicon "nf-custom-folder_open" :face face :height size) sep))
         (closed-icon (format "%s%s%s" sep (nerd-icons-sucicon "nf-custom-folder_oct" :face face :height size) sep)))
    (treemacs-create-icon :icon open-icon :extensions (dir-open) :fallback 'same-as-icon)
    (treemacs-create-icon :icon closed-icon :extensions (dir-closed) :fallback 'same-as-icon)
    (treemacs-create-icon :icon open-icon :extensions ("src-open" "build-open" "test-open" "bin-open" "git-open" "github-open" "public-open" "private-open" "temp-open" "tmp-open" "readme-open" "docs-open") :fallback 'same-as-icon)
    (treemacs-create-icon :icon (format "%s%s%s" sep (nerd-icons-octicon "nf-oct-code" :face face :height size) sep) :extensions ("src-closed") :fallback 'same-as-icon)
    (treemacs-create-icon :icon (format "%s%s%s" sep (nerd-icons-mdicon "nf-md-folder_cog" :face face :height size) sep) :extensions ("build-closed") :fallback 'same-as-icon)
    (treemacs-create-icon :icon (format "%s%s%s" sep (nerd-icons-mdicon "nf-md-folder_check" :face face :height size) sep) :extensions ("test-closed") :fallback 'same-as-icon)
    (treemacs-create-icon :icon (format "%s%s%s" sep (nerd-icons-mdicon "nf-md-folder_zip" :face face :height size) sep) :extensions ("bin-closed") :fallback 'same-as-icon)
    (treemacs-create-icon :icon (format "%s%s%s" sep (nerd-icons-sucicon "nf-custom-folder_git" :face face :height size) sep) :extensions ("git-closed") :fallback 'same-as-icon)
    (treemacs-create-icon :icon (format "%s%s%s" sep (nerd-icons-sucicon "nf-custom-folder_github" :face face :height size) sep) :extensions ("github-closed") :fallback 'same-as-icon)
    (treemacs-create-icon :icon (format "%s%s%s" sep (nerd-icons-mdicon "nf-md-folder_eye" :face face :height size) sep) :extensions ("public-closed") :fallback 'same-as-icon)
    (treemacs-create-icon :icon (format "%s%s%s" sep (nerd-icons-mdicon "nf-md-folder_lock" :face face :height size) sep) :extensions ("private-closed") :fallback 'same-as-icon)
    (treemacs-create-icon :icon (format "%s%s%s" sep (nerd-icons-mdicon "nf-md-folder_question" :face face :height size) sep) :extensions ("temp-closed" "tmp-closed") :fallback 'same-as-icon)
    (treemacs-create-icon :icon (format "%s%s%s" sep (nerd-icons-mdicon "nf-md-folder_file" :face face :height size) sep) :extensions ("readme-closed" "docs-closed") :fallback 'same-as-icon)
    (treemacs-create-icon :icon (format "%s%s%s" sep (nerd-icons-faicon "nf-fa-file_o" :face face :height size) sep) :extensions (fallback)))
  (setq treemacs-indentation 1
        treemacs-width 30
        treemacs-width-is-initially-locked t))

;; Sidebar/main window toggle (C-;) and buffer movement (SPC w h/j/k/l)
(map! :nvig (kbd "C-;") #'cmg/focus-sidebar)
(defvar cmg/last-main-window nil)
(add-hook 'window-selection-change-functions
          (lambda (_)
            (let ((win (selected-window)))
              (when (and (not (window-parameter win 'side-drawer))
                         (not (and (fboundp 'treemacs-get-local-window)
                                   (eq win (treemacs-get-local-window))))
                         (not (minibufferp (window-buffer win))))
                (setq cmg/last-main-window win)))))

(defun cmg/main-windows ()
  "Return list of non-sidebar, non-treemacs, non-minibuffer windows."
  (cl-remove-if
   (lambda (w)
     (or (window-parameter w 'side-drawer)
         (and (fboundp 'treemacs-get-local-window)
              (eq w (treemacs-get-local-window)))
         (minibufferp (window-buffer w))))
   (window-list)))

(defun cmg/move-buffer-to (direction)
  "Move current buffer to the window in DIRECTION.
If only one main window exists, create a split in that direction first."
  (let* ((buf (current-buffer))
         (target (windmove-find-other-window direction))
         (target-ok (and target
                         (not (window-parameter target 'side-drawer))
                         (not (and (fboundp 'treemacs-get-local-window)
                                   (eq target (treemacs-get-local-window)))))))
    (if target-ok
        (progn
          (set-window-buffer (selected-window) (other-buffer buf))
          (set-window-buffer target buf)
          (select-window target))
      ;; Only create a split if there's exactly one main window
      (when (= (length (cmg/main-windows)) 1)
        (let* ((side (pcase direction
                       ((or 'left 'right) 'right)
                       ((or 'up 'down) 'below)))
               (new-win (split-window (selected-window) nil side)))
          (set-window-buffer (selected-window) (other-buffer buf))
          (set-window-buffer new-win buf)
          (select-window new-win))))))

(defun cmg/move-buffer-left ()  (interactive) (cmg/move-buffer-to 'left))
(defun cmg/move-buffer-right () (interactive) (cmg/move-buffer-to 'right))
(defun cmg/move-buffer-up ()    (interactive) (cmg/move-buffer-to 'up))
(defun cmg/move-buffer-down ()  (interactive) (cmg/move-buffer-to 'down))

;; SPC b l: switch to last buffer in this window, skipping buffers visible elsewhere
(defadvice! cmg/switch-last-buffer-skip-visible-a (orig-fn &rest args)
  :around #'evil-switch-to-windows-last-buffer
  (let* ((visible (mapcar #'window-buffer
                          (cl-remove-if (lambda (w) (eq w (selected-window)))
                                        (window-list))))
         (prev (cl-find-if (lambda (entry)
                              (not (memq (car entry) visible)))
                            (window-prev-buffers))))
    (if prev
        (switch-to-buffer (car prev))
      (apply orig-fn args))))

(defun cmg/exchange-main-buffers ()
  "Swap buffers between the two main (non-sidebar, non-treemacs) windows."
  (interactive)
  (let* ((main-wins (cl-remove-if
                     (lambda (w)
                       (or (window-parameter w 'side-drawer)
                           (and (fboundp 'treemacs-get-local-window)
                                (eq w (treemacs-get-local-window)))
                           (minibufferp (window-buffer w))))
                     (window-list)))
         (other (cl-find-if (lambda (w) (not (eq w (selected-window)))) main-wins)))
    (if other
        (let ((buf-a (window-buffer (selected-window)))
              (buf-b (window-buffer other)))
          (set-window-buffer (selected-window) buf-b)
          (set-window-buffer other buf-a))
      (message "No other main window to exchange with"))))


(defun cmg/kill-non-sidebar-buffers ()
  "Kill all buffers except sidebar buffers, the dashboard, and the current buffer."
  (interactive)
  (let ((current (current-buffer)))
    (dolist (buf (buffer-list))
      (unless (or (eq buf current)
                  (cmg/sidebar-buffer-p buf)
                  (eq buf (doom-fallback-buffer)))
        (kill-buffer buf)))))

(defun cmg/switch-to-log-buffer ()
  "Switch to a *...*  buffer via completing-read."
  (interactive)
  (let* ((names (cl-remove-if-not
                 (lambda (name) (string-prefix-p "*" name))
                 (mapcar #'buffer-name (buffer-list))))
         (choice (completing-read "Buffer: " names nil t)))
    (switch-to-buffer choice)))

(defun cmg/focus-sidebar ()
  "Toggle between sidebar and main window."
  (interactive)
  (if (window-parameter (selected-window) 'side-drawer)
      ;; In sidebar — jump back to last main window
      (when (and cmg/last-main-window (window-live-p cmg/last-main-window))
        (select-window cmg/last-main-window))
    ;; In main — jump to sidebar
    (when-let ((win (cl-find-if (lambda (w) (window-parameter w 'side-drawer)) (window-list))))
      (select-window win))))

;; Visual line movement and remappings
(map! :nm "j" #'evil-next-visual-line)
(map! :nm "k" #'evil-previous-visual-line)
(map! :nm "U" #'undo-fu-only-redo)
(map! :n "g b" #'xref-go-back)

;; ——————————————————————————————————————————————————————————————————
;; Python
;; ——————————————————————————————————————————————————————————————————
(after! flycheck
  (setq flycheck-checkers (delq 'python-ruff flycheck-checkers)))

;; Use nearest .python-version as project root so each service in a monorepo
;; gets its own LSP instance with the correct virtualenv
(defun cmg/python-project-root (dir)
  "Find the nearest directory containing .python-version."
  (when-let ((root (locate-dominating-file dir ".python-version")))
    (cons 'transient root)))

(after! project
  (add-to-list 'project-find-functions #'cmg/python-project-root))

;; Don't auto-visit TAGS files — project has a directory named TAGS
(after! projectile
  (advice-add 'projectile-visit-project-tags-table :override #'ignore))


;; Pre-load eglot during idle time after startup
(add-hook 'emacs-startup-hook
          (lambda () (run-with-idle-timer 0.5 nil (lambda () (require 'eglot nil t)))))

(after! eglot
  (setq eglot-sync-connect nil
        eglot-extend-to-xref t)
  (add-to-list 'eglot-server-programs
               '(python-mode . ("pyright-langserver" "--stdio")))
  ;; Tell pyright which Python to use via pyenv (only when no .python-version exists)
  (defun cmg/eglot-python-config (_server)
    (if (locate-dominating-file default-directory ".python-version")
        (list)
      (let ((python-path (string-trim (shell-command-to-string "pyenv which python 2>/dev/null"))))
        (if (string-empty-p python-path) (list)
          (list :python (list :pythonPath python-path))))))
  (setq-default eglot-workspace-configuration #'cmg/eglot-python-config)
  ;; Filter out hint-level diagnostics (severity 4) — pyright sends these
  ;; for unused variables etc. but the CLI doesn't report them
  (cl-defmethod eglot-handle-notification
    (server (_method (eql textDocument/publishDiagnostics))
            &rest params &key uri diagnostics version &allow-other-keys)
    (let ((filtered (cl-remove-if (lambda (d) (= (plist-get d :severity) 4)) diagnostics)))
      (cl-call-next-method server _method
                           :uri uri :version version :diagnostics filtered)))
  ;; Disable LSP file watching
  (cl-defmethod eglot-register-capability
    (_server (_method (eql workspace/didChangeWatchedFiles)) &rest _args)
    "Ignore file watch requests from the LSP server."
    nil))

;; For library files (.pyenv), return any running Python eglot server
;; so eglot activates managed-mode via after-change-major-mode-hook
;; instead of trying to start a new server.
(defadvice! +eglot-reuse-server-for-libs-a (fn)
  :around #'eglot-current-server
  (or (funcall fn)
      (when (and buffer-file-name
                 (string-match-p "/\\.pyenv/.*\\.py$" buffer-file-name))
        (catch 'found
          (maphash (lambda (_proj servers)
                     (dolist (s servers)
                       (when (process-live-p (jsonrpc--process s))
                         (throw 'found s))))
                   eglot--servers-by-project)
          nil))))

;; ——————————————————————————————————————————————————————————————————
;; Claude
;; ——————————————————————————————————————————————————————————————————

(defun cmg/open-claude-sidebar ()
  "Launch Claude in the sidebar drawer with absolute width control."
  (interactive)
  (let* ((buf-name (cmg/terminal-buffer-name "Claude"))
         (buf (get-buffer-create buf-name))
         (width cmg/sidebar-width)
         (needs-init (not (with-current-buffer buf (derived-mode-p 'vterm-mode)))))
    (with-current-buffer buf
      (setq default-directory (cmg/project-root)))
    ;; Display in sidebar first so vterm gets correct dimensions
    (let ((win (or (cl-find-if (lambda (w) (window-parameter w 'side-drawer)) (window-list))
                   (cl-find-if (lambda (w) (cmg/sidebar-buffer-p (window-buffer w))) (window-list)))))
      (if (and win (window-live-p win))
          (select-window win)
        (setq win (split-window (frame-root-window) (- width) 'right))
        (cmg/set-sidebar-window-params win))
      (select-window win)
      (set-window-dedicated-p win nil)
      (switch-to-buffer buf))
    ;; Set fringes before vterm-mode so it reads correct dimensions
    (set-window-fringes (selected-window) 15 0)
    ;; Init vterm with claude as the shell so it launches directly and
    ;; exiting claude kills the process/buffer
    (when needs-init
      (let ((vterm-shell "claude"))
        (vterm-mode)))
    (when (bound-and-true-p persp-mode)
      (persp-add-buffer buf))
    (cmg/reindex-terminals)))

(defun cmg/diff-file-and-lines (beg end)
  "In a magit diff buffer, return (FILE START-LINE END-LINE) for the source file."
  (save-excursion
    (goto-char beg)
    (let ((file (magit-file-at-point))
          (hunk-start nil))
      (when file
        ;; Find the hunk header above point
        (when (re-search-backward "^@@ -[0-9,]+ \\+\\([0-9]+\\)" nil t)
          (setq hunk-start (string-to-number (match-string 1)))
          ;; Count lines from hunk header to selection, skipping removed lines
          (let ((line-offset 0)
                (hunk-header-pos (point)))
            (forward-line 1)
            (while (< (point) beg)
              (unless (looking-at-p "^-") ; skip removed lines
                (setq line-offset (1+ line-offset)))
              (forward-line 1))
            (let* ((start-line (+ hunk-start line-offset))
                   ;; Count selected lines, skipping removed lines
                   (selected-lines 0))
              (goto-char beg)
              (while (<= (point) end)
                (unless (looking-at-p "^-")
                  (setq selected-lines (1+ selected-lines)))
                (forward-line 1))
              (list file start-line (+ start-line (max 0 (1- selected-lines)))))))))))

(defun cmg/claude-send-region (beg end)
  "Send a file reference (@filepath:lines) for the selected region to Claude and switch to it."
  (interactive "r")
  (let* ((in-diff (derived-mode-p 'magit-diff-mode 'diff-mode 'magit-status-mode))
         (diff-info (when in-diff (cmg/diff-file-and-lines beg end)))
         (project-root (or (projectile-project-root) default-directory))
         (rel-file (cond
                    (diff-info (car diff-info))
                    ((buffer-file-name) (file-relative-name (buffer-file-name) project-root))
                    (t (buffer-name))))
         (start-line (if diff-info (nth 1 diff-info) (line-number-at-pos beg)))
         (end-line (if diff-info (nth 2 diff-info) (line-number-at-pos end)))
         (ref (if (= start-line end-line)
                  (format "@%s:%d" rel-file start-line)
                (format "@%s:%d-%d" rel-file start-line end-line)))
         (buf (get-buffer (cmg/terminal-buffer-name "Claude"))))
    (if buf
        (progn
          (with-current-buffer buf
            (vterm-send-string (concat ref " ")))
          (let ((win (get-buffer-window buf)))
            (if win
                (select-window win)
              (cmg/open-claude-sidebar))))
      (message "Claude not found! Run 'SPC l c' first."))))


(defun cmg/claude-fix-error ()
  "Grab the Flycheck error at point and ask Claude to fix it."
  (interactive)
  (let ((errs (flycheck-overlay-errors-at (point))))
    (if errs
        (let ((msg (flycheck-error-message (car errs))))
          (cmg/claude-send-region (point) (point)) ; Just to trigger focus
          (with-current-buffer (cmg/terminal-buffer-name "Claude")
            (vterm-send-string (format "I'm getting this error: '%s'. How do I fix it?" msg))
            (vterm-send-return)))
      (message "No Flycheck error found here!"))))


;; ——————————————————————————————————————————————————————————————————
;; Sidebar
;; ——————————————————————————————————————————————————————————————————

;; Hide sidebar buffers from buffer switch list (SPC b b, etc.)
(add-to-list 'doom-unreal-buffer-functions #'cmg/sidebar-buffer-p)
(defadvice! +hide-sidebar-from-consult-a (fn &rest args)
  :around #'consult--buffer-query
  (cl-remove-if (lambda (item)
                  (cmg/sidebar-buffer-p
                   (if (stringp item) (get-buffer item) item)))
                (apply fn args)))

;; Minor mode with shared keybindings for all sidebar buffers
(define-minor-mode cmg/sidebar-mode
  "Minor mode for sidebar buffers (terminals, search, etc.)."
  :keymap (make-sparse-keymap))

(evil-define-key* '(normal insert visual) cmg/sidebar-mode-map
  (kbd "C-c") (lambda () (interactive) (vterm-send-key "c" nil nil t))
  (kbd "C-t") #'cmg/open-new-sidebar-terminal
  ;; override Doom's insert-state C-n/C-p (corfu)
  (kbd "C-n") #'cmg/sidebar-next-tab
  (kbd "C-p") #'cmg/sidebar-prev-tab
  (kbd "C-h") #'evil-window-left
  (kbd "C-l") #'evil-window-right
  [M-left]  (lambda () (interactive) (vterm-send-key "b" nil t))
  [M-right] (lambda () (interactive) (vterm-send-key "f" nil t)))

(evil-define-key* '(normal) cmg/sidebar-mode-map
  (kbd "[f") #'cmg/vterm-prev-file-ref
  (kbd "]f") #'cmg/vterm-next-file-ref)

;; Make the dashboard buffer unkillable
(add-hook 'kill-buffer-query-functions
          (lambda () (not (eq (current-buffer) (doom-fallback-buffer)))))

;; Prevent sidebar buffers from appearing in non-sidebar windows
(set-frame-parameter nil 'buffer-predicate
                     (lambda (buf)
                       (if (window-parameter (selected-window) 'side-drawer)
                           t
                         (not (cmg/sidebar-buffer-p buf)))))
(add-hook 'after-make-frame-functions
          (lambda (frame)
            (set-frame-parameter frame 'buffer-predicate
                                 (lambda (buf)
                                   (if (window-parameter (selected-window) 'side-drawer)
                                       t
                                     (not (cmg/sidebar-buffer-p buf)))))))

;; Force sidebar buffers to only display in sidebar windows
(defun cmg/display-in-sidebar (buf alist)
  "Display BUF in the sidebar window, never in the main area."
  (let ((win (cl-find-if (lambda (w) (window-parameter w 'side-drawer))
                         (window-list))))
    (when win
      (window--display-buffer buf win 'reuse alist)
      win)))
(add-to-list 'display-buffer-alist
             '((lambda (buf _action)
                 (cmg/sidebar-buffer-p (if (stringp buf) (get-buffer buf) buf)))
               (cmg/display-in-sidebar)))

;; Mark sidebar windows as dedicated to prevent non-sidebar buffers opening there
(defun cmg/maybe-dedicate-sidebar-window ()
  "Set sidebar window as dedicated if showing a sidebar buffer."
  (dolist (win (window-list))
    (when (and (window-parameter win 'side-drawer)
               (cmg/sidebar-buffer-p (window-buffer win)))
      (set-window-dedicated-p win t))))
(add-hook 'window-buffer-change-functions (lambda (_) (cmg/maybe-dedicate-sidebar-window)))

;; ——————————————————————————————————————————————————————————————————
;; Deadgrep
;; ——————————————————————————————————————————————————————————————————
(after! doom-modeline
  (doom-modeline-def-segment deadgrep-hints
    (concat
     (propertize " /" 'face `(:foreground ,(doom-color 'fg) :weight bold))
     (propertize " search  " 'face `(:foreground ,(doom-color 'base7)))
     (propertize "t" 'face `(:foreground ,(doom-color 'fg) :weight bold))
     (propertize " type  " 'face `(:foreground ,(doom-color 'base7)))
     (propertize "c" 'face `(:foreground ,(doom-color 'fg) :weight bold))
     (propertize " case  " 'face `(:foreground ,(doom-color 'base7)))
     (propertize "f" 'face `(:foreground ,(doom-color 'fg) :weight bold))
     (propertize " files" 'face `(:foreground ,(doom-color 'base7)))))

  (doom-modeline-def-modeline 'deadgrep
    '(bar deadgrep-hints)
    '()))

(after! deadgrep
  (setq deadgrep-display-buffer-function
        (lambda (buf)
          (let ((win (or (cl-find-if (lambda (w) (window-parameter w 'side-drawer))
                                     (window-list))
                         (split-window (frame-root-window) (- cmg/sidebar-width) 'right))))
            (cmg/set-sidebar-window-params win)
            (set-window-dedicated-p win nil)
            (select-window win)
            (switch-to-buffer buf)
            (set-window-dedicated-p win t))))

  ;; Never prompt about deadgrep processes on exit
  (advice-add 'deadgrep--start :after
              (lambda (&rest _)
                (when-let ((proc (get-buffer-process (current-buffer))))
                  (set-process-query-on-exit-flag proc nil))))

  (add-hook 'deadgrep-mode-hook
            (lambda ()
              (cmg/sidebar-mode 1)
              ;; Don't prompt when killing deadgrep buffers
              (add-hook 'kill-buffer-query-functions
                        (lambda ()
                          (when-let ((proc (get-buffer-process (current-buffer))))
                            (set-process-query-on-exit-flag proc nil))
                          t)
                        nil t)
              (setq tab-line-format '(:eval (cmg/get-terminal-tabs)))
              (setq header-line-format " ")
              (doom-modeline-set-modeline 'deadgrep)
              (face-remap-add-relative 'header-line
                                       :background (doom-color 'bg)
                                       :box nil :overline nil :underline nil
                                       :height 0.3)
              (face-remap-add-relative 'tab-line :background (doom-color 'bg))))

  (add-hook 'deadgrep-mode-hook (lambda () (evil-snipe-local-mode -1)))
  (evil-define-key* 'normal deadgrep-mode-map
    "q" #'ignore
    "/" #'deadgrep-search-term
    "c" #'deadgrep-cycle-search-case
    "t" #'deadgrep-cycle-search-type
    "f" (cmd! (let* ((current (when (eq (car-safe deadgrep--file-type) 'glob)
                                (cdr deadgrep--file-type)))
                     (input (read-from-minibuffer
                             "Globs (*.py, !*.{json,lock}, !etl/, space-separated): "
                             current)))
                (if (string-empty-p input)
                    (setq deadgrep--file-type 'all)
                  (setq deadgrep--file-type (cons 'glob input)))
                (deadgrep-restart))))

  ;; Support multiple space-separated globs
  (defadvice! +deadgrep-multi-glob-a (orig-fn &rest args)
    :around #'deadgrep--arguments
    (let ((result (apply orig-fn args)))
      (when (and (eq (car-safe deadgrep--file-type) 'glob)
                 (string-match-p " " (cdr deadgrep--file-type)))
        (setq result (cl-remove-if (lambda (a) (string-prefix-p "--glob=" a)) result))
        (dolist (glob (split-string (cdr deadgrep--file-type)))
          (push (format "--glob=%s" glob) result)))
      result))

  (defadvice! +deadgrep-open-in-main-a (fn open-fn)
    :around #'deadgrep--visit-result
    (let ((search-dir default-directory))
      (funcall fn
               (lambda (file-name)
                 (let ((win (cl-find-if (lambda (w)
                                          (not (window-parameter w 'side-drawer)))
                                        (window-list))))
                   (when win (select-window win))
                   (let ((default-directory search-dir))
                     (find-file file-name))))))))

;; ——————————————————————————————————————————————————————————————————
;; Terminal
;; ——————————————————————————————————————————————————————————————————

(setq vterm-shell "/bin/bash")
(setq vterm-kill-buffer-on-exit t)

(defun cmg/open-new-sidebar-terminal ()
  "Add a terminal to the existing sidebar, or create one if none exists."
  (interactive)
  (let* ((ws (cmg/workspace-name))
         (buf (generate-new-buffer (format "%s:Term:new" ws)))
         (win (or (cl-find-if (lambda (w) (window-parameter w 'side-drawer)) (window-list))
                  (cl-find-if (lambda (w) (cmg/sidebar-buffer-p (window-buffer w))) (window-list)))))
    (with-current-buffer buf
      (setq default-directory (cmg/project-root)))
    (if (and win (window-live-p win))
        (progn
          (select-window win)
          (set-window-dedicated-p win nil)
          (switch-to-buffer buf)
          (set-window-fringes (selected-window) 15 0)
          (vterm-mode)
          (when (bound-and-true-p persp-mode)
            (persp-add-buffer buf))
          (cmg/reindex-terminals))
      ;; No sidebar exists — create fresh
      (kill-buffer buf)
      (cmg/create-sidebar-terminal))))

(defun cmg/toggle-terminal-sidebar ()
  "Toggle the terminal sidebar, scoped to current workspace."
  (interactive)
  (let ((sidebar-window (cl-find-if (lambda (w)
                                     (cmg/sidebar-buffer-p (window-buffer w)))
                                   (window-list))))
    (if sidebar-window
        (delete-window sidebar-window)
      (let ((existing-term (car (cmg/workspace-sidebar-buffers))))
        (if existing-term
            (let* ((width cmg/sidebar-width)
                   (win (split-window (frame-root-window) (- width) 'right)))
              (cmg/set-sidebar-window-params win)
              (select-window win)
              (switch-to-buffer existing-term))
          (cmg/open-new-sidebar-terminal))))))


;; File path navigation in terminal buffers
(defvar cmg/file-path-regexp
  "\\(?:^\\|[[:space:]\"'(]\\)\\(\\(?:\\./\\|/\\|[a-zA-Z_][a-zA-Z0-9_.-]*/\\)[a-zA-Z0-9_./-]+\\.[a-zA-Z0-9]+\\(?::[0-9]+\\)?\\)"
  "Regexp matching file paths like ./foo/bar.py, path/to/file.py:123, /abs/path.py")

(defun cmg/vterm-prev-file-ref ()
  "Jump to the previous file path reference in the terminal buffer."
  (interactive)
  (unless vterm-copy-mode (vterm-copy-mode 1))
  (if (re-search-backward cmg/file-path-regexp nil t)
      (goto-char (match-beginning 1))
    (message "No more file references")))

(defun cmg/vterm-next-file-ref ()
  "Jump to the next file path reference in the terminal buffer."
  (interactive)
  (unless vterm-copy-mode (vterm-copy-mode 1))
  (forward-char 1)
  (if (re-search-forward cmg/file-path-regexp nil t)
      (goto-char (match-beginning 1))
    (backward-char 1)
    (message "No more file references")))

(defun cmg/vterm-open-file-at-point ()
  "Open the file path at point in the main window."
  (interactive)
  (let* ((text (thing-at-point 'filename t))
         (parts (when text (split-string text ":")))
         (file (car parts))
         (line (when (cadr parts) (string-to-number (cadr parts))))
         (project-root (or (projectile-project-root) default-directory))
         (full-path (when file
                      (if (file-name-absolute-p file) file
                        (expand-file-name file project-root)))))
    (if (and full-path (file-exists-p full-path))
        (let ((win (cl-find-if (lambda (w) (not (window-parameter w 'side-drawer)))
                               (window-list))))
          (when win
            (select-window win)
            (find-file full-path)
            (when line (goto-char (point-min)) (forward-line (1- line)))))
      (message "File not found: %s" (or file "no path at point")))))

(defun cmg/vterm-sidebar-cleanup-h ()
  "Handle window management when a sidebar terminal is killed."
  (when (and (derived-mode-p 'vterm-mode)
             (cmg/sidebar-buffer-p (current-buffer)))
    (let ((win (get-buffer-window (current-buffer)))
          (ws-name (cmg/workspace-name)))
      (when win
        ;; Schedule cleanup after buffer is actually dead
        (run-at-time "0.05 sec" nil
                     (lambda ()
                       (let* ((prefix (concat ws-name ":"))
                              (remaining (cl-remove-if-not
                                          (lambda (b)
                                            (and (buffer-live-p b)
                                                 (string-prefix-p prefix (buffer-name b))
                                                 (cmg/sidebar-buffer-p b)))
                                          (buffer-list))))
                         (if (null remaining)
                             (when (window-live-p win)
                               (delete-window win))
                           (when (window-live-p win)
                             (set-window-dedicated-p win nil)
                             (set-window-buffer win (car remaining))))))))))
  t)

(add-hook 'kill-buffer-query-functions #'cmg/vterm-sidebar-cleanup-h)

;; Clean up vterm copies — remove fake newlines from terminal wrapping

(defun cmg/vterm-clean-kill-ring ()
  "Strip vterm fake (soft-wrap) newlines from the latest kill-ring entry.
Real newlines are preserved. If every line starts with 2+ spaces, dedent by 2."
  (when kill-ring
    (let* ((text (car kill-ring))
           (result (with-temp-buffer
                     (insert text)
                     (goto-char (point-min))
                     (while (search-forward "\n" nil t)
                       (when (get-text-property (1- (point)) 'vterm-line-wrap)
                         (delete-char -1)))
                     ;; Dedent by 2 if first line starts with 2 spaces
                     (goto-char (point-min))
                     (when (looking-at "  ")
                       (while (not (eobp))
                         (when (looking-at "  ")
                           (delete-char 2))
                         (forward-line 1)))
                     (buffer-string))))
      (setcar kill-ring result))))

;; Also clean up on Cmd-c in vterm
(after! vterm
  ;; Remove Doom's hook that hides the modeline in vterm
  (remove-hook 'vterm-mode-hook #'mode-line-invisible-mode)
  (define-key vterm-mode-map (kbd "s-c")
              (lambda () (interactive)
                (call-interactively #'kill-ring-save)
                (cmg/vterm-clean-kill-ring)))
  (define-key vterm-copy-mode-map (kbd "y")
              (lambda () (interactive)
                (call-interactively #'evil-yank)
                (cmg/vterm-clean-kill-ring))))

(map! :leader :g "C-t" nil) ;; Kill the workspace-new global binding

(defun cmg/sidebar-next-tab ()
  "Switch to the next sidebar buffer in order."
  (interactive)
  (let* ((all-terms (cl-sort (cmg/workspace-sidebar-buffers)
                             #'string-lessp :key #'buffer-name))
         (current (current-buffer))
         (pos (cl-position current all-terms))
         ;; Find next index, wrap around to 0 if at the end
         (next-pos (if (and pos (< (1+ pos) (length all-terms)))
                       (1+ pos)
                     0))
         (next-buf (nth next-pos all-terms))
         (win (selected-window)))
    (when next-buf
      (set-window-dedicated-p win nil)
      (switch-to-buffer next-buf)
      (set-window-dedicated-p win t))))

(defun cmg/sidebar-prev-tab ()
  "Switch to the previous sidebar buffer in order."
  (interactive)
  (let* ((all-terms (cl-sort (cmg/workspace-sidebar-buffers)
                             #'string-lessp :key #'buffer-name))
         (current (current-buffer))
         (pos (cl-position current all-terms))
         ;; Find prev index, wrap around to the end if at the start
         (prev-pos (if (and pos (> pos 0))
                       (1- pos)
                     (1- (length all-terms))))
         (prev-buf (nth prev-pos all-terms))
         (win (selected-window)))
    (when prev-buf
      (set-window-dedicated-p win nil)
      (switch-to-buffer prev-buf)
      (set-window-dedicated-p win t))))

(defun cmg/reindex-terminals ()
  "Rename generic terminals in the current workspace sequentially."
  (interactive)
  (let* ((ws (cmg/workspace-name))
         (prefix (concat ws ":"))
         (term-prefix (concat prefix "Term:"))
         ;; Only this workspace's vterm buffers
         (ws-vterm-buffers (cl-remove-if-not
                            (lambda (buf)
                              (and (buffer-live-p buf)
                                   (with-current-buffer buf (eq major-mode 'vterm-mode))
                                   (string-prefix-p prefix (buffer-name buf))))
                            (buffer-list)))
         (special-terms (cl-remove-if (lambda (b) (string-prefix-p term-prefix (buffer-name b)))
                                      ws-vterm-buffers))
         (generic-terms (cl-sort
                         (cl-remove-if-not (lambda (b) (string-prefix-p term-prefix (buffer-name b)))
                                           ws-vterm-buffers)
                         #'string-lessp :key #'buffer-name))
         (counter 1))
    ;; Clean up special buffer suffixes
    (dolist (buf special-terms)
      (with-current-buffer buf
        (rename-buffer (buffer-name) t)))
    ;; Temp names to avoid collisions
    (let ((i 0))
      (dolist (buf generic-terms)
        (with-current-buffer buf
          (rename-buffer (format " %s-term-tmp-%d" ws (cl-incf i)) t))))
    ;; Final sequential names
    (dolist (buf generic-terms)
      (with-current-buffer buf
        (rename-buffer (format "%s:Term:%d" ws counter))
        (setq counter (1+ counter))))))

(after! vterm
  ;; 1. THE EXCEPTIONS
  ;; These keys are "stolen" from the terminal so Emacs/Doom can use them.
  ;; We MUST include C-t, C-n, C-p, C-h, and C-l here.
  (setq vterm-keymap-exceptions
        '("C-t" "C-n" "C-p" "C-h" "C-l" "C-u" "C-x" "M-x"))

  ;; Sidebar keybindings handled by cmg/sidebar-mode

  ;; Normal mode (copy-mode) overrides
  (evil-define-key* 'normal vterm-copy-mode-map
    [escape] (lambda () (interactive) (vterm-copy-mode -1) (vterm-send-key "<escape>"))
    (kbd "[f") #'cmg/vterm-prev-file-ref
    (kbd "]f") #'cmg/vterm-next-file-ref
    (kbd "gf") #'cmg/vterm-open-file-at-point)

  ;; Shift-Enter sends Option-Enter (newline in Claude Code)
  (map! :map vterm-mode-map
        :ni "S-<return>" (lambda () (interactive) (vterm-send-key "\C-m" nil t)))

  ;; M-left/M-right word navigation handled by cmg/sidebar-mode

  ;; 3. THE SHELL SIGNALS (Raw Passthrough)
  ;; We do NOT put these in exceptions because we want vterm to
  ;; use its internal functions to send them to the shell process.
  (define-key vterm-mode-map (kbd "C-c") #'vterm-send-C-c)
  (define-key vterm-mode-map (kbd "C-g") (lambda () (interactive) (vterm-send-key "<escape>")))
  (define-key vterm-mode-map (kbd "C-d") #'vterm-send-C-d)
  (define-key vterm-mode-map (kbd "C-z") #'vterm-send-C-z)

  ;; Normal mode = copy mode (navigate text), insert mode = terminal input
  (add-hook 'vterm-mode-hook
            (lambda ()
              (add-hook 'evil-normal-state-entry-hook
                        (lambda () (when (derived-mode-p 'vterm-mode)
                                     (vterm-copy-mode 1)))
                        nil t)
              (add-hook 'evil-insert-state-entry-hook
                        (lambda () (when (derived-mode-p 'vterm-mode)
                                     (vterm-copy-mode -1)))
                        nil t)))

  ;; When leaving vterm: exit copy-mode so output flows
  ;; When entering vterm: switch to insert mode
  (add-hook 'window-selection-change-functions
            (lambda (_)
              ;; Unfreeze non-selected vterm windows
              (dolist (win (window-list))
                (with-current-buffer (window-buffer win)
                  (when (and (derived-mode-p 'vterm-mode)
                             vterm-copy-mode
                             (not (eq win (selected-window))))
                    (vterm-copy-mode -1))))
              ;; Enter insert mode when arriving at a vterm
              (when (derived-mode-p 'vterm-mode)
                (evil-insert-state)))))

(defun cmg/get-terminal-tabs ()
  "Return a propertized string of all sidebar buffers styled as tabs."
  (let* ((all-terminals (cmg/workspace-sidebar-buffers))
         ;; Sort by name so Claude comes first, then Term:1, Term:2, etc.
         (sorted-terms (cl-sort all-terminals #'string-lessp :key #'buffer-name)))
    (concat
     " "
     (mapconcat
      (lambda (buf)
        (let* ((display-name (cmg/terminal-display-name buf))
               (is-active (eq buf (current-buffer)))
               (bg-color (doom-color 'bg-alt))
               (fg-color (if is-active (doom-color 'fg) (doom-color 'base5)))
               (weight (if is-active 'bold 'normal)))
          (propertize (format "  %s  " display-name)
                      'face `(:background ,bg-color :foreground ,fg-color :weight ,weight)
                      'help-echo "Click to switch to this terminal"
                      'local-map (let ((map (make-sparse-keymap)))
                                   (define-key map [tab-line mouse-1]
                                     (lambda () (interactive) (switch-to-buffer buf)))
                                   map))))
      sorted-terms " "))))

(add-hook 'vterm-mode-hook
          (lambda ()
            (cmg/sidebar-mode 1)
            ;; Use :eval so it updates every time you switch buffers or create new ones
            (setq tab-line-format '(:eval (cmg/get-terminal-tabs)))
            ;; Thin spacer between tab-line and terminal content
            (setq header-line-format " ")
            (face-remap-add-relative 'header-line
                                     :background (doom-color 'bg)
                                     :box nil
                                     :overline nil
                                     :underline nil
                                     :height 0.3)
            (face-remap-add-relative 'tab-line :background (doom-color 'bg))

            ;; Make hl-line invisible in terminals
            (face-remap-add-relative 'hl-line :background (doom-color 'bg))

            ;; Fix characters that cause line height oscillation in vterm.
            ;; If more characters need remapping, revisit by setting doom-symbol-font
            ;; to a monospace font instead of patching individual glyphs.
            (let ((dt (make-display-table)))
              (aset dt 160 [32])       ; non-breaking space → space
              (aset dt 9210 [?●])      ; ⏺ → ● (emoji font fallback causes taller line height)
              (setq-local buffer-display-table dt))

            (display-line-numbers-mode -1)
            (doom-modeline-set-modeline 'vterm)
            (set-window-fringes (selected-window) 15 0)
            (set-process-query-on-exit-flag (get-buffer-process (current-buffer)) nil)

            ;; Hide cursor when vterm window is not selected
            (setq-local cursor-in-non-selected-windows nil)
            ;; Hide Emacs cursor in Claude buffers in insert mode only —
            ;; TUI renders its own cursor. Show cursor in normal/visual for navigation.
            (when (string-match-p ":Claude$" (buffer-name))
              (setq-local evil-insert-state-cursor '(nil nil))
              (setq-local cursor-type nil))
))

;; Track which vterm buffer is focused for tab-line rendering
;; (selected-window is unreliable during redisplay — Emacs temporarily selects the drawn window)
(defvar-local cmg/vterm-focused nil "Whether this vterm buffer's window is focused.")

(defun cmg/update-vterm-focus ()
  "Update focus tracking and force tab-line redraw in all vterm windows."
  (let ((focused-buf (window-buffer (selected-window))))
    (dolist (win (window-list))
      (with-current-buffer (window-buffer win)
        (when (derived-mode-p 'vterm-mode)
          (setq cmg/vterm-focused (eq (current-buffer) focused-buf))
          (force-mode-line-update))))))
(add-hook 'window-selection-change-functions (lambda (_) (cmg/update-vterm-focus)))
(add-hook 'evil-normal-state-entry-hook #'cmg/update-vterm-focus)
(add-hook 'evil-insert-state-entry-hook #'cmg/update-vterm-focus)
(add-hook 'evil-visual-state-entry-hook #'cmg/update-vterm-focus)
(add-hook 'doom-switch-buffer-hook #'cmg/update-vterm-focus)

;; Allow opening files from vterm via `open <file>`
(defun cmg/vterm-find-file (file)
  "Open FILE in the main (non-sidebar) window."
  (let ((win (cl-find-if (lambda (w)
                           (not (window-parameter w 'side-drawer)))
                         (window-list))))
    (when win (select-window win))
    (find-file file)))
(after! vterm
  (add-to-list 'vterm-eval-cmds '("find-file" cmg/vterm-find-file)))
;; Undedicate window before vterm kills the buffer on exit
(after! vterm
  (add-to-list 'vterm-exit-functions
               (lambda (buf _event)
                 (when-let ((win (and (buffer-live-p buf)
                                      (get-buffer-window buf))))
                   (set-window-dedicated-p win nil)))))
(add-hook 'vterm-exit-hook #'cmg/reindex-terminals)
;; Also catch if the buffer is killed manually without the process exiting
(add-hook 'kill-buffer-hook (lambda ()
                              (when (cmg/sidebar-buffer-p (current-buffer))
                                (let* ((win (get-buffer-window (current-buffer)))
                                       (remaining (cl-remove (current-buffer)
                                                             (cmg/workspace-sidebar-buffers))))
                                  (when win
                                    (if remaining
                                        (set-window-buffer win (car remaining))
                                      (run-at-time "0.01 sec" nil
                                                   (lambda () (when (window-live-p win)
                                                                (delete-window win)))))))
                                (run-at-time "0.1 sec" nil #'cmg/reindex-terminals))))

;; ——————————————————————————————————————————————————————————————————
;; Top Bar
;; ——————————————————————————————————————————————————————————————————
(defvar cmg/hw-memsize nil)
(defvar cmg/hw-ncpu nil)
(defvar cmg/net-prev-in 0)
(defvar cmg/net-prev-out 0)
(defvar cmg/net-prev-time nil)
(defvar cmg/tab-bar-stats-cache "")
(defvar cmg/next-event-cache "")
(defvar cmg/tab-bar-branch-cache "")

(defun cmg/format-bytes-rate (bps)
  "Format BPS as human-readable rate (max 4 chars)."
  (cond
   ((>= bps (* 1024 1024 1024)) (format "%.0fG" (/ bps (* 1024.0 1024 1024))))
   ((>= bps (* 1024 1024)) (format "%.0fM" (/ bps (* 1024.0 1024))))
   ((>= bps 1024) (format "%.0fK" (/ bps 1024.0)))
   (t (format "%dB" (round bps)))))

(defun cmg/pad-stat (str width)
  "Right-pad STR to WIDTH and apply base7 face."
  (propertize (truncate-string-to-width (concat str (make-string width ?\s)) width)
              'face `(:foreground ,(doom-color 'base7))))

(defun cmg/parse-applescript (raw)
  "Parse AppleScript calendar output into a display string."
  (if (string-empty-p raw)
      ""
    (let ((sections (split-string raw "|||" t))
          current-text next-text)
      (dolist (s sections)
        (let ((fields (split-string s "|:|")))
          (cond
           ((and (string= (car fields) "CURRENT") (>= (length fields) 4))
            (setq current-text
                  (propertize (format "Current ▸ %s (%s-%s)"
                                      (nth 1 fields) (nth 2 fields) (nth 3 fields))
                              'face `(:foreground ,(doom-color 'fg) :weight bold))))
           ((and (string= (car fields) "NEXT") (>= (length fields) 5))
            (let ((mins (string-to-number (nth 1 fields))))
              (setq next-text
                    (propertize (format "Next ▸ %s (%s-%s)"
                                        (nth 2 fields) (nth 3 fields) (nth 4 fields))
                                'face (if (<= mins 5)
                                          `(:foreground ,(doom-color 'yellow))
                                        `(:foreground ,(doom-color 'base7))))))))))
      (cond
       ((and current-text next-text) (concat "Calendar — " current-text "  —  " next-text))
       (current-text (concat "Calendar — " current-text))
       (next-text (concat "Calendar — " next-text))
       (t "")))))

(defun cmg/parse-icalbuddy (raw)
  "Parse icalBuddy output into a display string."
  (if (string-empty-p raw)
      ""
    (let* ((now (float-time))
           (lines (split-string raw "\n" t))
           current-text next-text)
      (while lines
        (let ((time-line (string-trim (pop lines)))
              (title-line (if lines (string-trim (pop lines)) "")))
          (when (string-match "\\([0-9]+:[0-9]+\\) - \\([0-9]+:[0-9]+\\)" time-line)
            (let* ((start-str (match-string 1 time-line))
                   (end-str (match-string 2 time-line))
                   (start-h (string-to-number (car (split-string start-str ":"))))
                   (start-m (string-to-number (cadr (split-string start-str ":"))))
                   (end-h (string-to-number (car (split-string end-str ":"))))
                   (end-m (string-to-number (cadr (split-string end-str ":"))))
                   (now-decoded (decode-time))
                   (start-time (float-time (encode-time 0 start-m start-h
                                                        (nth 3 now-decoded)
                                                        (nth 4 now-decoded)
                                                        (nth 5 now-decoded))))
                   (end-time (float-time (encode-time 0 end-m end-h
                                                      (nth 3 now-decoded)
                                                      (nth 4 now-decoded)
                                                      (nth 5 now-decoded))))
                   (fmt-start (cmg/fmt-time start-h start-m))
                   (fmt-end (cmg/fmt-time end-h end-m)))
              (cond
               ((and (<= start-time now) (>= end-time now) (not current-text))
                (setq current-text (format "Current ▸ %s (%s-%s)" title-line fmt-start fmt-end)))
               ((and (> start-time now) (not next-text))
                (setq next-text (format "Next ▸ %s (%s-%s)" title-line fmt-start fmt-end))))))))
      (cond
       ((and current-text next-text) (format "Calendar — %s  —  %s" current-text next-text))
       (current-text (format "Calendar — %s" current-text))
       (next-text (format "Calendar — %s" next-text))
       (t "")))))

(defun cmg/fmt-time (h m)
  "Format H:M as 12-hour time string."
  (let ((ampm (if (>= h 12) "PM" "AM"))
        (h12 (cond ((> h 12) (- h 12)) ((= h 0) 12) (t h))))
    (if (= m 0)
        (format "%d%s" h12 ampm)
      (format "%d:%02d%s" h12 m ampm))))

(defun cmg/update-next-event ()
  "Fetch today's calendar events asynchronously via AppleScript."
  (let ((buf (get-buffer-create " *next-event*")))
    (with-current-buffer buf (erase-buffer))
    (set-process-query-on-exit-flag
     (make-process
      :name "next-event"
      :buffer buf
      :command (list "osascript" (expand-file-name "read-cal.scpt" doom-private-dir))
      :sentinel
      (lambda (proc _event)
        (when (eq (process-status proc) 'exit)
          (let ((raw (string-trim (with-current-buffer (process-buffer proc)
                                    (buffer-string)))))
            (setq cmg/next-event-cache
                  (if (and (not (string-empty-p raw))
                           (or (string-prefix-p "CURRENT" raw)
                               (string-prefix-p "NEXT" raw)))
                      (cmg/parse-applescript raw)
                    ""))))))
     nil)))


(defun cmg/update-tab-bar-branch ()
  "Update the cached git branch for the tab bar."
  (let ((root (or (projectile-project-root) default-directory)))
    (setq cmg/tab-bar-branch-cache
          (let ((branch (string-trim
                         (shell-command-to-string
                          (format "git -C %s rev-parse --abbrev-ref HEAD 2>/dev/null"
                                  (shell-quote-argument root))))))
            (if (string-empty-p branch) ""
              (let* ((color (doom-color 'base7))
                     (face (list :foreground color))
                     (icon (nerd-icons-devicon "nf-dev-git_branch" :face face))
                     (max-len 40)
                     (display-branch (if (> (length branch) max-len)
                                         (concat (substring branch 0 (- max-len 3)) "...")
                                       branch)))
                (concat "  " icon
                        (propertize (concat " " display-branch)
                                    'face face
                                    'help-echo branch))))))))

(defun cmg/update-tab-bar-stats ()
  "Refresh the cached system stats string."
  (let ((default-directory (if (file-directory-p default-directory) default-directory "~/")))
  (cmg/update-tab-bar-branch)
  (unless cmg/hw-memsize
    (setq cmg/hw-memsize
          (string-to-number (string-trim (shell-command-to-string "sysctl -n hw.memsize"))))
    (setq cmg/hw-ncpu
          (string-to-number (string-trim (shell-command-to-string "sysctl -n hw.ncpu")))))
  (let* (;; CPU: sum per-process usage, divide by core count
         (cpu-raw (string-to-number
                   (string-trim
                    (shell-command-to-string "ps -A -o %cpu= | awk '{s+=$1} END {printf \"%.1f\", s}'"))))
         (cpu-pct (/ cpu-raw (max 1 cmg/hw-ncpu)))
         ;; Memory: App Memory + Wired + Compressed (matches Activity Monitor)
         (vm-out (shell-command-to-string "vm_stat"))
         (page-size (if (string-match "page size of \\([0-9]+\\)" vm-out)
                        (string-to-number (match-string 1 vm-out)) 16384))
         (active (if (string-match "Pages active:[ \t]+\\([0-9]+\\)\\." vm-out)
                     (string-to-number (match-string 1 vm-out)) 0))
         (wired (if (string-match "Pages wired down:[ \t]+\\([0-9]+\\)\\." vm-out)
                    (string-to-number (match-string 1 vm-out)) 0))
         (compressed (if (string-match "Pages occupied by compressor:[ \t]+\\([0-9]+\\)\\." vm-out)
                         (string-to-number (match-string 1 vm-out)) 0))
         (mem-used (* (float (+ active wired compressed)) page-size))
         (mem-pct (* 100.0 (/ mem-used cmg/hw-memsize)))
         ;; Network
         (net-out (shell-command-to-string "netstat -bI en0 | awk 'NR==2 {print $7, $10}'"))
         (net-parts (split-string (string-trim net-out)))
         (now (float-time))
         (in-bytes (string-to-number (or (nth 0 net-parts) "0")))
         (out-bytes (string-to-number (or (nth 1 net-parts) "0")))
         (dt (if cmg/net-prev-time (max 0.1 (- now cmg/net-prev-time)) 1.0))
         (in-rate (if (> cmg/net-prev-in 0) (/ (max 0 (- in-bytes cmg/net-prev-in)) dt) 0))
         (out-rate (if (> cmg/net-prev-out 0) (/ (max 0 (- out-bytes cmg/net-prev-out)) dt) 0)))
    (setq cmg/net-prev-in in-bytes
          cmg/net-prev-out out-bytes
          cmg/net-prev-time now)
    (let* ((batt-raw (string-trim (shell-command-to-string
                      "pmset -g batt | grep -o '[0-9]*%'")))
           (batt-str (if (string-empty-p batt-raw) "" (format "BAT %s" batt-raw))))
      (setq cmg/tab-bar-stats-cache
            (concat (unless (string-empty-p batt-str)
                      (cmg/pad-stat batt-str 10))
                    (cmg/pad-stat (format "CPU %.0f%%" cpu-pct) 10)
                    (cmg/pad-stat (format "MEM %.0f%%" mem-pct) 10)
                    (cmg/pad-stat (format "NET ↓%-4s ↑%-4s"
                                          (cmg/format-bytes-rate in-rate)
                                          (cmg/format-bytes-rate out-rate)) 20)
                    (propertize (concat (format-time-string "%m-%d") " " (string-trim (format-time-string "%l:%M %p")) "  ")
                                'face `(:foreground ,(doom-color 'base7)))))))
  (force-mode-line-update t)))

(defun cmg/tab-bar-stats ()
  "Return system stats for tab bar display."
  (let* ((unsaved-bufs (cl-remove-if-not
                        (lambda (b) (and (buffer-file-name b) (buffer-modified-p b)))
                        (buffer-list)))
          (unsaved (length unsaved-bufs))
          (unsaved-item (when (> unsaved 0)
                          (let* ((names (mapconcat
                                         (lambda (b) (file-name-nondirectory (buffer-file-name b)))
                                         unsaved-bufs ", "))
                                 (label (concat "  " (propertize (format " %d " unsaved)
                                                                  'face (list :foreground (doom-color 'yellow)
                                                                              :box (list :line-width -1 :color (doom-color 'yellow)))
))))
                            (list (list 'unsaved 'menu-item label 'ignore
                                      :help (format "Unsaved buffers: %s" names)))))))
  `((pad menu-item ,(propertize " " 'face `(:box (:line-width (2 . 2) :color ,(doom-color 'bg-alt)))) ignore)
    ,@unsaved-item
    (branch menu-item ,cmg/tab-bar-branch-cache ignore)
    (cal-spacer menu-item
                ,(propertize " " 'display `(space :align-to ,(+ 2 (or (bound-and-true-p treemacs-width) 30))))
                ignore)
    (event menu-item
           ,(if (string-empty-p cmg/next-event-cache) ""
              cmg/next-event-cache)
           ignore)
    (spacer menu-item
            ,(propertize " " 'display '(space :align-to (- right 66)))
            ignore)
    (stats menu-item ,cmg/tab-bar-stats-cache ignore))))

(add-hook 'doom-after-init-hook
          (lambda ()
            (setq tab-bar-show t)
            (setq tab-bar-format '(cmg/tab-bar-stats))
            (tab-bar-mode 1)
            (run-with-timer 1 1 #'cmg/update-tab-bar-stats)
            (run-with-timer 0.5 60 #'cmg/update-next-event))
          100)
