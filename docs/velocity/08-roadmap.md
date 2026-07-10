# Roadmap

| Milestone | Status | Outcome |
|---|---|---|
| M0 | Complete | Standalone repository, docs, Native SDK foundation |
| M1 | Complete | Running native shell with bounded UI/model state |
| M2 | MVP complete | Workspace open/scan/edit/save/recovery and governed pipe commands |
| M3 | Blocked/not operational | Rich editor island after first paint |
| M4 | Blocked/not operational | Native terminal PTY transport; current runner uses pipes |
| M5 | Blocked/not operational | LSP transport plus one language server |
| M6 | Not started | Plugin runtime and permission enforcement |
| M7 | Not started | Signed, allowlisted registry client |
| M8 | Deferred | Optional sandboxed legacy VSIX bridge |

The editor, PTY, and LSP protocol scaffolds are testable boundaries only; none
is a working runtime integration. See `18-mvp-definition.md` for shipped scope
and `native-sdk-blockers.md` for exact unblock criteria.
