# CaptureLiveKit

Reusable capture-domain primitives extracted from Record and Learn.

## Scope

- Recording session models
- Live transcript buffering and generation triggers
- Document import processing
- Import pipeline interfaces with host protocol adapters
- Recording library grouping/parser primitives

## Local verification

```bash
swift build -c release
swift test -c release
```

## Local release script

Use `scripts/release_local.sh` for local SemVer tagging and GitHub Release creation.
