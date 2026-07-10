/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

/**
 * Performance Fork feature gating.
 *
 * Resolution order (later wins):
 * 1. Build-time / product.json defaults for the active runtime mode
 * 2. Environment variables (`VSCODE_PERF_FORK_*`)
 * 3. Command-line overrides (`--perf-fork-mode`, `--perf-fork-enable`, `--perf-fork-disable`)
 * 4. User settings overrides (applied after configuration is available)
 *
 * This module is intentionally dependency-light so it can run before the
 * workbench DI container exists (entrypoint selection).
 */

export type PerformanceForkMode = 'core' | 'developer' | 'compat';

export type PerformanceForkFeatureId =
	| 'workbench.telemetry'
	| 'workbench.surveys'
	| 'workbench.welcome'
	| 'workbench.chat'
	| 'workbench.inlineChat'
	| 'workbench.notebook'
	| 'workbench.interactive'
	| 'workbench.replNotebook'
	| 'workbench.testing'
	| 'workbench.remote'
	| 'workbench.remoteTunnel'
	| 'workbench.remoteCodingAgents'
	| 'workbench.mcp'
	| 'workbench.userDataSync'
	| 'workbench.userDataProfiles'
	| 'workbench.editSessions'
	| 'workbench.debug'
	| 'workbench.tasks'
	| 'workbench.scm'
	| 'workbench.searchEditor'
	| 'workbench.timeline'
	| 'workbench.localHistory'
	| 'workbench.webviews'
	| 'workbench.processExplorer'
	| 'workbench.issueReporter'
	| 'workbench.accessibilitySignals'
	| 'workbench.share'
	| 'workbench.update'
	| 'workbench.emmet'
	| 'workbench.languageDetection'
	| 'workbench.markdownPreview'
	| 'workbench.extensionsRecommendations'
	| 'workbench.extensionTips'
	| 'workbench.extensionGallery'
	| 'workbench.speech'
	| 'workbench.authentication'
	| 'workbench.comments'
	| 'workbench.editTelemetry'
	| 'workbench.tags'
	| 'workbench.emergencyAlert'
	| 'workbench.policyExport'
	| 'terminal.shellIntegration'
	| 'terminal.gpuAcceleration'
	| 'terminal.imageAddon'
	| 'terminal.ligaturesAddon'
	| 'terminal.serializeAddon'
	| 'terminal.searchAddon'
	| 'terminal.chatContrib'
	| 'extensions.activationBudget'
	| 'extensions.permissions';

export const PERFORMANCE_FORK_FEATURE_IDS: readonly PerformanceForkFeatureId[] = [
	'workbench.telemetry',
	'workbench.surveys',
	'workbench.welcome',
	'workbench.chat',
	'workbench.inlineChat',
	'workbench.notebook',
	'workbench.interactive',
	'workbench.replNotebook',
	'workbench.testing',
	'workbench.remote',
	'workbench.remoteTunnel',
	'workbench.remoteCodingAgents',
	'workbench.mcp',
	'workbench.userDataSync',
	'workbench.userDataProfiles',
	'workbench.editSessions',
	'workbench.debug',
	'workbench.tasks',
	'workbench.scm',
	'workbench.searchEditor',
	'workbench.timeline',
	'workbench.localHistory',
	'workbench.webviews',
	'workbench.processExplorer',
	'workbench.issueReporter',
	'workbench.accessibilitySignals',
	'workbench.share',
	'workbench.update',
	'workbench.emmet',
	'workbench.languageDetection',
	'workbench.markdownPreview',
	'workbench.extensionsRecommendations',
	'workbench.extensionTips',
	'workbench.extensionGallery',
	'workbench.speech',
	'workbench.authentication',
	'workbench.comments',
	'workbench.editTelemetry',
	'workbench.tags',
	'workbench.emergencyAlert',
	'workbench.policyExport',
	'terminal.shellIntegration',
	'terminal.gpuAcceleration',
	'terminal.imageAddon',
	'terminal.ligaturesAddon',
	'terminal.serializeAddon',
	'terminal.searchAddon',
	'terminal.chatContrib',
	'extensions.activationBudget',
	'extensions.permissions',
];

