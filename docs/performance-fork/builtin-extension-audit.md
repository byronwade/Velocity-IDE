# Built-in Extension Audit

## Classification legend

| Class | Meaning |
|---|---|
| Core syntax | Grammar + language-configuration only; cheap |
| Common web | HTML/CSS/JSON/JS/TS basics used by most web work |
| Optional language pack | Grammar for less common languages |
| Heavy language feature | LSP / tsserver / language server client |
| Debug-only | Debugger companions |
| Notebook-only | ipynb / renderers |
| Markdown-only | Markdown language features / math / mermaid |
| Theme/icon | Color and file icon themes |
| Remove from default | Not shipped activated in Core |
| Compat pack | Keep available when mode=compat/developer packaging |

## Marketplace built-ins (`product.json`)

| Extension | Class | Core | Developer | Compat |
|---|---|---|---|---|
| ms-vscode.js-debug | Debug-only | ❌ | ✅ | ✅ |
| ms-vscode.js-debug-companion | Debug-only | ❌ | ✅ | ✅ |
| ms-vscode.vscode-js-profile-table | Debug-only | ❌ | ✅ | ✅ |

Core Mode sets `builtInExtensions: []`. Mode-specific lists live under `builtInExtensionsByMode` for future packaging filters.

## Local `extensions/` inventory

### Keep in Core default build (syntax / essentials)

| Extension | Class | Notes |
|---|---|---|
| theme-defaults | Theme/icon | Required calm defaults |
| theme-seti | Theme/icon | File icons |
| javascript | Core syntax | |
| typescript-basics | Core syntax | |
| json | Core syntax | |
| css | Core syntax | |
| html | Core syntax | |
| markdown-basics | Core syntax | Preview optional |
| shellscript | Core syntax | Terminal adjacency |
| log | Core syntax | |
| diff | Core syntax | |
| ini / dotenv / xml / yaml | Core syntax | Common config |
| search-result | Other | Search UX |
| configuration-editing | Other | settings.json schema UX |

### Developer Mode additions

| Extension | Class |
|---|---|
| git / git-base | Git/SCM |
| merge-conflict | Git/SCM |
| typescript-language-features | Heavy language feature |
| json-language-features | Heavy language feature |
| css-language-features | Heavy language feature |
| html-language-features | Heavy language feature |
| emmet | Other |
| npm | Other |
| references-view | Other |
| media-preview | Media |
| simple-browser | Media |
| debug-auto-launch / debug-server-ready | Debug-only |
| terminal-suggest | Other |

### Compat / optional only (do not activate by default)

| Extension | Class |
|---|---|
| ipynb / notebook-renderers | Notebook-only |
| markdown-language-features / markdown-math / mermaid-chat-features | Markdown-only |
| php-language-features | Heavy language feature |
| github / github-authentication / microsoft-authentication | Auth / GitHub |
| grunt / gulp / jake | Task helpers |
| tunnel-forwarding | Remote |
| prompt-basics | Chat-adjacent |
| All remaining language grammars (python, java, go, rust, …) | Optional language pack |
| Extra themes (abyss, monokai, …) | Theme/icon |
| vscode-*-tests | Testing (already excluded from ship) |

## Packaging recommendation

1. Short term: empty marketplace `builtInExtensions` in Core; keep local extensions on disk but rely on activation budget + disable-on-startup setting.
2. Medium term: `build/lib/extensions.ts` filter by `performanceFork.mode` / allowlist.
3. Long term: ship “syntax pack” vs “web pack” vs “compat pack” as optional installable extension packs.

## Activation risk hotspots

| Extension | Activation | Risk |
|---|---|---|
| git | `*` | High — defer in Core |
| typescript-language-features | onLanguage | Medium — OK after file open |
| emmet | broad onLanguage | Medium |
| markdown-language-features | onLanguage + webview | Medium |
| notebook / ipynb | notebook open | High if imported in workbench |

## Rollback

Restore previous `builtInExtensions` array from git and set mode to `compat`.
