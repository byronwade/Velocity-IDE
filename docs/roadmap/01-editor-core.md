# 01 · Editor core (text engine)

The current editor is a native textarea over a whole-document string. Every
serious competitor runs a tree-structured buffer with cheap snapshots. This is
the deepest foundation item on the roadmap; most later features (background
agents, collaboration, large-file support) sit on top of it.

Verified precedents:
- Zed's rope is a copy-on-write persistent B+ tree ("SumTree") of ≤128-byte
  chunks; node summaries give O(log n) seeks by offset/point/UTF-16/line
  (zed.dev/blog/zed-decoded-rope-sumtree).
- Concurrency was the stated hard requirement: snapshots are an Arc refcount
  bump, letting every edit ship the buffer to background threads. Gap buffers
  and piece tables were ruled out for this.
- VS Code's line-array model amplified a 35 MB file to ~600 MB before the 1.21
  piece-tree rewrite; their native C++ buffer was rejected because JS↔C++
  boundary crossings erased the gains. Velocity has no such boundary.
- Zed accelerates offset↔point math with per-chunk u128 bitmaps
  (count_ones/leading_zeros), ~70% faster point_to_offset (PR #19913).
- Zed's buffer is CRDT-native: insertions carry (replica id, sequence) ids and
  positions are anchors (insertion id, offset) stable under concurrent edits —
  the substrate for multiplayer AND stable cursors/diagnostics.

## Todo

- [ ] P0 [TS] Design `rope.zig`: persistent chunk tree with per-node summaries
      (bytes, chars, lines, UTF-16 units); bounded chunk size (~128 B); arena
      or refcounted copy-on-write nodes compatible with Zig memory discipline.
- [ ] P0 [TS] Cheap immutable snapshots (refcount bump, no text copy) so
      background work (search, diagnostics, agents) reads a stable buffer
      while the user keeps typing.
- [ ] P0 [TS] O(log n) coordinate conversion (offset ↔ line/col ↔ UTF-16);
      add per-chunk bitmaps for newline/char counting on the hot path.
- [ ] P0 [TS] Replace the textarea-backed document model with the rope behind
      the existing edit/save/undo/transform surface without changing tests'
      observable behavior; keep bounded-memory guarantees (AGENTS.md).
- [ ] P1 [DIFF] Stable position anchors from day one: (edit id, offset) pairs
      used for cursors, find results, diagnostics, and breadcrumbs so they
      survive concurrent/background edits. This is the cheap-now,
      expensive-later CRDT foundation.
- [ ] P1 [TS] Incremental edit journal on top of anchors (insert-immutable
      model) to replace the whole-text undo stack; bounded history.
- [ ] P1 [TS] Large-file discipline: memory ceiling per document, lazy line
      index, and a measured "open a 100 MB log" budget in the perf HUD.
- [ ] P2 [TS] Multibuffer view (Zed's signature): one editor surface composing
      excerpts from many buffers — powers project-wide find/replace review and
      agent diff review.
- [ ] P2 [DIFF] Full CRDT convergence (replica ids, vector timestamps) once
      collaboration ships; the anchor model above must not need rework.
