# Workspace Manager

- **id:** `feature.workspace-manager`
- **mode:** `core`
- **status:** `prototype`
- **startupAllowed:** `false`
- **memoryBudgetMB:** `8`

## Behavior (M2)

- `Open Folder` / recent **acme-dashboard** opens `fixtures/acme-dashboard` via path (no OS dialog yet).
- Scan + document buffers live in heap-allocated `WorkspaceBuffers` (not on the Model stack).
- Workspace Trust remains false until Trust Plus is implemented.

## Next

- Native open-directory dialog (`showOpenDialog`) with `filesystem` permission.
- Multi-root workspaces.
- File watchers (process-budgeted).
