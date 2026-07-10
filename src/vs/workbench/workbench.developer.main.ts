/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

/**
 * Developer Mode packs — loaded on top of Core Mode.
 * Adds SCM, debug, tasks, search editor, timeline, local history, update,
 * emmet, language detection, markdown, authentication, comments, extension gallery UX.
 */

import { isPerformanceForkFeatureEnabled } from '../platform/performanceFork/common/performanceForkFeatures.js';

// SCM / Git surface
if (isPerformanceForkFeatureEnabled('workbench.scm')) {
	await import('./contrib/scm/browser/scm.contribution.js');
}

// Debug
if (isPerformanceForkFeatureEnabled('workbench.debug')) {
	await import('./contrib/debug/browser/debug.contribution.js');
	await import('./contrib/debug/browser/debugEditorContribution.js');
	await import('./contrib/debug/browser/breakpointEditorContribution.js');
	await import('./contrib/debug/browser/callStackEditorContribution.js');
	await import('./contrib/debug/browser/repl.js');
	await import('./contrib/debug/browser/debugViewlet.js');
}

// Tasks
if (isPerformanceForkFeatureEnabled('workbench.tasks')) {
	await import('./contrib/tasks/browser/task.contribution.js');
}

// Search editor
if (isPerformanceForkFeatureEnabled('workbench.searchEditor')) {
	await import('./contrib/searchEditor/browser/searchEditor.contribution.js');
}

// Timeline / local history
if (isPerformanceForkFeatureEnabled('workbench.timeline')) {
	await import('./contrib/timeline/browser/timeline.contribution.js');
}
if (isPerformanceForkFeatureEnabled('workbench.localHistory')) {
	await import('./contrib/localHistory/browser/localHistory.contribution.js');
}

// Process explorer
if (isPerformanceForkFeatureEnabled('workbench.processExplorer')) {
	await import('./contrib/processExplorer/browser/processExplorer.contribution.js');
}

// Update
if (isPerformanceForkFeatureEnabled('workbench.update')) {
	await import('./contrib/update/browser/update.contribution.js');
}

// Emmet
if (isPerformanceForkFeatureEnabled('workbench.emmet')) {
	await import('./contrib/emmet/browser/emmet.contribution.js');
}

// Markdown
if (isPerformanceForkFeatureEnabled('workbench.markdownPreview')) {
	await import('./contrib/markdown/browser/markdown.contribution.js');
}

// Language detection
if (isPerformanceForkFeatureEnabled('workbench.languageDetection')) {
	await import('./contrib/languageDetection/browser/languageDetection.contribution.js');
}

// Authentication
if (isPerformanceForkFeatureEnabled('workbench.authentication')) {
	await import('./contrib/authentication/browser/authentication.contribution.js');
}

// Comments
if (isPerformanceForkFeatureEnabled('workbench.comments')) {
	await import('./contrib/comments/browser/comments.contribution.js');
}

// User data profiles (lightweight profile switching without sync)
if (isPerformanceForkFeatureEnabled('workbench.userDataProfiles')) {
	await import('./contrib/userDataProfile/browser/userDataProfile.contribution.js');
}

// Remote (SSH/containers explorer — optional in developer)
if (isPerformanceForkFeatureEnabled('workbench.remote')) {
	await import('./contrib/remote/common/remote.contribution.js');
	await import('./contrib/remote/browser/remote.contribution.js');
}

// Extra terminal contribs (chat/voice) — only when explicitly enabled.
// Core already loaded terminal.core.js; do not re-import terminal.all.js.
if (isPerformanceForkFeatureEnabled('terminal.chatContrib')) {
	await import('./contrib/terminalContrib/chat/browser/terminal.chat.contribution.js');
	await import('./contrib/terminalContrib/chatAgentTools/browser/terminal.chatAgentTools.contribution.js');
	await import('./contrib/terminalContrib/chat/browser/terminal.initialHint.contribution.js');
	await import('./contrib/terminalContrib/voice/browser/terminal.voice.contribution.js');
}

// Accessibility signals (only when explicitly enabled)
if (isPerformanceForkFeatureEnabled('workbench.accessibilitySignals')) {
	await import('./contrib/accessibilitySignals/browser/accessibilitySignal.contribution.js');
}

// Testing — opt-in even in developer mode
if (isPerformanceForkFeatureEnabled('workbench.testing')) {
	await import('./contrib/testing/browser/testing.contribution.js');
}
