#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import path from 'node:path';

function countImports(source) {
	const re = /^\s*import\s+['"][^'"]+['"]/gm;
	return (source.match(re) || []).length;
}

function countDynamicImports(source) {
	const re = /await\s+import\(/g;
	return (source.match(re) || []).length;
}

/** Stock contrib areas that must not appear as static imports in common.main for Core. */
const STOCK_HEAVY = [
	'contrib/telemetry/',
	'contrib/surveys/',
	'contrib/welcomeGettingStarted/',
	'contrib/welcomeWalkthrough/',
	'contrib/chat/',
	'contrib/inlineChat/',
	'contrib/mcp/',
	'contrib/notebook/',
	'contrib/interactive/',
	'contrib/replNotebook/',
	'contrib/testing/',
	'contrib/remoteTunnel/',
	'contrib/remoteCodingAgents/',
	'contrib/userDataSync/',
	'contrib/editSessions/',
	'contrib/editTelemetry/',
	'terminal.all'
];

export async function measureStartup(repoRoot) {
	const commonPath = path.join(repoRoot, 'src/vs/workbench/workbench.common.main.ts');
	const corePath = path.join(repoRoot, 'src/vs/workbench/workbench.core.main.ts');
	const desktopPath = path.join(repoRoot, 'src/vs/workbench/workbench.desktop.main.ts');

	const [common, core, desktop] = await Promise.all([
		readFile(commonPath, 'utf8'),
		readFile(corePath, 'utf8'),
		readFile(desktopPath, 'utf8')
	]);

	const heavyStillStatic = STOCK_HEAVY.filter(p => {
		const re = new RegExp(`import\\s+['"][^'"]*${p.replace(/\//g, '\\/')}[^'"]*['"]`);
		return re.test(common) || re.test(desktop);
	});

	return {
		coldStartToFirstWindowMs: null,
		firstEditorPaintMs: null,
		interactiveMs: null,
		runtimeMeasured: false,
		commonStaticImports: countImports(common),
		coreContributionImportCount: countImports(core),
		desktopDynamicImports: countDynamicImports(desktop),
		disabledStockImportCount: STOCK_HEAVY.length - heavyStillStatic.length,
		heavyStillStatic,
		gatedPacks: ['telemetry', 'welcome', 'chat', 'mcp', 'notebook', 'testing', 'sync'],
		notes: heavyStillStatic.length
			? `WARNING: still statically importing: ${heavyStillStatic.join(', ')}`
			: 'Heavy stock contribs are not static-imported in common/desktop mains (Core path).'
	};
}
