#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';

export async function measureTerminal(repoRoot) {
	const leanPath = path.join(repoRoot, 'src/vs/workbench/contrib/terminal/terminal.core.ts');
	const leanEntrypointPresent = existsSync(leanPath);
	let chatInCore = false;
	if (leanEntrypointPresent) {
		const src = await readFile(leanPath, 'utf8');
		chatInCore = /terminalContrib\/chat/.test(src) || /terminal\.voice/.test(src);
	}

	return {
		openTimeMs: null,
		runtimeMeasured: false,
		leanEntrypointPresent,
		chatInCore,
		notes: leanEntrypointPresent && !chatInCore
			? 'Lean terminal.core.ts present without chat/voice contribs.'
			: 'Check terminal.core.ts wiring.'
	};
}
