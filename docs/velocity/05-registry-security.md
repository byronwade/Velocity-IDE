# Registry Security

## Goals

- Signed plugin packages only in the curated registry
- Publisher trust tiers (trusted-core, verified, community, unsigned)
- Permission labels shown before install
- Performance scores (activation ms, idle RSS)
- Enterprise allowlists / denylists

## Scaffold status

Preview rows only in the native shell. No downloads, no signature verification yet.
See `packages/registry-client/` and `apps/native-shell/src/registry/`.
