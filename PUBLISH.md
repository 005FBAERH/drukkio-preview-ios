# Publishing DrukkioPreview (Swift Package Manager)

SPM installs from a **public Git repo + version tag**. There is no Maven Central / npm step.

## Recommended: dedicated repo

Published at: **https://github.com/005FBAERH/drukkio-preview-ios**

Consumers add:

```text
https://github.com/005FBAERH/drukkio-preview-ios.git
```

from version `0.1.0`.

To release a new version from `packages/ios-preview`:

1. Sync/push this folder to the repo root.
2. Tag and push:

```bash
git tag 0.1.1
git push origin 0.1.1
```

## Mono-repo alternative

Keep developing here under `packages/ios-preview`. For releases, either:

- subtree-split / copy into the dedicated repo above, or  
- document an Xcode “Add Local Package” path for contributors only.

Xcode needs a Mac to resolve and build the package; authoring the files on Windows is fine.

## Keep the download copy in sync

Canonical source: `Sources/DrukkioPreview/DrukkioPreview.swift`  
Mirror: `public/sdk/mobile/DrukkioPreview.swift` (and the mobile zip).
