#!/usr/bin/env node
/*---------------------------------------------------------------------------------------------
 * Performance fork measurement harness entry.
 * Usage: npm run perf-fork
 *--------------------------------------------------------------------------------------------*/

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '../..');
const outDir = path.join(repoRoot, '.perf-fork');

async function load(mod) {
	return import(pathToFileURL(path.join(__dirname, mod)).href);
}

function nowIso() {
	return new Date().toISOString();
}

async function main() {
	await mkdir(outDir, { recursive: true });

	const startup = await (await load('./startup.mjs')).measureStartup(repoRoot);
	const memory = await (await load('./memory.mjs')).measureMemory(repoRoot);
	const terminal = await (await load('./terminal.mjs')).measureTerminal(repoRoot);
	const extensions = await (await load('./extension-activation.mjs')).measureExtensionActivation(repoRoot);
	const bundle = await (await load('./bundle-size.mjs')).measureBundleSize(repoRoot);

	const report = {
		timestamp: nowIso(),
		repoRoot,
		mode: process.env.VSCODE_PERF_FORK_MODE || 'core',
		metrics: {
			startup,
			memory,
			terminal,
			extensions,
			bundle
		}
	};

	const latestPath = path.join(outDir, 'latest.json');
	const historyPath = path.join(outDir, 'history.json');
	const reportPath = path.join(outDir, 'report.md');

	await writeFile(latestPath, JSON.stringify(report, null, 2));

	let history = [];
	if (existsSync(historyPath)) {
		try {
			history = JSON.parse(await readFile(historyPath, 'utf8'));
			if (!Array.isArray(history)) {
				history = [];
			}
		} catch {
			history = [];
		}
	}
	history.push({
		timestamp: report.timestamp,
		mode: report.mode,
		startupContributionImports: startup.coreContributionImportCount,
		disabledStockImports: startup.disabledStockImportCount,
		builtinMarketplaceExtensions: extensions.marketplaceBuiltInCount,
		workbenchMainBytes: bundle.workbenchEntrypointBytes
	});
	if (history.length > 100) {
		history = history.slice(-100);
	}
	await writeFile(historyPath, JSON.stringify(history, null, 2));

	const md = [
		'# Performance Fork Report',
		'',
		`Generated: ${report.timestamp}`,
		`Mode: \`${report.mode}\``,
		'',
		'## Startup (static analysis)',
		'',
		`- Core contribution imports: **${startup.coreContributionImportCount}**`,
		`- Stock contrib imports removed from common.main: **${startup.disabledStockImportCount}**`,
		`- Feature packs gated: ${startup.gatedPacks.join(', ') || '(none listed)'}`,
		`- Notes: ${startup.notes}`,
		'',
		'## Memory',
		'',
		`- Status: ${memory.status}`,
		`- ${memory.notes}`,
		'',
		'## Terminal',
		'',
		`- Lean terminal entry present: **${terminal.leanEntrypointPresent}**`,
		`- Chat/voice contribs in core entry: **${terminal.chatInCore}**`,
		`- ${terminal.notes}`,
		'',
		'## Extensions',
		'',
		`- Marketplace built-ins (product.json): **${extensions.marketplaceBuiltInCount}**`,
		`- Local extension folders: **${extensions.localExtensionCount}**`,
		`- Activation budget module: **${extensions.activationBudgetPresent}**`,
		'',
		'## Bundle',
		'',
		`- workbench.desktop.main.ts bytes: **${bundle.workbenchEntrypointBytes}**`,
		`- workbench.core.main.ts bytes: **${bundle.coreEntrypointBytes}**`,
		`- Compiled out present: **${bundle.compiledOutPresent}**`,
		`- ${bundle.notes}`,
		'',
		'## Next steps',
		'',
		'- Run a cold boot with `--prof-startup` once Electron deps are installed for runtime timings.',
		'- Compare history in `.perf-fork/history.json`.',
		''
	].join('\n');

	await writeFile(reportPath, md);
	console.log(`perf-fork: wrote ${latestPath}`);
	console.log(`perf-fork: wrote ${reportPath}`);
	console.log(md);
}

main().catch(err => {
	console.error(err);
	process.exit(1);
});
