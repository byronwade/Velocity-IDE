/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

import { localize } from '../../../nls.js';
import { Registry } from '../../../platform/registry/common/platform.js';
import { Extensions as ConfigurationExtensions, IConfigurationRegistry } from '../../../platform/configuration/common/configurationRegistry.js';
import {
	PERFORMANCE_FORK_FEATURE_IDS,
	applyPerformanceForkSettingOverrides,
	getPerformanceForkDefaultSettings,
	getPerformanceForkMode,
	getPerformanceForkSnapshot,
	type PerformanceForkFeatureId,
} from '../../../platform/performanceFork/common/performanceForkFeatures.js';
import { IWorkbenchContribution, WorkbenchPhase, registerWorkbenchContribution2 } from '../../common/contributions.js';
import { IConfigurationService } from '../../../platform/configuration/common/configuration.js';
import { ILogService } from '../../../platform/log/common/log.js';
import { Disposable } from '../../../base/common/lifecycle.js';

const configurationRegistry = Registry.as<IConfigurationRegistry>(ConfigurationExtensions.Configuration);

configurationRegistry.registerConfiguration({
	id: 'performanceFork',
	order: 1,
	title: localize('performanceForkConfigurationTitle', "Performance Fork"),
	type: 'object',
	properties: {
		'performanceFork.mode': {
			type: 'string',
			enum: ['core', 'developer', 'compat'],
			enumDescriptions: [
				localize('performanceFork.mode.core', "Minimal IDE: editor, files, search, terminal. Heavy features gated off."),
				localize('performanceFork.mode.developer', "Core plus SCM, debug, tasks, marketplace, language tooling."),
				localize('performanceFork.mode.compat', "Near-stock VS Code contribution surface for compatibility testing.")
			],
			default: getPerformanceForkMode(),
			description: localize('performanceFork.mode', "Runtime product mode for the performance fork. Restart required after change for full effect on contribution loading."),
			tags: ['performance', 'experimental']
		},
		'performanceFork.disableExtensionsOnStartup': {
			type: 'boolean',
			default: getPerformanceForkMode() === 'core',
			description: localize('performanceFork.disableExtensionsOnStartup', "When enabled, extensions do not activate until after first editor paint / idle (activation budget)."),
			tags: ['performance']
		},
		'performanceFork.extensionAllowlist': {
			type: 'array',
			items: { type: 'string' },
			default: [],
			description: localize('performanceFork.extensionAllowlist', "When non-empty, only these extension IDs may activate (plus built-in core syntax extensions)."),
			tags: ['performance']
		},
		'performanceFork.features': {
			type: 'object',
			additionalProperties: { type: 'boolean' },
			default: {},
			markdownDescription: localize('performanceFork.features', "Per-feature overrides. Known ids: `{0}`", PERFORMANCE_FORK_FEATURE_IDS.join('`, `')),
			tags: ['performance']
		}
	}
});

// Apply Focus Core default settings for non-compat modes
const defaultOverrides = getPerformanceForkDefaultSettings();
if (Object.keys(defaultOverrides).length > 0) {
	configurationRegistry.registerDefaultConfigurations([{ overrides: defaultOverrides }]);
}

class PerformanceForkConfigurationContribution extends Disposable implements IWorkbenchContribution {

	static readonly ID = 'workbench.contrib.performanceForkConfiguration';

	constructor(
		@IConfigurationService configurationService: IConfigurationService,
		@ILogService logService: ILogService,
	) {
		super();

		const apply = () => {
			const features = configurationService.getValue<Partial<Record<PerformanceForkFeatureId, boolean>>>('performanceFork.features') ?? {};
			applyPerformanceForkSettingOverrides(features);
			const snapshot = getPerformanceForkSnapshot();
			logService.info(`[perf-fork] active mode=${snapshot.mode}, enabled=${snapshot.enabled.length}, disabled=${snapshot.disabled.length}`);
		};

		apply();
		this._register(configurationService.onDidChangeConfiguration(e => {
			if (e.affectsConfiguration('performanceFork.features') || e.affectsConfiguration('performanceFork.mode')) {
				apply();
			}
		}));
	}
}

registerWorkbenchContribution2(PerformanceForkConfigurationContribution.ID, PerformanceForkConfigurationContribution, WorkbenchPhase.BlockStartup);
