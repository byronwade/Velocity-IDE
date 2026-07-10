# 07 · Extensibility

The open strategic risk: VS Code's marketplace is the moat Velocity cannot
copy. Zed's answer — batteries-included core + thin extension surface — is
the verified viable posture for a native editor. Velocity already has the
right skeleton: curated, permissioned, signed registry; plugins locked until
trusted; process budgets per feature.

## Todo

- [ ] P1 [TS] Define the v1 extension surface deliberately small: themes,
      grammars/language configs, MCP tool servers, ACP agents. No arbitrary
      UI injection in v1.
- [ ] P1 [TS] WASM sandbox for compute extensions (grammars, linters) with
      capability-based permissions mapped to the existing permissions model;
      every extension process governed with memory/process budgets.
- [ ] P1 [TS] Registry trust flow: signing, review states, and the existing
      "locked until trusted" UX made real (install → inspect permissions →
      trust → activate).
- [ ] P2 [DIFF] Per-extension resource accounting in the perf HUD (memory,
      processes, activation cost) — turn process governance into a visible
      trust feature no competitor exposes.
- [ ] P2 [TS] Compatibility shims where cheap: TextMate grammar import,
      VS Code theme import (tokens permitting) to soften the ecosystem gap.
