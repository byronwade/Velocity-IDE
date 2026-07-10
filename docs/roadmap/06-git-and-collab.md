# 06 · Git and collaboration

Built-in Git UX is table stakes (Zed's core stance; VS Code ships it in the
box). Collaboration is a later differentiator that gets cheap if the editor
core adopts stable anchors early (see 01-editor-core).

Verified precedent: Zed rejected OT after the Teletype era and made buffer
operations inherently commutative — insertion ids + anchor positions — so
multiplayer needed no transformation logic.

## Todo

- [ ] P0 [TS] Inline diff decorations in the editor gutter (added/modified/
      deleted bars) from the existing git status pipeline.
- [ ] P1 [TS] Commit flow polish: staged/unstaged sections as separate lists
      (today one list with per-row buttons), amend, commit message history.
- [ ] P1 [TS] Branch UX: switch/create branch from the status bar segment;
      branch listing via governed `git` calls.
- [ ] P1 [TS] Editable side-by-side diff (today's diff review is read-only,
      bounded): edit the working side in place; powered by multibuffers.
- [ ] P1 [DIFF] Worktree management UI (shared with agents roadmap): list,
      create, prune worktrees; show which agent owns which worktree.
- [ ] P2 [TS] Blame layer (toggleable inline last-change annotations).
- [ ] P2 [DIFF] Collaboration alpha on CRDT anchors: shared buffer between
      two Velocity instances on a LAN, cursors + edits only — proves the
      anchor substrate before any server work.
