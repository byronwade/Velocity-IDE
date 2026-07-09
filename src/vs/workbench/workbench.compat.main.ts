/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

/**
 * Full Compatibility Mode packs — stock VS Code contribution surface.
 * Used for migration testing and extension compatibility verification.
 * Not the default product mode.
 */

import { isPerformanceForkFeatureEnabled } from '../platform/performanceFork/common/performanceForkFeatures.js';

// Telemetry
if (isPerformanceForkFeatureEnabled('workbench.telemetry')) {
	await import('./contrib/telemetry/browser/telemetry.contribution.js');
	await import('./contrib/bracketPairColorizer2Telemetry/browser/bracketPairColorizer2Telemetry.contribution.js');
}

// Notebook / interactive / REPL
if (isPerformanceForkFeatureEnabled('workbench.notebook')) {
	await import('./contrib/notebook/browser/notebook.contribution.js');
}
if (isPerformanceForkFeatureEnabled('workbench.interactive')) {
	await import('./contrib/interactive/browser/interactive.contribution.js');
}
if (isPerformanceForkFeatureEnabled('workbench.replNotebook')) {
	await import('./contrib/replNotebook/browser/repl.contribution.js');
}

// Speech
if (isPerformanceForkFeatureEnabled('workbench.speech')) {
	await import('./contrib/speech/browser/speech.contribution.js');
}

// Chat / inline chat / MCP
if (isPerformanceForkFeatureEnabled('workbench.chat')) {
	await import('./contrib/chat/browser/chat.contribution.js');
	await import('./contrib/chat/browser/chatSessions.contribution.js');
	await import('./contrib/chat/browser/chatContext.contribution.js');
}
if (isPerformanceForkFeatureEnabled('workbench.inlineChat')) {
	await import('./contrib/inlineChat/browser/inlineChat.contribution.js');
}
if (isPerformanceForkFeatureEnabled('workbench.mcp')) {
	await import('./contrib/mcp/browser/mcp.contribution.js');
}

// Testing
if (isPerformanceForkFeatureEnabled('workbench.testing')) {
	await import('./contrib/testing/browser/testing.contribution.js');
}

// Surveys
if (isPerformanceForkFeatureEnabled('workbench.surveys')) {
	await import('./contrib/surveys/browser/nps.contribution.js');
	await import('./contrib/surveys/browser/languageSurveys.contribution.js');
}

// Welcome / walkthroughs
if (isPerformanceForkFeatureEnabled('workbench.welcome')) {
	await import('./contrib/welcomeGettingStarted/browser/gettingStarted.contribution.js');
	await import('./contrib/welcomeWalkthrough/browser/walkThrough.contribution.js');
	await import('./contrib/welcomeViews/common/viewsWelcome.contribution.js');
	await import('./contrib/welcomeViews/common/newFile.contribution.js');
}

// User data sync / edit sessions
if (isPerformanceForkFeatureEnabled('workbench.userDataSync')) {
	await import('./contrib/userDataSync/browser/userDataSync.contribution.js');
}
if (isPerformanceForkFeatureEnabled('workbench.editSessions')) {
	await import('./contrib/editSessions/browser/editSessions.contribution.js');
}

// Remote coding agents / share
if (isPerformanceForkFeatureEnabled('workbench.remoteCodingAgents')) {
	await import('./contrib/remoteCodingAgents/browser/remoteCodingAgents.contribution.js');
}
if (isPerformanceForkFeatureEnabled('workbench.share')) {
	await import('./contrib/share/browser/share.contribution.js');
}

// Edit telemetry
if (isPerformanceForkFeatureEnabled('workbench.editTelemetry')) {
	await import('./contrib/editTelemetry/browser/editTelemetry.contribution.js');
}

// Ensure developer packs are also present in compat
await import('./workbench.developer.main.js');
