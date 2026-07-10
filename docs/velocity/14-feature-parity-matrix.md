# Feature Parity Matrix

Complete catalog: `apps/native-shell/src/core/feature_catalog.json` (200 modules).
Research: `11-vscode-feature-parity-research.md`.

## Columns
VS Code feature → Velocity module → mode → priority → native/WebView/process/plugin → startup allowed → memory budget MB → process budget → terminal impact → status → source → notes

## Matrix

| VS Code feature | Velocity module | mode | priority | impl | startup | mem MB | procs | term impact | status | source | notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Activity Rail | `feature.activity-rail` | core | P0 | native | True | 2 | 0 | low | stub | docs/11 + contrib | |
| Sidebar | `feature.sidebar` | core | P0 | native | True | 4 | 0 | low | stub | docs/11 + contrib | |
| Panel | `feature.panel` | core | P0 | native | True | 4 | 0 | low | stub | docs/11 + contrib | |
| Status Bar | `feature.status-bar` | core | P0 | native | True | 2 | 0 | low | stub | docs/11 + contrib | |
| Command Palette | `feature.command-palette` | core | P0 | native | True | 4 | 0 | low | stub | docs/11 + contrib | |
| Quick Open | `feature.quick-open` | core | P0 | native | False | 8 | 0 | low | working | deterministic bounded fuzzy/path ranking + recent tie-break | |
| Editor Groups | `feature.editor-groups` | core | P0 | native | True | 8 | 0 | low | stub | docs/11 + contrib | |
| Tabs | `feature.tabs` | core | P0 | native | True | 4 | 0 | low | stub | docs/11 + contrib | |
| Breadcrumbs | `feature.breadcrumbs` | core | P1 | native | False | 2 | 0 | low | working | clickable path segments + 32-entry path/line Back/Forward history | |
| Layout | `feature.layout` | core | P0 | native | True | 2 | 0 | low | stub | docs/11 + contrib | |
| Settings | `feature.settings` | core | P0 | native | False | 8 | 0 | low | working | searchable persisted prefs + bounded poll interval | |
| Keybindings | `feature.keybindings` | core | P0 | native | True | 2 | 0 | low | stub | docs/11 + contrib | |
| Themes | `feature.themes` | core | P0 | native | True | 2 | 0 | low | stub | docs/11 + contrib | |
| Notifications | `feature.notifications` | core | P1 | native | False | 4 | 0 | low | working | bounded structured/deduped center + safe actions | |
| Context Menus | `feature.context-menus` | core | P1 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
| Hover | `feature.hover` | core | P1 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Dialogs | `feature.dialogs` | core | P1 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Welcome / Empty State | `feature.welcome-empty-state` | core | P2 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
| Accessibility Core | `feature.accessibility-core` | core | P0 | native | True | 4 | 0 | low | stub | docs/11 + contrib | |
| File Explorer | `feature.file-explorer` | core | P0 | native | False | 16 | 0 | low | working | bounded collapse/filter projection; reveal; SCM decorations; honest scan cap | |
| Workspace Manager | `feature.workspace-manager` | core | P0 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Multi-root Workspaces | `feature.multi-root-workspaces` | dev | P2 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Recent Projects | `feature.recent-projects` | core | P0 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
| File Watchers | `feature.file-watchers` | core | P1 | process | False | 8 | 1 | low | stub | docs/11 + contrib | |
| Hot Exit | `feature.hot-exit` | core | P2 | native | False | 4 | 0 | low | working | bounded workspace session restore on Close Window | |
| Auto Save | `feature.auto-save` | core | P1 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
| Backups | `feature.backups` | core | P2 | native | False | 8 | 0 | low | working | bounded backup before confirmed overwrite; guarded active-file preview/restore | |
| File Encoding | `feature.file-encoding` | core | P2 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
| File Decorations | `feature.file-decorations` | dev | P2 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Drag and Drop | `feature.drag-drop` | core | P2 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
| Dirty State | `feature.dirty-state` | core | P0 | native | False | 2 | 0 | low | working | bounded per-tab copies and undo/redo histories, partial-conflict Save All, disk polling | |
| Compare Files | `feature.compare-files` | dev | P2 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Diff Editor | `feature.diff-editor` | dev | P1 | native | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Merge Editor | `feature.merge-editor` | dev | P2 | native | False | 24 | 0 | low | stub | docs/11 + contrib | |
| Editor Island | `feature.editor-island` | core | P0 | native | False | 32 | 0 | low | scaffold / SDK-blocked rich backends | typed protocol; textarea runtime unchanged | Monaco requires stable WebView messaging/focus/IME/a11y; textarea gutter API also absent |
| Monaco Bridge | `feature.monaco-bridge` | core | P1 | webview | False | 80 | 0 | low | scaffold / blocked by SDK | typed backend only; no WebView | stable WebView lifecycle + bidirectional messaging/focus/IME/a11y |
| Native Editor Research | `feature.native-editor-research` | heavy | P3 | deferred | False | 0 | 0 | low | stub | docs/11 + contrib | |
| Multi Cursor | `feature.multi-cursor` | core | P1 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Column Selection | `feature.column-selection` | core | P2 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
| Find Replace | `feature.find-replace` | core | P0 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Search Selection | `feature.search-selection` | core | P2 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
| Snippets | `feature.snippets` | core | P1 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Syntax Highlighting | `feature.syntax-highlighting` | core | P0 | native | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Semantic Tokens | `feature.semantic-tokens` | dev | P1 | process | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Bracket Matching | `feature.bracket-matching` | core | P1 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
| Bracket Pair Colorization | `feature.bracket-pair-colorization` | core | P2 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Folding | `feature.folding` | core | P1 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Minimap | `feature.minimap` | heavy | P3 | native | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Code Lens | `feature.code-lens` | dev | P2 | process | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Inlay Hints | `feature.inlay-hints` | dev | P2 | process | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Inline Suggestions | `feature.inline-suggestions` | agent | P1 | plugin | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Hover Docs | `feature.hover-docs` | dev | P1 | process | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Go to Definition | `feature.go-to-definition` | dev | P0 | process | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Go to References | `feature.go-to-references` | dev | P0 | process | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Peek | `feature.peek` | dev | P1 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Rename Symbol | `feature.rename-symbol` | dev | P1 | process | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Code Actions | `feature.code-actions` | dev | P1 | process | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Refactor | `feature.refactor` | dev | P1 | process | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Formatting | `feature.formatting` | dev | P0 | process | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Outline | `feature.outline` | dev | P1 | process | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Symbols | `feature.symbols` | dev | P1 | process | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Problems | `feature.problems` | dev | P0 | native | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Diagnostics | `feature.diagnostics` | core | P0 | process | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Language Status | `feature.language-status` | dev | P2 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
| Workspace Search | `feature.workspace-search` | core | P0 | native | False | 24 | 0 | low | working | bounded case/whole-word/path scope + fixed-key debounce | |
| Quick Search | `feature.quick-search` | core | P0 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Search Results | `feature.search-results` | core | P0 | native | False | 16 | 0 | low | working | bounded clickable path/line results integrated with navigation history | |
| Search Replace | `feature.search-replace` | core | P1 | native | False | 16 | 0 | low | working | bounded preview, guarded double-confirm apply, same search options/scope | |
| Ripgrep Adapter | `feature.ripgrep-adapter` | core | P0 | process | False | 8 | 1 | low | stub | docs/11 + contrib | |
| Search Index | `feature.search-index` | dev | P2 | process | False | 64 | 1 | low | stub | docs/11 + contrib | |
| Search Editor | `feature.search-editor` | heavy | P3 | native | False | 32 | 0 | low | stub | docs/11 + contrib | |
| Fuzzy File Search | `feature.fuzzy-file-search` | core | P0 | native | False | 16 | 0 | low | working | exact/prefix/segment/fuzzy/substring ranking with stable ordering | |
| Symbol Search | `feature.symbol-search` | dev | P1 | native | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Command Search | `feature.command-search` | core | P0 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Terminal | `feature.terminal` | core | P0 | process | False | 32 | 1 | high | scaffold / PTY blocked by SDK | pipe runner works; PTY protocol in-memory only | cross-platform PTY streams, resize, cancellation/process-tree lifecycle |
| Terminal Profiles | `feature.terminal-profiles` | core | P1 | native | False | 4 | 0 | high | working | bounded command-only `.velocity/launch.json`; shared governor effect | |
| Terminal Tabs | `feature.terminal-tabs` | core | P1 | native | False | 4 | 0 | high | stub | docs/11 + contrib | |
| Terminal Splits | `feature.terminal-splits` | core | P2 | native | False | 4 | 0 | high | stub | docs/11 + contrib | |
| Terminal Links | `feature.terminal-links` | core | P1 | native | False | 4 | 0 | high | stub | docs/11 + contrib | |
| Terminal Shell Integration | `feature.terminal-shell-integration` | dev | P2 | native | False | 8 | 0 | high | stub | docs/11 + contrib | |
| Terminal Find | `feature.terminal-find` | core | P1 | native | False | 8 | 0 | high | stub | docs/11 + contrib | |
| Task Runner | `feature.task-runner` | dev | P1 | process | False | 16 | 1 | high | working | npm/tasks.json/Make via governed terminal + Stop + diagnostics | |
| Task Detector | `feature.task-detector` | dev | P2 | native | False | 8 | 0 | high | working | bounded npm, tasks.json shell/process, simple Make targets; deterministic precedence | |
| Problem Matchers | `feature.problem-matchers` | dev | P1 | native | False | 8 | 0 | high | working | bounded TS/Zig/GCC + Vitest/Jest assertion locations | |
| Output Panel | `feature.output-panel` | dev | P1 | native | False | 16 | 0 | high | working | bounded All/Task/Test/Launch/Git/System registry | |
| SCM Core | `feature.scm-core` | dev | P0 | native | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Git Provider | `feature.git-provider` | dev | P0 | process | False | 24 | 1 | low | stub | docs/11 + contrib | |
| Git Status | `feature.git-status` | dev | P0 | process | False | 8 | 1 | low | stub | docs/11 + contrib | |
| Git Diff | `feature.git-diff` | dev | P0 | process | False | 16 | 1 | low | stub | docs/11 + contrib | |
| Git Stage/Commit | `feature.git-stage-commit` | dev | P0 | process | False | 8 | 1 | low | working | per-file/all stage/unstage, guarded restore, commit | |
| Git Branches | `feature.git-branches` | dev | P1 | process | False | 8 | 1 | low | stub | docs/11 + contrib | |
| Git Merge Conflicts | `feature.git-merge-conflicts` | dev | P1 | native | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Git History | `feature.git-history` | heavy | P2 | process | False | 32 | 1 | low | stub | docs/11 + contrib | |
| Pull Request Provider | `feature.pull-request-provider` | heavy | P3 | native | False | 24 | 0 | low | stub | docs/11 + contrib | |
| SCM Provider API | `feature.source-control-provider-api` | dev | P2 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Debug Core | `feature.debug-core` | dev | P1 | native | False | 24 | 0 | low | stub | docs/11 + contrib | |
| Debug Adapter Protocol | `feature.debug-adapter-protocol` | dev | P1 | process | False | 16 | 1 | low | stub | docs/11 + contrib | |
| Debug Configurations | `feature.debug-configurations` | dev | P1 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Breakpoints | `feature.breakpoints` | dev | P1 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Call Stack | `feature.call-stack` | dev | P1 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Variables | `feature.variables` | dev | P1 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Watch | `feature.watch` | dev | P2 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Debug Console | `feature.debug-console` | dev | P1 | native | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Debug REPL | `feature.debug-repl` | dev | P2 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Test Core | `feature.test-core` | dev | P1 | native | False | 16 | 0 | low | working | run/rerun test or test:*; pass/fail/cancel state; shared governed process | |
| Test Discovery | `feature.test-discovery` | dev | P1 | process | False | 16 | 1 | low | partial | task-name discovery only; no per-test tree | |
| Test Explorer | `feature.test-explorer` | dev | P1 | native | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Test Output | `feature.test-output` | dev | P1 | native | False | 16 | 0 | low | working | labeled bounded Output mirror + assertion Problems | |
| Coverage | `feature.coverage` | heavy | P3 | process | False | 32 | 1 | low | stub | docs/11 + contrib | |
| LSP Broker | `feature.lsp-broker` | core | P0 | native | False | 16 | 0 | low | scaffold / transport blocked by SDK | bounded JSON-RPC/session/diagnostics; no process | long-lived streamed child process, backpressure, cancellation/exit, governor ownership |
| LSP Process Manager | `feature.lsp-process-manager` | core | P0 | process | False | 8 | 4 | low | stub | docs/11 + contrib | |
| Language Registry | `feature.language-registry` | core | P0 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Language Server Registry | `feature.language-server-registry` | core | P0 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Language Client | `feature.language-client` | core | P0 | native | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Formatter Registry | `feature.formatter-registry` | dev | P1 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Diagnostic Registry | `feature.diagnostic-registry` | core | P0 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Completion Registry | `feature.completion-registry` | core | P0 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Semantic Token Registry | `feature.semantic-token-registry` | dev | P1 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| JS/TS Language Pack | `feature.js-ts-language-pack` | core | P0 | process | False | 48 | 1 | low | stub | docs/11 + contrib | |
| JSON Language Pack | `feature.json-language-pack` | core | P1 | process | False | 16 | 1 | low | stub | docs/11 + contrib | |
| CSS/HTML Language Pack | `feature.css-html-language-pack` | dev | P2 | process | False | 24 | 1 | low | stub | docs/11 + contrib | |
| Markdown Language Pack | `feature.markdown-language-pack` | dev | P1 | process | False | 16 | 1 | low | stub | docs/11 + contrib | |
| Python Language Pack | `feature.python-language-pack` | heavy | P2 | process | False | 64 | 1 | low | stub | docs/11 + contrib | |
| Rust Language Pack | `feature.rust-language-pack` | heavy | P2 | process | False | 64 | 1 | low | stub | docs/11 + contrib | |
| Go Language Pack | `feature.go-language-pack` | heavy | P2 | process | False | 48 | 1 | low | stub | docs/11 + contrib | |
| Native Plugin Runtime | `feature.native-plugin-runtime` | core | P0 | process | False | 16 | 1 | low | stub | docs/11 + contrib | |
| Plugin Manifest | `feature.plugin-manifest` | core | P0 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
| Plugin Permissions | `feature.plugin-permissions` | core | P0 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
| Plugin Activation | `feature.plugin-activation` | core | P0 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Plugin Sandbox | `feature.plugin-sandbox` | core | P1 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Plugin Registry Client | `feature.plugin-registry-client` | core | P1 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Plugin Install | `feature.plugin-install` | core | P1 | process | False | 8 | 1 | low | stub | docs/11 + contrib | |
| Plugin Update | `feature.plugin-update` | core | P2 | process | False | 8 | 1 | low | stub | docs/11 + contrib | |
| Plugin Signatures | `feature.plugin-signatures` | core | P1 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Plugin Scorecard | `feature.plugin-scorecard` | core | P1 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Plugin Marketplace UI | `feature.plugin-marketplace-ui` | core | P1 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Plugin Devtools | `feature.plugin-devtools` | dev | P2 | native | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Plugin Host Process | `feature.plugin-host-process` | core | P0 | process | False | 32 | 1 | low | stub | docs/11 + contrib | |
| Plugin Memory Budget | `feature.plugin-memory-budget` | core | P0 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
| Legacy VSIX Bridge | `feature.legacy-vsix-bridge` | legacy | P3 | legacy | False | 64 | 1 | low | stub | docs/11 + contrib | |
| Legacy Extension Host | `feature.legacy-extension-host` | legacy | P3 | legacy | False | 128 | 1 | low | stub | docs/11 + contrib | |
| Agent Composer | `feature.agent-composer` | agent | P0 | native | False | 24 | 0 | low | stub | docs/11 + contrib | |
| Inline Agent Edit | `feature.inline-agent-edit` | agent | P1 | native | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Agent Task List | `feature.agent-task-list` | agent | P0 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Agent Review | `feature.agent-review` | agent | P0 | native | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Agent Apply | `feature.agent-apply` | agent | P0 | native | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Agent Checkpoints | `feature.agent-checkpoints` | agent | P1 | native | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Agent Context | `feature.agent-context` | agent | P0 | native | False | 24 | 0 | low | stub | docs/11 + contrib | |
| Agent Indexer | `feature.agent-indexer` | agent | P1 | native | False | 64 | 0 | low | stub | docs/11 + contrib | |
| Agent Memory | `feature.agent-memory` | agent | P2 | native | False | 32 | 0 | low | stub | docs/11 + contrib | |
| Agent Permissions | `feature.agent-permissions` | agent | P0 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Agent Terminal Approval | `feature.agent-terminal-approval` | agent | P0 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Agent Tool Registry | `feature.agent-tool-registry` | agent | P0 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Agent Model Router | `feature.agent-model-router` | agent | P1 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Agent Local Adapter | `feature.agent-local-adapter` | agent | P1 | native | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Agent Cloud Adapter | `feature.agent-cloud-adapter` | agent | P2 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Agent MCP Adapter | `feature.agent-mcp-adapter` | agent | P2 | native | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Agent Hooks | `feature.agent-hooks` | agent | P2 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Notebooks | `feature.notebooks` | heavy | P3 | webview | False | 64 | 0 | low | stub | docs/11 + contrib | |
| Notebook Renderers | `feature.notebook-renderers` | heavy | P3 | native | False | 32 | 0 | low | stub | docs/11 + contrib | |
| Markdown Preview | `feature.markdown-preview` | dev | P2 | webview | False | 24 | 0 | low | stub | docs/11 + contrib | |
| Webviews | `feature.webviews` | heavy | P2 | webview | False | 48 | 0 | low | stub | docs/11 + contrib | |
| Custom Editors | `feature.custom-editors` | heavy | P3 | webview | False | 48 | 0 | low | stub | docs/11 + contrib | |
| Timeline | `feature.timeline` | heavy | P3 | native | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Local History | `feature.local-history` | heavy | P3 | native | False | 32 | 0 | low | stub | docs/11 + contrib | |
| Profiles | `feature.profiles` | heavy | P3 | native | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Settings Sync | `feature.settings-sync` | heavy | P3 | native | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Remote SSH | `feature.remote-ssh` | remote | P3 | native | False | 32 | 0 | low | stub | docs/11 + contrib | |
| Remote Containers | `feature.remote-containers` | remote | P3 | native | False | 48 | 0 | low | stub | docs/11 + contrib | |
| Remote Tunnels | `feature.remote-tunnels` | remote | P3 | native | False | 24 | 0 | low | stub | docs/11 + contrib | |
| Port Forwarding | `feature.port-forwarding` | remote | P3 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Integrated Browser | `feature.integrated-browser` | heavy | P3 | webview | False | 64 | 0 | low | stub | docs/11 + contrib | |
| Accessibility Signals | `feature.accessibility-signals` | heavy | P3 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Voice | `feature.voice` | heavy | P3 | native | False | 32 | 0 | low | stub | docs/11 + contrib | |
| Performance HUD | `feature.performance-hud` | core | P0 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Process Governor UI | `feature.process-governor-ui` | core | P0 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Terminal Memory Inspector | `feature.terminal-memory-inspector` | core | P1 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Plugin Permission Inspector | `feature.plugin-permission-inspector` | core | P1 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Plugin Performance Score | `feature.plugin-performance-score` | core | P1 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Workspace Trust Plus | `feature.workspace-trust-plus` | core | P0 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Workspace Process Sandbox | `feature.workspace-process-sandbox` | core | P1 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Crash/Leak Reporter | `feature.crash-leak-reporter` | core | P1 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Feature Toggle Matrix | `feature.feature-toggle-matrix` | core | P0 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Startup Flamegraph View | `feature.startup-flamegraph` | core | P1 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| RAM Budget Dashboard | `feature.ram-budget-dashboard` | core | P0 | native | False | 4 | 0 | low | stub | docs/11 + contrib | |
| Project Capsule | `feature.project-capsule` | core | P1 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Agent Autonomy Slider | `feature.agent-autonomy-slider` | agent | P0 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
| Agent Worktree Manager | `feature.agent-worktree-manager` | agent | P1 | native | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Parallel Agent Task Board | `feature.parallel-agent-task-board` | agent | P0 | native | False | 16 | 0 | low | stub | docs/11 + contrib | |
| Codebase Index Health View | `feature.codebase-index-health` | agent | P1 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Command Journal | `feature.command-journal` | core | P1 | native | False | 8 | 0 | low | stub | docs/11 + contrib | |
| Instant Safe Mode | `feature.instant-safe-mode` | core | P0 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
| No-Extensions Mode | `feature.no-extensions-mode` | core | P0 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
| No-Agents Mode | `feature.no-agents-mode` | core | P0 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
| Minimal Battery Mode | `feature.minimal-battery-mode` | core | P1 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
| Memory Pressure Mode | `feature.memory-pressure-mode` | core | P0 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
| Kill All Workspace Processes | `feature.kill-all-workspace-processes` | core | P0 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
| Freeze Background Terminals | `feature.freeze-background-terminals` | core | P1 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
| Suspend Inactive Language Servers | `feature.suspend-inactive-language-servers` | core | P1 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
| Disable Heavy Features | `feature.disable-heavy-features` | core | P0 | native | False | 2 | 0 | low | stub | docs/11 + contrib | |
