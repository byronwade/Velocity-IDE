# Registry Security

## Goals

- Signed plugin packages only in the curated registry
- Publisher trust tiers (trusted-core, verified, community, unsigned)
- Permission labels shown before install
- Performance scores (activation ms, idle RSS)
- Enterprise allowlists / denylists

## Current status

Preview rows exist in the native shell, but there is no registry client,
download path, package format, or signature verification. Registry-related
feature IDs and resource budgets are tracked in
`apps/native-shell/src/core/feature_catalog.json`; this document is the security
design target until an implementation exists.