export interface IPerformanceForkProductConfig {
	readonly mode?: PerformanceForkMode;
	readonly features?: Partial<Record<PerformanceForkFeatureId, boolean>>;
}

/**
 * Core Mode: absolute minimum IDE surface.
 * Developer Mode: Core + SCM/debug/tasks/marketplace/etc.
 * Compat Mode: stock VS Code contribution surface.
 */
const CORE_DISABLED: ReadonlySet<PerformanceForkFeatureId> = new Set<PerformanceForkFeatureId>([
	'workbench.telemetry',
	'workbench.surveys',
	'workbench.welcome',
	'workbench.chat',
	'workbench.inlineChat',
	'workbench.notebook',
	'workbench.interactive',
	'workbench.replNotebook',
	'workbench.testing',
	'workbench.remote',
	'workbench.remoteTunnel',
	'workbench.remoteCodingAgents',
	'workbench.mcp',
	'workbench.userDataSync',
	'workbench.userDataProfiles',
	'workbench.editSessions',
	'workbench.debug',
	'workbench.tasks',
	'workbench.scm',
	'workbench.searchEditor',
	'workbench.timeline',
	'workbench.localHistory',
	'workbench.processExplorer',
	'workbench.issueReporter',
	'workbench.accessibilitySignals',
	'workbench.share',
	'workbench.update',
	'workbench.emmet',
	'workbench.languageDetection',
	'workbench.markdownPreview',
	'workbench.extensionsRecommendations',
	'workbench.extensionTips',
	'workbench.extensionGallery',
	'workbench.speech',
	'workbench.authentication',
	'workbench.comments',
	'workbench.editTelemetry',
	'workbench.tags',
	'workbench.emergencyAlert',
	'workbench.policyExport',
	'terminal.shellIntegration',
	'terminal.imageAddon',
	'terminal.ligaturesAddon',
	'terminal.serializeAddon',
	'terminal.chatContrib',
]);

const DEVELOPER_DISABLED: ReadonlySet<PerformanceForkFeatureId> = new Set<PerformanceForkFeatureId>([
	'workbench.telemetry',
	'workbench.surveys',
	'workbench.welcome',
	'workbench.chat',
	'workbench.inlineChat',
	'workbench.notebook',
	'workbench.interactive',
	'workbench.replNotebook',
	'workbench.testing', // opt-in even in developer mode
	'workbench.remoteTunnel',
	'workbench.remoteCodingAgents',
	'workbench.mcp',
	'workbench.userDataSync',
	'workbench.editSessions',
	'workbench.share',
	'workbench.extensionsRecommendations',
	'workbench.extensionTips',
	'workbench.speech',
	'workbench.editTelemetry',
	'workbench.tags',
	'workbench.emergencyAlert',
	'terminal.imageAddon',
	'terminal.ligaturesAddon',
	'terminal.chatContrib',
]);

export interface IPerformanceForkResolvedState {
	readonly mode: PerformanceForkMode;
	readonly features: ReadonlyMap<PerformanceForkFeatureId, boolean>;
}

let resolvedState: IPerformanceForkResolvedState | undefined;
let userSettingOverrides: Partial<Record<PerformanceForkFeatureId, boolean>> = {};

function readEnv(name: string): string | undefined {
	try {
		const processGlobal = (globalThis as { process?: { env?: Record<string, string | undefined> } }).process;
		return processGlobal?.env?.[name];
	} catch {
		return undefined;
	}
}

function parseMode(value: string | undefined | null): PerformanceForkMode | undefined {
	if (!value) {
		return undefined;
	}
	const normalized = value.trim().toLowerCase();
	if (normalized === 'core' || normalized === 'developer' || normalized === 'compat') {
		return normalized;
	}
	return undefined;
}

function parseFeatureList(value: string | undefined): PerformanceForkFeatureId[] {
	if (!value) {
		return [];
	}
	return value
		.split(',')
		.map(part => part.trim())
		.filter((part): part is PerformanceForkFeatureId => (PERFORMANCE_FORK_FEATURE_IDS as readonly string[]).includes(part));
}

