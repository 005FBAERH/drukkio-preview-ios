# DrukkioPreview

SwiftUI / UIKit WebView wrappers for [DRUKKIO](https://drukk.io) product embeds — the same preview, buy, link, info, and QR widgets as the web components.

**Platforms:** iOS 15+  
**License:** MIT

## Install (Swift Package Manager)

In Xcode: **File → Add Package Dependencies…** and enter your package Git URL (see [PUBLISH.md](PUBLISH.md)).

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/005FBAERH/drukkio-preview-ios.git", from: "0.1.0"),
]
```

Then link the **DrukkioPreview** product to your app target.

## Usage

```swift
import SwiftUI
import DrukkioPreview

struct Shirt: View {
    var body: some View {
        DrukkioPreview(
            product: "0123456789abcdef",
            canvasColor: "#111111",
            sockets: ["headline": "Ada"],
            showName: true,
            showPrice: true,
            showBuy: true,
            checkout: true,
            options: true
        )
    }
}
```

Also available: `DrukkioBuy`, `DrukkioLink`, `DrukkioInfo`, `DrukkioQr` (and the `*View` UIKit classes).

Shop and checkout open in the **system browser** by default. Pass `onOpenUrl` if the app should handle the URL first.

## Docs

- [App integration](https://drukk.io/en/docs/app-integration)
- [Web components](https://drukk.io/en/docs/web-integration)

## License

MIT
