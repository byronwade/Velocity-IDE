# VS Code Feature Parity Research

**Date:** 2026-07-09
**Rule:** VS Code feature parity, not VS Code bloat parity.
**Product:** Velocity IDE (`apps/native-shell`)

## Sources

### Official docs
- https://code.visualstudio.com/docs
- https://code.visualstudio.com/api/references/contribution-points
- https://code.visualstudio.com/api/references/activation-events
- https://code.visualstudio.com/api/advanced-topics/extension-host
- https://code.visualstudio.com/docs/configure/extensions/extension-runtime-security
- https://code.visualstudio.com/docs/editing/codebasics
- https://code.visualstudio.com/docs/terminal/basics
- https://code.visualstudio.com/docs/terminal/shell-integration
- https://code.visualstudio.com/docs/terminal/profiles
- https://code.visualstudio.com/docs/sourcecontrol/overview
- https://code.visualstudio.com/docs/debugtest/debugging
- https://code.visualstudio.com/docs/debugtest/tasks
- https://code.visualstudio.com/docs/agents/overview
- https://github.com/vercel-labs/native / https://native-sdk.dev

### External Microsoft VS Code source baseline

Research used the external `microsoft/vscode` repository; none of these paths
exist locally:

- https://github.com/microsoft/vscode/blob/main/package.json
- https://github.com/microsoft/vscode/tree/main/src/vs/workbench
- https://github.com/microsoft/vscode/tree/main/src/vs/code/electron-main
- https://github.com/microsoft/vscode/tree/main/src/vs/workbench/api
- https://github.com/microsoft/vscode/tree/main/src/vs/workbench/services/extensions
- https://github.com/microsoft/vscode/blob/main/src/vs/platform/extensions/common/extensions.ts
- https://github.com/microsoft/vscode/tree/main/src/vs/workbench/contrib
- https://github.com/microsoft/vscode/tree/main/extensions

---

## Contribution point inventory

From official contribution-point docs and the external baseline's
`IExtensionContributions` definition:

| Contribution | Velocity mapping | Mode | Impl | Startup | Mem risk | Proc risk | Priority |
|---|---|---|---|---|---|---|---|
| authentication | deferred / agent-cloud stub | heavy | plugin | no | med | low | P3 |
| breakpoints | feature.breakpoints | dev | native | no | low | low | P1 |
| chatAgents / chatParticipants | feature.agent-* | agent | native | no | med | low | P0 |
| chatInstructions / chatPromptFiles / chatSkills | feature.agent-context | agent | native | no | low | low | P2 |
| colors / themes / iconThemes / productIconThemes | feature.themes | core | native | yes | low | none | P0 |
| commands | feature.command-palette + command_registry | core | native | yes | low | none | P0 |
| configuration / configurationDefaults | feature.settings | core | native | no | low | none | P0 |
| customEditors | feature.custom-editors | heavy | webview | no | high | med | P3 |
| debuggers | feature.debug-* | dev | process | no | med | high | P1 |
| grammars / languages | feature.syntax-highlighting / language-registry | core | native | no | med | none | P0 |
| icons | themes / activity-rail | core | native | yes | low | none | P1 |
| jsonValidation | feature.json-language-pack | core | process | no | med | low | P1 |
| keybindings | feature.keybindings | core | native | yes | low | none | P0 |
| languageModelChatProviders / languageModelTools | feature.agent-tool-registry | agent | plugin | no | med | med | P1 |
| menus / submenus | feature.context-menus | core | native | no | low | none | P1 |
| problemMatchers / problemPatterns | feature.problem-matchers | dev | native | no | low | none | P1 |
| resourceLabelFormatters | workspace-manager | core | native | no | low | none | P2 |
| semanticToken* | feature.semantic-tokens | dev | process | no | med | low | P1 |
| snippets | feature.snippets | core | native | no | low | none | P1 |
| taskDefinitions | feature.task-runner | dev | process | no | med | high | P1 |
| terminal | feature.terminal* | core | process | no | high | high | P0 |
| typescriptServerPlugins | js-ts-language-pack | core | process | no | high | med | P1 |
| views / viewsContainers / viewsWelcome | sidebar / activity-rail | core | native | yes | low | none | P0 |
| walkthroughs | welcome-empty-state (minimal) | core | native | no | low | none | P2 |
| notebooks / notebookRenderer | feature.notebooks | heavy | webview | no | high | high | P3 |
| mcpServerDefinitionProviders | feature.agent-mcp-adapter | agent | process | never default | med | med | P2 |

---

## Activation event inventory

From the docs and the external baseline's `extensionsRegistry.ts`:

