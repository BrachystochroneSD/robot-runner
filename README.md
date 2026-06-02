# robot-runner.el

**Run [Robot Framework](https://robotframework.org/) tests directly from Emacs** via a
[transient](https://github.com/magit/transient)-powered menu.

![screenshot placeholder](screenshot.png)

## Features

- Run **test at point**, **current suite**, **directory**, or **selected files**
- **Tag completion** for `--include` / `--exclude` filters (reads tags from your project)
- **Clickable output links** — `log.html`, `report.html`, `output.xml` are buttons in the results buffer
- Works with plain `robot`, [`robotcode`](https://robotcode.io/), or any custom wrapper
- Robot Framework 7.1+ supported (`--consolelinks off` added automatically)

## Installation

### MELPA (coming soon)

```
M-x package-install RET robot-runner RET
```

### Manual

Clone this repository and add it to your load-path:

```elisp
(add-to-list 'load-path "/path/to/robot-runner")
(require 'robot-runner)
```

### with `use-package`

```elisp
(use-package robot-runner
  :load-path "~/path/to/robot-runner")
```

## Quick Start

Call `M-x robot-runner-dispatch` from any `.robot` buffer to open the transient menu.

Bind it to a key for convenience:

```elisp
(global-set-key (kbd "C-c r") #'robot-runner-dispatch)
```

## Configuration

### Basic — plain `robot`

```elisp
(use-package robot-runner
  :bind ("C-c r" . robot-runner-dispatch))
```

### With [`robot-mode`](https://github.com/sakari/robot-mode) (syntax highlighting)

`robot-runner` is fully independent from `robot-mode`, but they complement each other well:

```elisp
(use-package robot-mode
  :mode (("\\.robot\\'" . robot-mode)
         ("\\.resource\\'" . robot-mode)))

(use-package robot-runner
  :after robot-mode
  :bind (:map robot-mode-map
              ("C-c C-r" . robot-runner-dispatch)))
```

### With [`robotcode`](https://robotcode.io/) (LSP + runner)

[robotcode](https://robotcode.io/) is a powerful Robot Framework toolchain that includes an
LSP language server and a `robotcode robot` runner with extra features.

```elisp
(use-package robot-mode
  :mode (("\\.robot\\'" . robot-mode)
         ("\\.resource\\'" . robot-mode))
  :hook (robot-mode . eglot-ensure)
  :config
  (push (cons '(robot-mode :language-id "robotframework")
              '("robotcode" "language-server"))
        eglot-server-programs))

(use-package robot-runner
  :after robot-mode
  :custom
  ;; Use robotcode as the runner instead of plain robot
  (robot-runner-command '("robotcode" "robot"))
  :bind (:map robot-mode-map
              ("C-c C-r" . robot-runner-dispatch)))
```

### With `lsp-mode` instead of `eglot`

```elisp
(use-package lsp-mode
  :hook (robot-mode . lsp))

(use-package robot-runner
  :custom (robot-runner-command '("robotcode" "robot"))
  :bind ("C-c r" . robot-runner-dispatch))
```

## Customization

| Variable | Default | Description |
|---|---|---|
| `robot-runner-command` | `'("robot")` | Executable and optional prefix args |
| `robot-runner-extra-args` | `'()` | Args always passed to robot |
| `robot-runner-use-git-root` | `t` | Run from Git repo root |
| `robot-runner-open-report-after-run` | `nil` | Open `report.html` automatically |

### Common examples

```elisp
;; Use robotcode
(setq robot-runner-command '("robotcode" "robot"))

;; Always run with DEBUG log level
(setq robot-runner-extra-args '("--loglevel" "DEBUG"))

;; Don't hunt for git root, use current directory
(setq robot-runner-use-git-root nil)

;; Open the HTML report automatically after each run
(setq robot-runner-open-report-after-run t)
```

## Transient Menu Reference

```
╔══════════════════════════════════════╗
║  Test Selection                      ║
║  -i  Include tags  (with completion) ║
║  -e  Exclude tags  (with completion) ║
║  -R  Re-run failed (output.xml)      ║
╠══════════════════════════════════════╣
║  Variables & Config                  ║
║  -v  Variable (KEY:VALUE)            ║
║  -M  Metadata (KEY:VALUE)            ║
║  -P  Python path                     ║
║  -l  Listener                        ║
╠══════════════════════════════════════╣
║  Output                              ║
║  -n  Suite name                      ║
║  -L  Log level                       ║
║  -o  Output XML file                 ║
║  -d  Output directory                ║
║  -T  Timestamp output files          ║
╠══════════════════════════════════════╣
║  Execution flags                     ║
║  --d  Dry run                        ║
║  -X   Exit on failure                ║
║  --x  Exit on error                  ║
║  --s  Skip teardown on exit          ║
╠══════════════════════════════════════╣
║  Launch                              ║
║  t  Test at point                    ║
║  a  Current suite                    ║
║  d  Directory suite                  ║
║  f  Select files                     ║
╚══════════════════════════════════════╝
```

## Requirements

- Emacs 27.1+
- [transient](https://github.com/magit/transient) 0.4.0+
- [Robot Framework](https://robotframework.org/) installed and on your `$PATH`

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
