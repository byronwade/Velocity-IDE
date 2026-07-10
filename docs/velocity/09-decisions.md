# Decisions

| ID | Decision | Rationale |
|---|---|---|
| D1 | Maintain a standalone native repository | Keep product boundaries explicit; use microsoft/vscode externally for research |
| D2 | Native SDK (Zig + `.native`) for shell | Fast native window; TEA model; markup hot reload |
| D3 | Editor as island (placeholder → Monaco WebView) | Avoid rebuilding editor day one; keep shell native |
| D4 | Plugins default-deny; no VSIX by default | Security + startup budget |
| D5 | No telemetry / marketplace / Copilot wiring | Product principles |
| D6 | Codename Velocity is rename-ready | Avoid irreversible branding |
| D7 | Pin Native SDK CLI in `.tools` | One reproducible CLI installation without a product dependency |
