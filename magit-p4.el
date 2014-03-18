;;; magit-p4.el --- git-p4 plug-in for Magit

;; Copyright (C) 2014 Damian T. Dobroczyński
;;
;; Author: Damian T. Dobroczy\\'nski <qoocku@gmail.com>
;; Keywords: vc tools
;; Package: magit-p4

;; Magit-p4 is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; Magit-p4 is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
;; License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Magit-p4.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This plug-in provides git-p4 functionality as a separate component
;; of Magit.

;;; Code:

(require 'magit)

(eval-when-compile
  (require 'cl-lib)
  (require 'find-lisp)
  (require 'p4))

(declare-function find-lisp-find-files-internal 'find-lisp)

;;; Options

(defgroup magit-p4 nil
  "Git-p4 support for Magit."
  :group 'magit-extensions)

;;; Commands

;;;###autoload
(defun magit-p4-clone (depot-path &optional target-dir)
  "Clone given depoth path.

   The first argument is P4 depot path to clone. The second optional argument
   is directory which will hold the Git repository."
  (interactive
   (append (list (p4-read-arg-string "Depot path: " "//" 'filespec))
           (if (and (not (search "destination=" magit-custom-options))
                  current-prefix-arg)
               (read-directory-name "Target directory: ")
             nil)))
  (magit-run-git-async "p4" "clone" (cons depot-path magit-custom-options)))

;;;###autoload
(defun magit-p4-sync (&optional depot-path)
  "Synchronize with default and/or given depoth path.

   The optional argument is P4 depot path which will be synchronised with.
   If not present, git-p4 will try to synchronize with default depot path which
   has been cloned to before."
  (interactive
   (when current-prefix-arg
     (list (p4-read-arg-string "With (another) depot path: " "//" 'filespec))))
  (magit-run-git-async "p4" "sync"
                       (cond (depot-path
                              (cons depot-path magit-custom-options))
                             (t magit-custom-options))))

;;;###autoload
(defun magit-p4-rebase ()
  "Runs git-p4 rebase."
  (interactive)
  (magit-run-git-async "p4" "rebase" magit-custom-options))

(defun magit-p4/server-edit-end-keys ()
  "Private function.
   Binds C-c C-c keys to finish editing submit log
   when using emacsclient tools."
  (when (current-local-map)
    (use-local-map (copy-keymap (current-local-map))))
  (when server-buffer-clients
    (local-set-key (kbd "C-c C-c") 'server-edit)))

(defun magit-p4/get-config (var)
  (let* ((env-var (format "P4%s" (upcase var)))
         (value (getenv env-var))
         (result (if value
                     (list 'env env-var value)
                   (list 'git env-var (magit-get (format "git-p4.%s" var))))))
    result))

(defun magit-p4/submit (git-dir &optional sync-mode)
  "Runs git-p4 submit within given GIT directory.
   If SYNC-MODE is true all Magit command will be called in
   synchronised (editor blocking) mode."
  ;; git-p4 invokes editor using values of P4EDITOR or GIT_EDITOR variables
  ;; here we temporarily set P4EDITOR (it has precedence in git-p4) to "emacsclient"
  (let ((magit-fun (if sync-mode 'magit-run-git 'magit-run-git-async)) ; sync/async magit functin
        (to-restore (list (list "P4EDITOR" (getenv "P4EDITOR"))))) ; list of env. vars to set & restore
    ;; get P4 variables (from git-p4.* config or environment)
    (dolist (var '("user" "password" "port" "host" "client"))
      (let* ((value-spec (magit-p4/get-config var))
             (var-val (pcase value-spec
                        (`(,_ ,_ nil) nil)
                        (`(env ,var ,val) (progn (append to-restore var)
                                                 (list var val)))
                        (`(git ,var ,val) (list var val)))))
        ;; set environment P4 variables for to-be-spawned submit process
        ;; which starts emacsclient
        (when var-val
          (setenv (first var-val) (second var-val)))))
    (setenv "P4EDITOR" "emacsclient")
    (funcall magit-fun "p4" "submit"
             (if (and git-dir (not (search "--git-dir=" magit-custom-options)))
                 (append magit-custom-options (format "--git-dir=%s" git-dir))
               magit-custom-options))
    (dolist (pair to-restore)
      (pcase pair
        (`(,var ,val) (setenv var val))))))

;;;###autoload
(defun magit-p4-submit ()
  "Runs git-p4 submit."
  (interactive)
  (magit-p4/submit nil))

(defun magit-p4/squeeze-commits (since)
  "Squeezes all commits since SINCE to current HEAD into one."
  (magit-run-git git-dir-arg "reset" "--soft" since)
  (magit-run-git git-dir-arg "commit" "-m\"$(git log --format=%B --reverse HEAD..HEAD@{1})\""))

;;;###autoload
(defun magit-p4-submit-as-one ()
  "Runs git-p4 submit treating all recent commits as one.
   The Git repo will be rewritten - all commits since the last
   registered in P4 will be squeezed (squashed) into one."
  (interactive)
  (let ((last-submit (magit-get-string "show" "-s" "--format=%H" "p4/master")))
    (when last-submit
      (magit-p4/squeeze-commits last-submit)
      (magit-p4/submit))))

;;; Utilities

(defun magit-p4-enabled ()
  t)

;;; Keymaps

(easy-menu-define magit-p4-extension-menu
  nil
  "Git P4 extension menu"
  '("Git P4"
    :visible magit-p4-mode
    ["Clone" magit-p4-clone (magit-p4-enabled)]
    ["Sync" magit-p4-sync (magit-p4-enabled)]
    ["Rebase" magit-p4-rebase (magit-p4-enabled)]
    ["Submit" magit-p4-submit (magit-p4-enabled)]))

(easy-menu-add-item 'magit-mode-menu
                    '("Extensions")
                    magit-p4-extension-menu)

;;; Add Perfoce group and its keys
(let ((p4-groups '((p4 (actions (("c" "Clone" magit-key-mode-popup-p4-clone)
                                 ("r" "Rebase" magit-key-mode-popup-p4-rebase)
                                 ("S" "Submit" magit-key-mode-popup-p4-submit)
                                 ("s" "Sync" magit-key-mode-popup-p4-sync))))
                   (p4-sync  (actions (("s" "Sync" magit-p4-sync)))
                             (switches (("-db" "Detect branches" "--detect-branches")
                                        ("-s" "Silent" "--silent")
                                        ("-ib" "import Labels" "--import-labels")
                                        ("-il" "import Local" "--import-local")
                                        ("-p" "Keep path" "--keep-path")
                                        ("-c" "Client spec" "--use-client-spec")))
                             (arguments (("-b" "Branch" "--branch" magit-read-rev)
                                         ("=c" "Changes files" "--changesfile=" (lambda () (read-file-name "Changes file: ")))
                                         ("=m" "Max changes" "--max-changes=" read-from-minibuffer))))
                   (p4-clone (actions (("c" "Clone" magit-p4-clone)))
                             (switches (("-b" "Bare clone" "--bare")))
                             (arguments (("=d" "Destination directory" "--destination=" read-directory-name)
                                         ("=/" "Exclude depot path" "-/ "
                                          (lambda (prompt) (p4-read-arg-string prompt "//" 'filespec))))))
                   (p4-submit (actions (("1" "Submit as one changelist" magit-p4-submit-as-one)
                                        ("s" "Submit as separate change lists (standard)" magit-p4-submit)))
                              (switches (("-M" "Detect renames" "-M")
                                         ("-u" "Preserve user" "--preserve-user")
                                         ("-l" "Export labels" "--export-labels")
                                         ("-n" "Dry run" "--dry-run")
                                         ("-p" "Prepare P4 only" "--prepare-p4-only")))
                              (arguments (("=o" "Upstream location to submit" "--origin="
                                           magit-read-rev-with-default)
                                          ("=c" "Conflict resolution (ask|skip|quit)" "--conflict="
                                           (lambda (prompt)
                                             (first (completing-read-multiple prompt '("ask" "skip" "quit")))))
                                          ("=b" "Sync with branch after" "--branch=" magit-read-rev)))
                              (p4-rebase (actions (("r" "Rebase" magit-p4-rebase)))
                                         (switches (("-l" "Import labels" "--import-labels"))))))))
  (dolist (group-def p4-groups)
    (let* ((group (first group-def))
           (keys (cdr group-def))
           (switches (append '(("-g" "GIT_DIR" "--git-dir")
                               ("-v" "Verbose" "--verbose"))
                             (second (assoc 'switches keys))))
           (arguments (second (assoc 'arguments keys)))
           (actions (second (assoc 'actions keys))))
      ;; (re-)create the group
      (magit-key-mode-add-group group)
      ;; magit so far is buggy here 'cause "arguments" group is not created by default
      (let ((options (assoc group magit-key-mode-groups)))
        (setcdr (last options) (list (list 'arguments)))
        (dolist (opt (list (list 'switch switches)
                           (list 'argument arguments)
                           (list 'action actions)))
          (pcase opt
            (`(,sym ,args)
             (let ((fun (intern (format "magit-key-mode-insert-%s" sym))))
               (dolist (arg args)
                 (apply fun (cons group arg))))))))
      ;; generate and bind the menu popup function
      (magit-key-mode-generate group)))
  (magit-key-mode-insert-action 'dispatch "4" "git-p4" 'magit-key-mode-popup-p4))

;; add keyboard hook to finish log edition with C-c C-c
(add-hook 'server-switch-hook 'magit-p4/server-edit-end-keys)

(defun magit-p4/insert-job (&optional job jobs-entry-title)
  "Inserts job reference in a buffer.
  The insertion assumes that it should be 'Jobs:' entry in the buffer.
  If not - it inserts such at the current point of the buffer. Then it asks (if
  applied interactively) for a job id using `p4` completion function.
  Finally it inserts the id under `Jobs:` entry."
  (interactive
   (list (p4-read-arg-string "Job: " "" 'job)
         (if current-prefix-arg
             (read-from-minibuffer "Jobs section title: ")
           "Jobs")))
  (when job
    (let* ((jobs-section-regexp (format "^%s:" jobs-entry-title))
           (jobs-entry (save-excursion (re-search-backward jobs-section-regexp nil t)))
           (jobs-entry (if jobs-entry jobs-entry (re-search-forward jobs-section-regexp nil t))))
      (if (not jobs-entry)
          ;; it inserts "Jobs:" entry in the CURRENT point!
          (insert (format "\n%s:\n\t" jobs-entry-title))
        ;; move to past the end of `Jobs:` entry
        (progn
          (goto-char jobs-entry)
          (end-of-line)
          (insert "\n\t")))
      (insert job))))

(defvar magit-p4-mode-map
  "Minor P4 mode key map.
   So far used in submit log edit buufer."
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-x j") 'magit-p4/insert-job)
    map))

;;; Mode

;;;###autoload
(define-minor-mode magit-p4-mode
  "P4 support for Magit"
  :lighter " P4"
  :require 'magit-p4
  :keymap 'magit-p4-mode-map
  (or (derived-mode-p 'magit-mode)
     (user-error "This mode only makes sense with magit"))
  (when (called-interactively-p 'any)
    (magit-refresh)))

(provide 'magit-p4)
;; Local Variables:
;; indent-tabs-mode: nil
;; End:
;;; magit-p4.el ends here
