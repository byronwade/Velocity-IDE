/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

/**
 * Core Mode workbench contributions.
 *
 * Absolute minimum surface to open a folder/file and edit code:
 * editor shell, explorer, search, terminal (lean), preferences, themes,
 * quick access, extensions host registration (lazy activation), markers/output.
 *
 * Heavy packs (chat, notebook, testing, telemetry, welcome, sync, etc.) are
 * intentionally omitted. Developer/compat packs load them via other entrypoints.
 */

// Performance fork configuration + Focus Core defaults
import './browser/performanceFork/performanceFork.contribution.js';

// Preferences / settings / keybindings
import './contrib/preferences/browser/preferences.contribution.js';
import './contrib/preferences/browser/keybindingsEditorContribution.js';
import './contrib/preferences/browser/preferencesSearch.js';

// Performance diagnostics (kept — needed to measure the fork)
import './contrib/performance/browser/performance.contribution.js';

// Logs
import './contrib/logs/common/logs.contribution.js';

// Quick access / command palette helpers
import './contrib/quickaccess/browser/quickAccess.contribution.js';

// Explorer / files
import './contrib/files/browser/explorerViewlet.js';
import './contrib/files/browser/fileActions.contribution.js';
import './contrib/files/browser/files.contribution.js';

// Bulk edit (needed for rename/refactor from language features)
import './contrib/bulkEdit/browser/bulkEditService.js';
import './contrib/bulkEdit/browser/preview/bulkEdit.contribution.js';

// Search (basic)
import './contrib/search/browser/search.contribution.js';
import './contrib/search/browser/searchView.js';

// Sash
import './contrib/sash/browser/sash.contribution.js';

// Markers (problems) — lightweight; useful even in core
import './contrib/markers/browser/markers.contribution.js';

// Commands
import './contrib/commands/common/commands.contribution.js';

// URL support
import './contrib/url/browser/url.contribution.js';

// Webview stack — required for extension API compatibility; keep registered
import './contrib/webview/browser/webview.contribution.js';
import './contrib/webviewPanel/browser/webviewPanel.contribution.js';
import './contrib/webviewView/browser/webviewView.contribution.js';
import './contrib/customEditor/browser/customEditor.contribution.js';
import './contrib/externalUriOpener/common/externalUriOpener.contribution.js';

// Extensions management UI (install still available; gallery gated by settings)
import './contrib/extensions/browser/extensions.contribution.js';
import './contrib/extensions/browser/extensionsViewlet.js';

// Output
import './contrib/output/browser/output.contribution.js';
import './contrib/output/browser/outputView.js';

// Terminal (lean — terminal.all trimmed via terminal.core)
import './contrib/terminal/terminal.core.js';

// External terminal
import './contrib/externalTerminal/browser/externalTerminal.contribution.js';

// Relauncher
import './contrib/relauncher/browser/relauncher.contribution.js';

// Code editor contributions
import './contrib/codeEditor/browser/codeEditor.contribution.js';

// Keybindings
import './contrib/keybindings/browser/keybindings.contribution.js';

// Snippets
import './contrib/snippets/browser/snippets.contribution.js';

// Format / folding
import './contrib/format/browser/format.contribution.js';
import './contrib/folding/browser/folding.contribution.js';

// Limit indicator
import './contrib/limitIndicator/browser/limitIndicator.contribution.js';

// Inlay hint accessibility
import './contrib/inlayHints/browser/inlayHintsAccessibilty.js';

// Themes
import './contrib/themes/browser/themes.contribution.js';

// Outline / symbols
import './contrib/codeEditor/browser/outline/documentSymbolsOutline.js';
import './contrib/outline/browser/outline.contribution.js';

// Language status
import './contrib/languageStatus/browser/languageStatus.contribution.js';

// Code actions
import './contrib/codeActions/browser/codeActions.contribution.js';

// Workspace / workspaces
import './contrib/workspace/browser/workspace.contribution.js';
import './contrib/workspaces/browser/workspaces.contribution.js';

// List
import './contrib/list/browser/list.contribution.js';

// Accessibility (core support — not decorative signals)
import './contrib/accessibility/browser/accessibility.contribution.js';

// Inline completions (editor feature; chat entitlement gated elsewhere)
import './contrib/inlineCompletions/browser/inlineCompletions.contribution.js';

// Drop or paste into
import './contrib/dropOrPasteInto/browser/dropOrPasteInto.contribution.js';

// Opener
import './contrib/opener/browser/opener.contribution.js';

// Merge / multi-diff (needed for basic git conflict UX when SCM later enabled;
// cheap enough to keep for file compare workflows)
import './contrib/mergeEditor/browser/mergeEditor.contribution.js';
import './contrib/multiDiffEditor/browser/multiDiffEditor.contribution.js';

// Call / type hierarchy (language feature UI — small)
import './contrib/callHierarchy/browser/callHierarchy.contribution.js';
import './contrib/typeHierarchy/browser/typeHierarchy.contribution.js';

// Scroll locking
import './contrib/scrollLocking/browser/scrollLocking.contribution.js';