function readCliArg(name: string): string | undefined {
	try {
		// Electron renderer: prefer vscode process globals when present
		const vscodeProcess = (globalThis as { vscode?: { process?: { argv?: string[]; env?: Record<string, string | undefined> } } }).vscode?.process;
		const processGlobal = (globalThis as { process?: { argv?: string[] } }).process;
		const argv = vscodeProcess?.argv ?? processGlobal?.argv;
		if (!argv) {
			return undefined;
		}
		const exact = `--${name}`;
		const prefix = `--${name}=`;
		for (let i = 0; i < argv.length; i++) {
			const arg = argv[i];
			if (arg === exact) {
				return argv[i + 1];
			}
			if (arg?.startsWith(prefix)) {
				return arg.slice(prefix.length);
			}
		}
	} catch {
		// ignore
	}
	return undefined;
}

function readCliFlag(name: string): boolean {
	try {
		const processGlobal = (globalThis as { process?: { argv?: string[] } }).process;
		const argv = processGlobal?.argv;
		if (!argv) {
			return false;
		}
		return argv.includes(`--${name}`);
	} catch {
		return false;
	}
}

function defaultsForMode(mode: PerformanceForkMode): Map<PerformanceForkFeatureId, boolean> {
	const disabled = mode === 'core' ? CORE_DISABLED : mode === 'developer' ? DEVELOPER_DISABLED : undefined;
	const map = new Map<PerformanceForkFeatureId, boolean>();
	for (const id of PERFORMANCE_FORK_FEATURE_IDS) {
		if (!disabled) {
			map.set(id, true);
			continue;
		}
		// Core keeps webviews registered (extension API) but prefers lazy use.
		if (id === 'workbench.webviews') {
			map.set(id, true);
			continue;
		}
		if (id === 'terminal.gpuAcceleration' || id === 'terminal.searchAddon') {
			map.set(id, mode !== 'core' ? true : false);
			continue;
		}
		if (id === 'extensions.activationBudget' || id === 'extensions.permissions') {
			map.set(id, mode !== 'compat');
			continue;
		}
		map.set(id, !disabled.has(id));
	}
	return map;
}

function readProductConfig(): IPerformanceForkProductConfig | undefined {
	try {
		const product = (globalThis as { _VSCODE_PRODUCT_JSON?: { performanceFork?: IPerformanceForkProductConfig } })._VSCODE_PRODUCT_JSON;
		return product?.performanceFork;
	} catch {
		return undefined;
	}
}

/**
 * Resolve the active performance-fork mode and feature map.
 * Safe to call before DI; caches the first resolution unless `force` is set.
 */
export function resolvePerformanceForkState(force = false): IPerformanceForkResolvedState {
	if (resolvedState && !force) {
		return resolvedState;
	}

	const productConfig = readProductConfig();
	const mode =
		parseMode(readCliArg('perf-fork-mode')) ??
		parseMode(readEnv('VSCODE_PERF_FORK_MODE')) ??
		parseMode(productConfig?.mode) ??
		'core';

	const features = defaultsForMode(mode);

	// product.json feature overrides
	if (productConfig?.features) {
		for (const [key, value] of Object.entries(productConfig.features)) {
			if ((PERFORMANCE_FORK_FEATURE_IDS as readonly string[]).includes(key) && typeof value === 'boolean') {
				features.set(key as PerformanceForkFeatureId, value);
			}
		}
	}

	// Environment overrides: VSCODE_PERF_FORK_ENABLE / VSCODE_PERF_FORK_DISABLE (comma-separated)
	for (const id of parseFeatureList(readEnv('VSCODE_PERF_FORK_ENABLE'))) {
		features.set(id, true);
	}
	for (const id of parseFeatureList(readEnv('VSCODE_PERF_FORK_DISABLE'))) {
		features.set(id, false);
	}

	// CLI overrides
	for (const id of parseFeatureList(readCliArg('perf-fork-enable'))) {
		features.set(id, true);
	}
	for (const id of parseFeatureList(readCliArg('perf-fork-disable'))) {
		features.set(id, false);
	}

	// Convenience: --disable-telemetry always wins for telemetry feature
	if (readCliFlag('disable-telemetry') || readEnv('VSCODE_DISABLE_TELEMETRY') === '1') {
		features.set('workbench.telemetry', false);
		features.set('workbench.editTelemetry', false);
		features.set('workbench.tags', false);
	}

	// User setting overrides applied later via applyPerformanceForkSettingOverrides
	for (const [key, value] of Object.entries(userSettingOverrides)) {
		if ((PERFORMANCE_FORK_FEATURE_IDS as readonly string[]).includes(key) && typeof value === 'boolean') {
			features.set(key as PerformanceForkFeatureId, value);
		}
	}

	resolvedState = { mode, features };
	return resolvedState;
}

