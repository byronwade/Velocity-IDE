# Changelog

All notable changes to Velocity IDE will be documented here.

## [0.1.0] - Unreleased

### Added

- Standalone Native SDK shell with bounded workspace editing and recovery.
- Governed pipe-based terminal, task, test, launch, and Git command execution.
- Problems, read-only diff review, literal snippets, and eight smoke suites.
- Canonical 200-entry feature catalog with deterministic Zig registry generation.

### Known limitations

- Linux is the only CI-validated platform.
- The editor uses a native textarea; the rich editor island is not operational.
- Terminal execution is pipe-based rather than PTY-backed.
- LSP transport, plugin runtime/registry, debugger, and network AI are not implemented.