| Event | Velocity policy | Allowed before first paint? |
|---|---|---|
| `*` | **Rejected** — never | no |
| `onStartupFinished` | Map to `onFirstPaintDone` / `onIdle` only | no |
| `onLanguage` / `onLanguage:` | `onLanguage` / `onFileOpen` | no |
| `onCommand` / `onCommand:` | `onCommand` | no |
| `onDebug*` | `onDebugStart` | no |
| `workspaceContains` / `workspaceContains:` | Prefer explicit workspace open + detector; avoid boot scans | no |
| `onTaskType` | `onTaskRun` | no |
| `onFileSystem` | deferred / plugin | no |
| `onEditSession` | heavy / deferred | no |
| `onSearch` | `onSearch` | no |
| `onView` / `onView:` | `onViewVisible` | no |
| `onUri` / `onOpenExternalUri` | command / deep-link after paint | no |
| `onCustomEditor` | heavy | no |
| `onNotebook` | heavy | no |
| `onAuthenticationRequest` | explicit user action | no |
| `onRenderer` | heavy notebook | no |
| `onTerminalProfile` / `onTerminal` / `onTerminalShellIntegration` / `onTerminalQuickFixRequest` | `onTerminalOpen` | no |
| `onWalkthrough` | minimal welcome only | no |
| `onIssueReporterOpened` | deferred | no |
| `onChatParticipant` / `onLanguageModelChatProvider` / `onLanguageModelTool` | `onAgentStart` | no |
| `onMcpCollection` | agent-mcp, disabled by default | no |
| `onWebviewPanel` | heavy webviews | no |

Velocity adds: `onStartupCritical`, `onFirstPaintDone`, `onIdle`, `onPanelVisible`, `onWorkspaceOpen`, `onTerminalOpen`, `onTaskRun`, `onDebugStart`, `onTestRun`, `onAgentStart`, `onPluginInstall`, `never`.

---

## Feature category inventories

### Editor / workbench
Editing basics (docs/editing/codebasics): multi-cursor, find/replace, folding, breadcrumbs, minimap, sticky scroll, etc.
**External baseline:** corresponding modules under
https://github.com/microsoft/vscode/tree/main/src/vs/workbench/contrib.
**Velocity:** core shell + editor-island; minimap **disabled by default**; Monaco via island after paint.

### Terminal
Docs: profiles, tabs, splits, links, scrollback, shell integration, sticky
scroll, and command navigation.
**External baseline:** https://github.com/microsoft/vscode/tree/main/src/vs/workbench/contrib/terminal.
**Velocity:** bounded scrollback default **2000** / hard max **10000**; no shell integration before first command; Process Governor owns PTY; see `12-terminal-ram-and-process-management.md`.

### SCM
Docs: sourcecontrol/overview.
**External baseline:** [SCM workbench](https://github.com/microsoft/vscode/tree/main/src/vs/workbench/contrib/scm)
and [Git extensions](https://github.com/microsoft/vscode/tree/main/extensions).
**Velocity:** Dev mode; no git process until SCM visible/queried.

### Debug / tasks / testing
Docs: debugging, tasks.
**External baseline:** relevant modules under
https://github.com/microsoft/vscode/tree/main/src/vs/workbench/contrib.
**Velocity:** Dev mode; adapters/tasks only on explicit start.

### Notebook / webview / remote
**External baseline:** relevant modules under
https://github.com/microsoft/vscode/tree/main/src/vs/workbench/contrib.
**Velocity:** Heavy/Remote; never boot.

### Agent / chat
Docs: agents/overview.
**External baseline:** relevant modules under
https://github.com/microsoft/vscode/tree/main/src/vs/workbench/contrib.
**Velocity:** Agent mode first-class; no network/AI calls in scaffold; MCP disabled by default.

### Extensions security risks
From extension-runtime-security, Workspace Trust docs, and the external host
implementation:
- Extension host has **same OS permissions as the app** (filesystem, network, processes).
- Publisher trust prompts do not sandbox capabilities.
- Workspace Trust / Restricted Mode gates automatic code execution; still not a true capability sandbox.
- `workspaceContains` activation can scan disk at open time.
- Proposed APIs / chat tools / MCP expand attack surface.
- **Velocity response:** native plugins default-deny permissions; legacy VSIX never default; no activation before first paint; Process Governor; Workspace Trust Plus.

---

## Mode assignment summary

| Mode | Intent | Examples |
|---|---|---|
| Core | Daily edit loop | shell, explorer, editor island, palette, terminal lazy, LSP broker lazy |
| Dev | Professional tooling | git, debug, tasks, testing, problems UI |
| Heavy | Optional expensive | notebooks, webviews, history, sync |
| Agent | AI-native | composer, review/apply, indexer (opt-in) |
| Remote | Remote/devcontainers | ssh/containers stubs |
| Legacy | Compatibility only | VSIX bridge / extension host |

---

## Implementation priority (research → build)

1. Canonical feature catalog + generated registry + activation policy
2. Process Governor + Performance HUD
3. Terminal RAM strategy + bounded PTY protocol (transport unavailable)
4. File/search/workspace real I/O
5. Monaco island after paint
6. Git provider
7. LSP broker + one language pack
8. Native plugin MVP
9. Agent apply/review without cloud
10. Legacy VSIX research only

Full metadata list: `apps/native-shell/src/core/feature_catalog.json` and
`14-feature-parity-matrix.md`. The generated Zig projection is
`apps/native-shell/src/core/feature_registry.zig`.
