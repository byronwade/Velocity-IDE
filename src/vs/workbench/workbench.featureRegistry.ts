/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

import {
	getPerformanceForkMode,
	isPerformanceForkFeatureEnabled,
	type PerformanceForkFeatureId,
	type PerformanceForkMode,
} from '../../platform/performanceFork/common/performanceForkFeatures.js';

/**
 * Maps workbench contribution packs to performance-fork feature flags.
 * Used by mode-specific entrypoints to decide which side-effect imports to load.
 */

export type WorkbenchFeaturePackId =
	| 'core'
	| 'telemetry'
	| 'surveys'
	| 'welcome'
	| 'chat'
	| 'notebook'
	| 'testing'
	| 'debug'
	| 'scm'
	| 'tasks'
	| 'remote'
	| 'remoteTunnel'
	| 'mcp'
	| 'userDataSync'
	| 'userDataProfiles'
	| 'editSessions'
	| 'searchEditor'
	| 'timeline'
	| 'localHistory'
	| 'webviews'
	| 'processExplorer'
	| 'issueReporter'
	| 'accessibilitySignals'
	| 'share'
	| 'update'
	| 'emmet'
	| 'languageDetection'
	| 'markdown'
	| 'extensionsRecommendations'
	| 'speech'
	| 'authentication'
	| 'comments'
	| 'editTelemetry'
	| 'tags'
	| 'emergencyAlert'
	| 'policyExport'
	| 'terminalExtras'
	| 'extensionGallery';

const PACK_TO_FEATURE: ReadonlyMap<WorkbenchFeaturePackId, PerformanceForkFeatureId | undefined> = new Map([
	['core', undefined],
	['telemetry', 'workbench.telemetry'],
	['surveys', 'workbench.surveys'],
	['welcome', 'workbench.welcome'],
	['chat', 'workbench.chat'],
	['notebook', 'workbench.notebook'],
	['testing', 'workbench.testing'],
	['debug', 'workbench.debug'],
	['scm', 'workbench.scm'],
	['tasks', 'workbench.tasks'],
	['remote', 'workbench.remote'],
	['remoteTunnel', 'workbench.remoteTunnel'],
	['mcp', 'workbench.mcp'],
	['userDataSync', 'workbench.userDataSync'],
	['userDataProfiles', 'workbench.userDataProfiles'],
	['editSessions', 'workbench.editSessions'],
	['searchEditor', 'workbench.searchEditor'],
	['timeline', 'workbench.timeline'],
	['localHistory', 'workbench.localHistory'],
	['webviews', 'workbench.webviews'],
	['processExplorer', 'workbench.processExplorer'],
	['issueReporter', 'workbench.issueReporter'],
	['accessibilitySignals', 'workbench.accessibilitySignals'],
	['share', 'workbench.share'],
	['update', 'workbench.update'],
	['emmet', 'workbench.emmet'],
	['languageDetection', 'workbench.languageDetection'],
	['markdown', 'workbench.markdownPreview'],
	['extensionsRecommendations', 'workbench.extensionsRecommendations'],
	['speech', 'workbench.speech'],
	['authentication', 'workbench.authentication'],
	['comments', 'workbench.comments'],
	['editTelemetry', 'workbench.editTelemetry'],
	['tags', 'workbench.tags'],
	['emergencyAlert', 'workbench.emergencyAlert'],
	['policyExport', 'workbench.policyExport'],
	['terminalExtras', 'terminal.chatContrib'],
	['extensionGallery', 'workbench.extensionGallery'],
]);

export function isWorkbenchFeaturePackEnabled(pack: WorkbenchFeaturePackId): boolean {
	const feature = PACK_TO_FEATURE.get(pack);
	if (!feature) {
		return true; // core pack always enabled
	}
	return isPerformanceForkFeatureEnabled(feature);
}

export function getEnabledWorkbenchFeaturePacks(): WorkbenchFeaturePackId[] {
	const packs: WorkbenchFeaturePackId[] = [];
	for (const pack of PACK_TO_FEATURE.keys()) {
		if (isWorkbenchFeaturePackEnabled(pack)) {
			packs.push(pack);
		}
	}
	return packs;
}

export function describeWorkbenchFeatureRegistry(): {
	mode: PerformanceForkMode;
	enabledPacks: WorkbenchFeaturePackId[];
	disabledPacks: WorkbenchFeaturePackId[];
} {
	const mode = getPerformanceForkMode();
	const enabledPacks: WorkbenchFeaturePackId[] = [];
	const disabledPacks: WorkbenchFeaturePackId[] = [];
	for (const pack of PACK_TO_FEATURE.keys()) {
		if (isWorkbenchFeaturePackEnabled(pack)) {
			enabledPacks.push(pack);
		} else {
			disabledPacks.push(pack);
		}
	}
	return { mode, enabledPacks, disabledPacks };
}
