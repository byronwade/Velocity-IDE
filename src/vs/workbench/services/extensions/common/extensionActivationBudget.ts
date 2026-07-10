/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

import { isPerformanceForkFeatureEnabled } from '../../../platform/performanceFork/common/performanceForkFeatures.js';

/**
 * Extension activation performance tiers for the performance fork.
 * Full permission enforcement is phased; this module defines the API boundary
 * and startup-budget helpers used by the extension service.
 */

export const enum ExtensionActivationTier {
	/** Always allowed to activate early (built-in syntax / critical). */
	TrustedCore = 0,
	/** Activate after idle / first paint. */
	Lazy = 1,
	/** Activate only on explicit user action or command. */
	OnDemand = 2,
	/** Activate on workspace folder open / file type match after idle. */
	WorkspaceActivated = 3,
	/** Never activate. */
	Blocked = 4,
}

export type ExtensionPermission =
	| 'filesystem'
	| 'shell'
	| 'network'
	| 'environment'
	| 'credentials'
	| 'workspaceScan'
	| 'terminalIntegration'
	| 'webview'
	| 'clipboard'
	| 'authentication';

export interface IExtensionActivationBudgetDecision {
	readonly allowed: boolean;
	readonly tier: ExtensionActivationTier;
	readonly reason: string;
	readonly deferUntilIdle: boolean;
}

export interface IExtensionActivationDiagnostics {
	readonly extensionId: string;
	readonly activationEvent: string;
	readonly startedAt: number;
	readonly finishedAt?: number;
	readonly durationMs?: number;
	readonly reason: string;
	readonly tier: ExtensionActivationTier;
}

const activationLog: IExtensionActivationDiagnostics[] = [];

/**
 * Whether the activation budget system is enforcing deferred activation.
 */
export function isExtensionActivationBudgetEnabled(): boolean {
	return isPerformanceForkFeatureEnabled('extensions.activationBudget');
}

/**
 * Decide whether an extension may activate during the current startup phase.
 * Conservative default: block non-core activations until after restore/idle
 * when the budget feature is enabled.
 */
export function evaluateExtensionActivationBudget(options: {
	readonly extensionId: string;
	readonly activationEvent: string;
	readonly isBuiltin: boolean;
	readonly startupFinished: boolean;
	readonly allowlist: readonly string[];
	readonly tier?: ExtensionActivationTier;
}): IExtensionActivationBudgetDecision {
	const tier = options.tier ?? (options.isBuiltin ? ExtensionActivationTier.TrustedCore : ExtensionActivationTier.Lazy);

	if (!isExtensionActivationBudgetEnabled()) {
		return { allowed: true, tier, reason: 'budget-disabled', deferUntilIdle: false };
	}

	if (tier === ExtensionActivationTier.Blocked) {
		return { allowed: false, tier, reason: 'blocked-tier', deferUntilIdle: false };
	}

	if (options.allowlist.length > 0 && !options.allowlist.includes(options.extensionId) && !options.isBuiltin) {
		return { allowed: false, tier: ExtensionActivationTier.Blocked, reason: 'not-in-allowlist', deferUntilIdle: false };
	}

	if (tier === ExtensionActivationTier.TrustedCore) {
		return { allowed: true, tier, reason: 'trusted-core', deferUntilIdle: false };
	}

	if (!options.startupFinished) {
		if (options.activationEvent === 'onStartupFinished') {
			return { allowed: true, tier, reason: 'startup-finished-event', deferUntilIdle: false };
		}
		if (options.activationEvent === '*') {
			return { allowed: false, tier, reason: 'star-deferred-until-idle', deferUntilIdle: true };
		}
		return { allowed: false, tier, reason: 'deferred-until-idle', deferUntilIdle: true };
	}

	if (tier === ExtensionActivationTier.OnDemand) {
		const onDemandOk = options.activationEvent.startsWith('onCommand:') || options.activationEvent.startsWith('onView:');
		return { allowed: onDemandOk, tier, reason: onDemandOk ? 'on-demand' : 'waiting-for-user-action', deferUntilIdle: !onDemandOk };
	}

	return { allowed: true, tier, reason: 'post-startup', deferUntilIdle: false };
}

export function recordExtensionActivation(entry: IExtensionActivationDiagnostics): void {
	activationLog.push(entry);
	if (activationLog.length > 500) {
		activationLog.shift();
	}
}

export function getExtensionActivationDiagnostics(): readonly IExtensionActivationDiagnostics[] {
	return activationLog;
}

/**
 * High-risk permission categories. Enforcement hooks will be wired into
 * filesystem / terminal / network / secrets call sites in later passes.
 */
export const HIGH_RISK_EXTENSION_PERMISSIONS: readonly ExtensionPermission[] = [
	'shell',
	'network',
	'credentials',
	'environment',
	'workspaceScan',
];
