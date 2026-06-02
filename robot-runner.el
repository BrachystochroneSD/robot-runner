;;; robot-runner.el --- Run Robot Framework tests from Emacs  -*- lexical-binding: t; -*-

;; Copyright (C) 2023  Samuel Dawant

;; Author: Samuel Dawant <samueld@mailo.com>
;; Keywords: languages, tools, testing
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (transient "0.4.0"))
;; URL: https://github.com/BrachystochroneSD/robot-runner
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; robot-runner provides a transient-based interface to run Robot Framework
;; tests directly from Emacs, displaying output in a dedicated comint buffer.
;;
;; Features:
;;  - Run test at point, current suite, current directory, or selected files
;;  - Tag-based filtering with completion (--include / --exclude)
;;  - Supports robotcode, robot, or any custom command
;;  - Clickable output links (log.html, report.html, output.xml)
;;  - Launches from Git root automatically
;;
;; Basic setup:
;;
;;   (require 'robot-runner)
;;
;; With robot-mode:
;;
;;   (with-eval-after-load 'robot-mode
;;     (define-key robot-mode-map (kbd "C-c C-r") #'robot-runner-dispatch))
;;
;; With robotcode (recommended LSP backend):
;;
;;   (setq robot-runner-command '("robotcode" "robot"))
;;
;; See README.md for full configuration examples.

;;; Code:

(require 'transient)

(defgroup robot-runner nil
  "Run Robot Framework tests from Emacs."
  :group 'tools
  :prefix "robot-runner-")

(defcustom robot-runner-command '("robot")
  "Command to run Robot Framework.

Should be a list of strings.  The first element is the executable,
the rest are prepended arguments.

Examples:
  \\='(\"robot\")
  \\='(\"robotcode\" \"robot\")
  \\='(\"python\" \"-m\" \"robot\")"
  :type '(choice
          (string :tag "Command")
          (repeat :tag "List of strings" string))
  :group 'robot-runner
  :safe (lambda (v) (or (stringp v) (and (listp v) (cl-every #'stringp v)))))

(defcustom robot-runner-extra-args '()
  "Extra arguments always passed to the robot command."
  :type '(repeat string)
  :group 'robot-runner
  :safe 'listp)

(defcustom robot-runner-open-report-after-run nil
  "If non-nil, open report.html automatically after a test run."
  :type 'boolean
  :group 'robot-runner
  :safe 'booleanp)

(defcustom robot-runner-use-git-root t
  "If non-nil, run tests from the Git repository root.
Falls back to `default-directory' when not inside a Git repo."
  :type 'boolean
  :group 'robot-runner
  :safe 'booleanp)

;;; Internal helpers

(defun robot-runner--get-rootdir ()
  "Return the directory from which to run tests.
If `robot-runner-use-git-root' is non-nil and a .git directory is found,
return that root.  Otherwise return `default-directory'."
  (let ((git-dir (locate-dominating-file default-directory ".git")))
    (if (and robot-runner-use-git-root git-dir)
        (expand-file-name git-dir)
      default-directory)))

(defun robot-runner--robotize-string (string)
  "Convert a file path fragment STRING to a Robot Framework suite name.
Underscores become spaces, slashes become dots, each word is capitalized."
  (let* ((no-underscores (replace-regexp-in-string "_" " " string))
         (no-slashes     (replace-regexp-in-string "/" "." no-underscores)))
    (mapconcat #'capitalize (split-string no-slashes) " ")))

(defun robot-runner--current-suite-name (file)
  "Return the dotted Robot suite name for FILE, relative to the project root."
  (let ((rel (string-replace
              (file-name-directory (directory-file-name (robot-runner--get-rootdir)))
              ""
              (replace-regexp-in-string "\\.robot$" "" file))))
    (robot-runner--robotize-string rel)))

(defun robot-runner--current-test-name ()
  "Return the name of the test case at point."
  (save-excursion
    (re-search-backward "^\\([[:alnum:]]+.*\\)$" nil t)
    (string-trim (match-string 1))))

(defun robot-runner--get-robot-files ()
  "Return a list of all .robot files under the project root."
  (directory-files-recursively (robot-runner--get-rootdir) ".+\\.robot" t))

(defun robot-runner--get-version ()
  "Return the Robot Framework version as a version list."
  (let ((output (shell-command-to-string "robot --version")))
    (string-match "Robot Framework *\\([0-9.]+\\) .*" output)
    (version-to-list (match-string 1 output))))

(defun robot-runner--make-clickable-links ()
  "Turn output file paths in the current buffer into clickable buttons."
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward
            "\\(Output\\|Log\\|Report\\): +\\(https?:.*\\|\\(.*\\.html\\|.*\\.xml\\)\\)"
            nil t)
      (let ((link (match-string 2)))
        (make-button (match-beginning 2) (match-end 2)
                     'action (lambda (_button) (robot-runner--open-link link)))))))

(defun robot-runner--open-link (link)
  "Open LINK with an appropriate viewer."
  (message "Opening %s..." link)
  (cond
   ((string-match "http.*"   link) (browse-url link))
   ((string-match ".*\\.html" link) (browse-url-of-file link))
   ((string-match ".*\\.xml"  link) (find-file-other-window link))))

(defun robot-runner--sentinel (process event)
  "Sentinel for the robot PROCESS.  Handles EVENT on completion."
  (unless (string-match "hangup: 1\n" event)
    (with-current-buffer (process-buffer process)
      (let ((inhibit-read-only t))
        (internal-default-process-sentinel process event)
        (robot-runner--make-clickable-links)
        (when robot-runner-open-report-after-run
          (insert "\nOpening report.html...")
          (robot-runner--open-link "report.html"))))))

;;; Completion readers

(defun robot-runner--read-file (prompt init history)
  "Read an existing file with PROMPT, initial input INIT and HISTORY."
  (read-file-name prompt (robot-runner--get-rootdir) nil t init))

(defun robot-runner--read-directory (prompt init history)
  "Read a directory with PROMPT, initial input INIT and HISTORY."
  (read-directory-name prompt (robot-runner--get-rootdir) nil nil init))

(defun robot-runner--read-output-file (prompt init history)
  "Read an existing output file with PROMPT, initial input INIT and HISTORY."
  (read-file-name prompt (robot-runner--get-rootdir) nil t init nil))

(defun robot-runner--get-all-tags ()
  "Collect all tags declared in .robot files under the project root."
  (let ((tags '()))
    (dolist (file (robot-runner--get-robot-files))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (re-search-forward "\\[Tags\\][ \t]*\\(.*\\)" nil t)
          (setq tags (append tags (split-string (match-string 1) "  +"))))))
    (delete-dups tags)))

(defun robot-runner--read-tag (prompt init history)
  "Read a tag expression with completion from known project tags."
  (completing-read prompt (robot-runner--get-all-tags) nil nil init history))

(defun robot-runner--read-files ()
  "Interactively select one or more .robot files from the project."
  (completing-read-multiple
   "Launch file(s): "
   (mapcar (lambda (f) (cons f f)) (robot-runner--get-robot-files))))

;;; Core launcher

(defun robot-runner--run (args)
  "Launch robot with ARGS (list of strings) in a comint buffer."
  (save-buffer)
  (setq args (append robot-runner-extra-args args))
  (when (not (version-list-< (robot-runner--get-version) '(7 1)))
    (setq args (append '("--consolelinks" "off") args)))
  (let* ((dir     (robot-runner--get-rootdir))
         (exe     (if (listp robot-runner-command)
                      (car robot-runner-command)
                    robot-runner-command))
         (prefix  (if (listp robot-runner-command)
                      (cdr robot-runner-command)
                    nil))
         (inhibit-read-only t))
    (with-current-buffer (get-buffer-create "*robot-runner*")
      (unless (derived-mode-p 'comint-mode)
        (comint-mode)
        (read-only-mode)
        (buffer-disable-undo))
      (erase-buffer)
      (insert (format "robot-runner: %s %s\n\n" exe (mapconcat #'identity args " ")))
      (let ((default-directory dir))
        (comint-exec (current-buffer) "robot-runner" exe nil
                     (append prefix args)))
      (set-process-sentinel
       (get-buffer-process (current-buffer))
       #'robot-runner--sentinel)
      (pop-to-buffer (current-buffer)))))

;;; Interactive commands

(defun robot-runner--arguments ()
  "Return current transient arguments."
  (transient-args 'robot-runner-dispatch))

;;;###autoload
(defun robot-runner-test-at-point (args)
  "Run the Robot test case at point, with transient ARGS."
  (interactive (list (robot-runner--arguments)))
  (let ((full-name (format "%s.%s"
                           (robot-runner--current-suite-name (buffer-file-name))
                           (robot-runner--current-test-name))))
    (robot-runner--run (append args (list "-t" full-name ".")))))

;;;###autoload
(defun robot-runner-suite (args)
  "Run the Robot suite for the current file, with transient ARGS."
  (interactive (list (robot-runner--arguments)))
  (let ((suite-name (robot-runner--current-suite-name (buffer-file-name))))
    (robot-runner--run (append args (list "-s" suite-name ".")))))

;;;###autoload
(defun robot-runner-directory (name args)
  "Run all Robot tests in the current directory, with transient ARGS."
  (interactive (list (file-name-nondirectory (directory-file-name default-directory))
                     (robot-runner--arguments)))
  (unless (seq-contains-p args "--name" (lambda (a b) (string-match b a)))
    (setq args (append (list "--name" name) args)))
  (robot-runner--run (append args (robot-runner--get-robot-files))))

;;;###autoload
(defun robot-runner-files (args files)
  "Run a selected set of Robot FILES, with transient ARGS."
  (interactive (list (robot-runner--arguments) (robot-runner--read-files)))
  (robot-runner--run (append args files)))

;;; Transient arguments

(transient-define-argument robot-runner:--rerunfailed ()
  :description "Re-run failed (output.xml)"
  :class 'transient-option
  :shortarg "-R"
  :argument "--rerunfailed="
  :reader #'robot-runner--read-output-file)

(transient-define-argument robot-runner:--outputdir ()
  :description "Output directory"
  :class 'transient-option
  :shortarg "-d"
  :argument "--outputdir="
  :reader #'robot-runner--read-directory)

(transient-define-argument robot-runner:--output ()
  :description "Output XML file"
  :class 'transient-option
  :shortarg "-o"
  :argument "--output="
  :reader #'robot-runner--read-file)

(transient-define-argument robot-runner:--name ()
  :description "Top-level suite name"
  :class 'transient-option
  :shortarg "-n"
  :argument "--name="
  :reader #'completing-read)

(transient-define-argument robot-runner:--loglevel ()
  :description "Log level"
  :class 'transient-option
  :key "-L"
  :argument "--loglevel="
  :choices '("DEBUG" "INFO" "WARN" "NONE"
             "DEBUG:INFO" "DEBUG:WARN" "INFO:DEBUG" "INFO:WARN"))

(transient-define-argument robot-runner:--pythonpath ()
  :description "Python path"
  :class 'transient-option
  :key "-P"
  :argument "--pythonpath="
  :shortarg "-P")

(transient-define-argument robot-runner:--variable ()
  :description "Variable (KEY:VALUE)"
  :class 'transient-option
  :key "-v"
  :argument "--variable="
  :shortarg "-v"
  :multi-value 'repeat)

(transient-define-argument robot-runner:--metadata ()
  :description "Metadata (KEY:VALUE)"
  :class 'transient-option
  :key "-M"
  :argument "--metadata="
  :shortarg "-M"
  :multi-value 'repeat)

(transient-define-argument robot-runner:--listener ()
  :description "Listener"
  :class 'transient-option
  :key "-l"
  :argument "--listener="
  :shortarg "-l"
  :multi-value 'repeat)

(transient-define-argument robot-runner:--include ()
  :description "Include tags"
  :class 'transient-option
  :key "-i"
  :argument "--include="
  :shortarg "-i"
  :multi-value 'repeat
  :reader #'robot-runner--read-tag)

(transient-define-argument robot-runner:--exclude ()
  :description "Exclude tags"
  :class 'transient-option
  :key "-e"
  :argument "--exclude="
  :shortarg "-e"
  :multi-value 'repeat
  :reader #'robot-runner--read-tag)

;;;###autoload
(transient-define-prefix robot-runner-dispatch ()
  "Transient menu for running Robot Framework tests."
  ["Test Selection"
   (robot-runner:--include)
   (robot-runner:--exclude)
   (robot-runner:--rerunfailed)]
  ["Variables & Config"
   (robot-runner:--variable)
   (robot-runner:--metadata)
   (robot-runner:--pythonpath)
   (robot-runner:--listener)]
  ["Output"
   (robot-runner:--name)
   (robot-runner:--loglevel)
   (robot-runner:--output)
   (robot-runner:--outputdir)
   ("-T" "Timestamp output files" "--timestampoutputs")]
  ["Execution flags"
   ("--d" "Dry run"               "--dryrun")
   ("-X"  "Exit on failure"       "--exitonfailure")
   ("--x" "Exit on error"         "--exitonerror")
   ("--s" "Skip teardown on exit" "--skipteardownonexit")]
  ["Launch"
   ("t" "Test at point"    robot-runner-test-at-point)
   ("a" "Current suite"    robot-runner-suite)
   ("d" "Directory suite"  robot-runner-directory)
   ("f" "Select files"     robot-runner-files)])

(provide 'robot-runner)
;;; robot-runner.el ends here
