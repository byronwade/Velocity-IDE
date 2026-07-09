# Decisions

| ID | Decision | Rationale |
|---|---|---|
| D1 | Build beside VS Code fork, do not rewrite workbench now | Ship a clean native shell; keep fork as reference/fallback |
| D2 | Native SDK (Zig + `.native`) for shell | Fast native window; TEA model; markup hot reload |
| D3 | Editor as island (placeholder → Monaco WebView) | Avoid rebuilding editor day one; keep shell native |
| D4 | Plugins default-deny; no VSIX by default | Security + startup budget |
| D5 | No telemetry / marketplace / Copilot wiring | Product principles |
| D6 | Codename Velocity is rename-ready | Avoid irreversible branding |
