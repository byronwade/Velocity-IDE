#!/usr/bin/env node
import { existsSync } from 'node:fs';
import path from 'node:path';

/**
 * Runtime RSS capture requires a running build + Electron.
 * This stub records availability and documents how to extend.
 */
export async function measureMemory(repoRoot) {
	const outMain = path.join(repoRoot, 'out/main.js');
	const hasBuild = existsSync(outMain);

	return {
		idleRssBytes: null,
		rendererBytes: null,
		extensionHostBytes: null,
		runtimeMeasured: false,
		status: hasBuild ? 'build-present-runtime-not-run' : 'no-compiled-out',
		notes: hasBuild
			? 'Compile present. Launch with scripts/code.sh and sample process RSS to fill runtime fields.'
			: 'No out/ build yet. Static harness only. Run full compile before runtime memory capture.'
	};
}
