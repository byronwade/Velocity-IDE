#!/usr/bin/env node
import { readFile, stat } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';

async function fileBytes(p) {
	if (!existsSync(p)) {
		return null;
	}
	const s = await stat(p);
	return s.size;
}

export async function measureBundleSize(repoRoot) {
	const desktopTs = path.join(repoRoot, 'src/vs/workbench/workbench.desktop.main.ts');
	const coreTs = path.join(repoRoot, 'src/vs/workbench/workbench.core.main.ts');
	const compiled = path.join(repoRoot, 'out/vs/workbench/workbench.desktop.main.js');
	const minified = path.join(repoRoot, 'out-vscode-min/vs/workbench/workbench.desktop.main.js');

	return {
		workbenchEntrypointBytes: await fileBytes(desktopTs),
		coreEntrypointBytes: await fileBytes(coreTs),
		compiledOutPresent: existsSync(path.join(repoRoot, 'out')),
		compiledWorkbenchBytes: await fileBytes(compiled),
		minifiedWorkbenchBytes: await fileBytes(minified),
		notes: existsSync(minified)
			? 'Minified bundle detected (out-vscode-min).'
			: 'Source entrypoint sizes only until minify-vscode is run.'
	};
}
