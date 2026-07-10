#!/usr/bin/env node
import { readFile, readdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';

export async function measureExtensionActivation(repoRoot) {
	const product = JSON.parse(await readFile(path.join(repoRoot, 'product.json'), 'utf8'));
	const extensionsDir = path.join(repoRoot, 'extensions');
	const entries = await readdir(extensionsDir, { withFileTypes: true });
	const localExtensionCount = entries.filter(e => e.isDirectory() && !e.name.startsWith('.')).length;

	const budgetPath = path.join(repoRoot, 'src/vs/workbench/services/extensions/common/extensionActivationBudget.ts');

	return {
		activationTimeMs: null,
		runtimeMeasured: false,
		marketplaceBuiltInCount: Array.isArray(product.builtInExtensions) ? product.builtInExtensions.length : 0,
		localExtensionCount,
		activationBudgetPresent: existsSync(budgetPath),
		performanceForkMode: product.performanceFork?.mode ?? null
	};
}
