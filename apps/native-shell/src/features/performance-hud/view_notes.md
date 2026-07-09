# Performance HUD view

Rendered in the main shell (`src/app.native`) when `show_perf_hud` is true or activity selects perf tools.
Every row includes a unit and explicit measured/unavailable state. In-process
frame marks, SDK first-frame latency, Governor counts, and registry counts are
measured from their named sources. RSS, external launch timing, terminal
process-ready latency, and plugin process ownership remain `n/a` until a real
source exists.