export function getPerformanceForkMode(): PerformanceForkMode {
	return resolvePerformanceForkState().mode;
}

export function isPerformanceForkFeatureEnabled(feature: PerformanceForkFeatureId): boolean {
	return resolvePerformanceForkState().features.get(feature) === true;
}

/**
 * Apply user-setting overrides after configuration service is available.
 * Does not unload already-imported contributions; affects runtime gates and future checks.
 */
export function applyPerformanceForkSettingOverrides(overrides: Partial<Record<PerformanceForkFeatureId, boolean>>): void {
	userSettingOverrides = { ...userSettingOverrides, ...overrides };
	resolvePerformanceForkState(true);
}

export function getPerformanceForkSnapshot(): {
	mode: PerformanceForkMode;
	enabled: PerformanceForkFeatureId[];
	disabled: PerformanceForkFeatureId[];
} {
	const state = resolvePerformanceForkState();
	const enabled: PerformanceForkFeatureId[] = [];
	const disabled: PerformanceForkFeatureId[] = [];
	for (const id of PERFORMANCE_FORK_FEATURE_IDS) {
		if (state.features.get(id)) {
			enabled.push(id);
		} else {
			disabled.push(id);
		}
	}
	return { mode: state.mode, enabled, disabled };
}

/**
 * Default settings applied for Focus Core / Core Mode first-run layout.
 * Registered via configuration default overrides — does not delete stock settings.
 */
export function getPerformanceForkDefaultSettings(mode: PerformanceForkMode = getPerformanceForkMode()): Record<string, unknown> {
	if (mode === 'compat') {
		return {};
	}

	const settings: Record<string, unknown> = {
		'telemetry.telemetryLevel': 'off',
		'telemetry.feedback.enabled': false,
		'workbench.startupEditor': 'none',
		'workbench.welcomePage.walkthroughs.openOnInstall': false,
		'workbench.tips.enabled': false,
		'extensions.ignoreRecommendations': true,
		'extensions.showRecommendationsOnlyOnDemand': true,
		'update.mode': mode === 'core' ? 'none' : 'manual',
		'workbench.activityBar.location': mode === 'core' ? 'hidden' : 'top',
		'workbench.statusBar.visible': true,
		'workbench.sideBar.location': 'left',
		'workbench.layoutControl.enabled': false,
		'window.commandCenter': false,
		'chat.commandCenter.enabled': false,
		'workbench.editor.enablePreview': true,
		'explorer.decorations.badges': false,
		'problems.decorations.enabled': mode !== 'core',
		'terminal.integrated.shellIntegration.enabled': mode !== 'core',
		'terminal.integrated.enableImages': false,
		'terminal.integrated.fontLigatures.enabled': false,
		'terminal.integrated.gpuAcceleration': mode === 'core' ? 'off' : 'auto',
		'workbench.reduceMotion': 'on',
		'extensions.autoCheckUpdates': false,
		'extensions.autoUpdate': false,
		'git.autoRepositoryDetection': mode === 'core' ? false : true,
		'scm.alwaysShowActions': false,
		'breadcrumbs.enabled': mode !== 'core',
		'editor.minimap.enabled': false,
		'editor.stickyScroll.enabled': false,
		'editor.guides.bracketPairs': false,
		'workbench.colorTheme': 'Default Light Modern',
		'performanceFork.mode': mode,
	};

	if (mode === 'core') {
		settings['workbench.panel.opensMaximized'] = 'never';
		settings['zenMode.hideActivityBar'] = true;
		settings['zenMode.hideStatusBar'] = false;
		settings['zenMode.centerLayout'] = false;
	}

	return settings;
}
