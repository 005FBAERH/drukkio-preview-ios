import SwiftUI
import UIKit
import WebKit

public enum DrukkioOrigin {
    public static let defaultOrigin = "https://drukk.io"

    public static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host,
              !host.isEmpty else {
            return defaultOrigin
        }
        var text = "\(scheme)://\(host)"
        if let port = url.port {
            text += ":\(port)"
        }
        return text
    }
}

/// Base WKWebView for every DRUKKIO embed tag. Links open outside the view.
open class DrukkioEmbedView: WKWebView, WKNavigationDelegate {
    public var onOpenUrl: ((URL) -> Void)?
    public var onHeightChange: ((CGFloat) -> Void)?

    private let componentTag: String
    private let bridge: Bridge
    private var embedReady = false
    private var loadedOrigin: String?
    private var reportedHeight: CGFloat = 0
    private var lastOpenUrl = ""
    private var lastOpenAt: TimeInterval = 0
    private var configProvider: () -> String?

    public init(tag: String, frame: CGRect = .zero, configProvider: @escaping () -> String?) {
        self.componentTag = tag
        self.configProvider = configProvider
        let bridge = Bridge()
        self.bridge = bridge
        let controller = WKUserContentController()
        controller.add(bridge, name: "drukkio")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        super.init(frame: frame, configuration: configuration)
        bridge.owner = self
        navigationDelegate = self
        isOpaque = false
        backgroundColor = .clear
        scrollView.isScrollEnabled = false
        scrollView.bounces = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        allowsLinkPreview = false
        if #available(iOS 15.0, *) {
            underPageBackgroundColor = .clear
        }
    }

  @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("Drukkio embed views are created in code")
    }

    deinit {
        bridge.owner = nil
        configuration.userContentController.removeScriptMessageHandler(forName: "drukkio")
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(
            width: UIView.noIntrinsicMetric,
            height: reportedHeight > 0 ? reportedHeight : UIView.noIntrinsicMetric
        )
    }

    public func reloadIfOriginChanged(_ origin: String) {
        let normalized = DrukkioOrigin.normalize(origin)
        if loadedOrigin == nil || normalized != loadedOrigin {
            loadDocument(origin: normalized)
            return
        }
        if embedReady {
            applyConfig()
        }
    }

    public func refreshConfig() {
        guard embedReady else { return }
        applyConfig()
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let frame = navigationAction.targetFrame, !frame.isMainFrame {
            decisionHandler(.allow)
            return
        }
        guard embedReady, let url = navigationAction.request.url, isWebLink(url) else {
            decisionHandler(.allow)
            return
        }
        openExternal(url)
        decisionHandler(.cancel)
    }

    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            openExternal(url)
        }
        return nil
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        embedReady = true
        applyConfig()
    }

    private func loadDocument(origin: String) {
        embedReady = false
        loadedOrigin = origin
        loadHTMLString(drukkioDocument(origin: origin, tag: componentTag), baseURL: URL(string: origin + "/"))
    }

    private func applyConfig() {
        guard embedReady, let json = configProvider() else { return }
        evaluateJavaScript(
            "(function(config){if(window.drukkioApply){window.drukkioApply(config)}else{window.drukkioPending=config}})(\(json))",
            completionHandler: nil
        )
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.name == "drukkio", let body = message.body as? [String: Any] else { return }
        switch body["type"] as? String {
        case "height":
            guard let number = body["height"] as? NSNumber else { return }
            let height = CGFloat(number.doubleValue)
            guard height > 0, height < 4000, abs(height - reportedHeight) > 0.5 else { return }
            reportedHeight = height
            invalidateIntrinsicContentSize()
            onHeightChange?(height)
        case "open":
            guard let text = body["url"] as? String, let url = URL(string: text) else { return }
            openExternal(url)
        default:
            break
        }
    }

    private func openExternal(_ url: URL) {
        guard isWebLink(url) else { return }
        let now = Date().timeIntervalSince1970
        if url.absoluteString == lastOpenUrl, now - lastOpenAt < 0.8 {
            return
        }
        lastOpenUrl = url.absoluteString
        lastOpenAt = now
        if let onOpenUrl {
            onOpenUrl(url)
            return
        }
        UIApplication.shared.open(url)
    }

    private func isWebLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }

    private final class Bridge: NSObject, WKScriptMessageHandler {
        weak var owner: DrukkioEmbedView?

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            owner?.receive(message)
        }
    }
}

public struct DrukkioPreviewOptions: Equatable {
    public var product: String
    public var origin: String
    public var mode: String
    public var placement: String
    public var canvasColor: String
    public var background: String
    public var sockets: [String: String]
    public var showName: Bool
    public var showPrice: Bool
    public var showBuy: Bool
    public var showQr: Bool
    public var checkout: Bool
    public var options: Bool
    public var plain: Bool
    public var tooltip: Bool
    public var size: String
    public var color: String

    public init(
        product: String,
        origin: String = DrukkioOrigin.defaultOrigin,
        mode: String = "svg",
        placement: String = "",
        canvasColor: String = "",
        background: String = "",
        sockets: [String: String] = [:],
        showName: Bool = false,
        showPrice: Bool = false,
        showBuy: Bool = false,
        showQr: Bool = false,
        checkout: Bool = false,
        options: Bool = false,
        plain: Bool = false,
        tooltip: Bool = false,
        size: String = "",
        color: String = ""
    ) {
        self.product = product
        self.origin = origin
        self.mode = mode
        self.placement = placement
        self.canvasColor = canvasColor
        self.background = background
        self.sockets = sockets
        self.showName = showName
        self.showPrice = showPrice
        self.showBuy = showBuy
        self.showQr = showQr
        self.checkout = checkout
        self.options = options
        self.plain = plain
        self.tooltip = tooltip
        self.size = size
        self.color = color
    }
}

public struct DrukkioBuyOptions: Equatable {
    public var product: String
    public var origin: String
    public var sockets: [String: String]
    public var action: Bool
    public var actionQuery: String
    public var options: Bool
    public var size: String
    public var color: String
    public var buttonColor: String
    public var borderColor: String
    public var icon: String
    public var showPrice: Bool
    public var tooltip: Bool

    public init(
        product: String,
        origin: String = DrukkioOrigin.defaultOrigin,
        sockets: [String: String] = [:],
        action: Bool = false,
        actionQuery: String = "",
        options: Bool = false,
        size: String = "",
        color: String = "",
        buttonColor: String = "",
        borderColor: String = "",
        icon: String = "",
        showPrice: Bool = false,
        tooltip: Bool = false
    ) {
        self.product = product
        self.origin = origin
        self.sockets = sockets
        self.action = action
        self.actionQuery = actionQuery
        self.options = options
        self.size = size
        self.color = color
        self.buttonColor = buttonColor
        self.borderColor = borderColor
        self.icon = icon
        self.showPrice = showPrice
        self.tooltip = tooltip
    }
}

public struct DrukkioLinkOptions: Equatable {
    public var product: String
    public var origin: String
    public var sockets: [String: String]
    public var action: Bool
    public var actionQuery: String
    public var tooltip: Bool
    public var text: String

    public init(
        product: String,
        origin: String = DrukkioOrigin.defaultOrigin,
        sockets: [String: String] = [:],
        action: Bool = false,
        actionQuery: String = "",
        tooltip: Bool = false,
        text: String = ""
    ) {
        self.product = product
        self.origin = origin
        self.sockets = sockets
        self.action = action
        self.actionQuery = actionQuery
        self.tooltip = tooltip
        self.text = text
    }
}

public struct DrukkioInfoOptions: Equatable {
    public var product: String
    public var origin: String
    public var showPrice: Bool
    public var showColors: Bool
    public var showDescription: Bool
    public var showSizes: Bool

    public init(
        product: String,
        origin: String = DrukkioOrigin.defaultOrigin,
        showPrice: Bool = false,
        showColors: Bool = false,
        showDescription: Bool = false,
        showSizes: Bool = false
    ) {
        self.product = product
        self.origin = origin
        self.showPrice = showPrice
        self.showColors = showColors
        self.showDescription = showDescription
        self.showSizes = showSizes
    }
}

public struct DrukkioQrOptions: Equatable {
    public var product: String
    public var origin: String
    public var sockets: [String: String]
    public var action: Bool
    public var actionQuery: String
    public var options: Bool
    public var size: String
    public var color: String
    public var tooltip: Bool

    public init(
        product: String,
        origin: String = DrukkioOrigin.defaultOrigin,
        sockets: [String: String] = [:],
        action: Bool = false,
        actionQuery: String = "",
        options: Bool = false,
        size: String = "",
        color: String = "",
        tooltip: Bool = false
    ) {
        self.product = product
        self.origin = origin
        self.sockets = sockets
        self.action = action
        self.actionQuery = actionQuery
        self.options = options
        self.size = size
        self.color = color
        self.tooltip = tooltip
    }
}

public final class DrukkioPreviewView: DrukkioEmbedView {
    public private(set) var options: DrukkioPreviewOptions

    public init(options: DrukkioPreviewOptions, frame: CGRect = .zero) {
        self.options = options
        super.init(tag: "drukkio-preview", frame: frame) { [weak self] in
            self?.configJSON(from: self?.options)
        }
        reloadIfOriginChanged(options.origin)
    }

    public func update(options next: DrukkioPreviewOptions) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.update(options: next) }
            return
        }
        let changed = next != options
        options = next
        reloadIfOriginChanged(next.origin)
        if changed { refreshConfig() }
    }
}

public final class DrukkioBuyView: DrukkioEmbedView {
    public private(set) var options: DrukkioBuyOptions

    public init(options: DrukkioBuyOptions, frame: CGRect = .zero) {
        self.options = options
        super.init(tag: "drukkio-buy", frame: frame) { [weak self] in
            self?.configJSON(from: self?.options)
        }
        reloadIfOriginChanged(options.origin)
    }

    public func update(options next: DrukkioBuyOptions) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.update(options: next) }
            return
        }
        let changed = next != options
        options = next
        reloadIfOriginChanged(next.origin)
        if changed { refreshConfig() }
    }
}

public final class DrukkioLinkView: DrukkioEmbedView {
    public private(set) var options: DrukkioLinkOptions

    public init(options: DrukkioLinkOptions, frame: CGRect = .zero) {
        self.options = options
        super.init(tag: "drukkio-link", frame: frame) { [weak self] in
            self?.configJSON(from: self?.options)
        }
        reloadIfOriginChanged(options.origin)
    }

    public func update(options next: DrukkioLinkOptions) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.update(options: next) }
            return
        }
        let changed = next != options
        options = next
        reloadIfOriginChanged(next.origin)
        if changed { refreshConfig() }
    }
}

public final class DrukkioInfoView: DrukkioEmbedView {
    public private(set) var options: DrukkioInfoOptions

    public init(options: DrukkioInfoOptions, frame: CGRect = .zero) {
        self.options = options
        super.init(tag: "drukkio-info", frame: frame) { [weak self] in
            self?.configJSON(from: self?.options)
        }
        reloadIfOriginChanged(options.origin)
    }

    public func update(options next: DrukkioInfoOptions) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.update(options: next) }
            return
        }
        let changed = next != options
        options = next
        reloadIfOriginChanged(next.origin)
        if changed { refreshConfig() }
    }
}

public final class DrukkioQrView: DrukkioEmbedView {
    public private(set) var options: DrukkioQrOptions

    public init(options: DrukkioQrOptions, frame: CGRect = .zero) {
        self.options = options
        super.init(tag: "drukkio-qr", frame: frame) { [weak self] in
            self?.configJSON(from: self?.options)
        }
        reloadIfOriginChanged(options.origin)
    }

    public func update(options next: DrukkioQrOptions) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.update(options: next) }
            return
        }
        let changed = next != options
        options = next
        reloadIfOriginChanged(next.origin)
        if changed { refreshConfig() }
    }
}

private extension DrukkioEmbedView {
    func configJSON(from preview: DrukkioPreviewOptions?) -> String? {
        guard let preview else { return nil }
        var payload: [String: Any] = [
            "product": preview.product,
            "mode": preview.mode,
            "placement": preview.placement,
            "canvasColor": preview.canvasColor,
            "background": preview.background,
            "sockets": preview.sockets,
            "showName": preview.showName,
            "showPrice": preview.showPrice,
            "showBuy": preview.showBuy,
            "showQr": preview.showQr,
            "checkout": preview.checkout,
            "options": preview.options,
            "plain": preview.plain,
            "tooltip": preview.tooltip,
            "size": preview.size,
            "color": preview.color,
        ]
        return serialize(payload)
    }

    func configJSON(from buy: DrukkioBuyOptions?) -> String? {
        guard let buy else { return nil }
        var payload: [String: Any] = [
            "product": buy.product,
            "sockets": buy.sockets,
            "options": buy.options,
            "size": buy.size,
            "color": buy.color,
            "buttonColor": buy.buttonColor,
            "borderColor": buy.borderColor,
            "icon": buy.icon,
            "showPrice": buy.showPrice,
            "tooltip": buy.tooltip,
        ]
        putAction(&payload, flag: buy.action, query: buy.actionQuery)
        return serialize(payload)
    }

    func configJSON(from link: DrukkioLinkOptions?) -> String? {
        guard let link else { return nil }
        var payload: [String: Any] = [
            "product": link.product,
            "sockets": link.sockets,
            "tooltip": link.tooltip,
            "text": link.text,
        ]
        putAction(&payload, flag: link.action, query: link.actionQuery)
        return serialize(payload)
    }

    func configJSON(from info: DrukkioInfoOptions?) -> String? {
        guard let info else { return nil }
        let payload: [String: Any] = [
            "product": info.product,
            "showPrice": info.showPrice,
            "showColors": info.showColors,
            "showDescription": info.showDescription,
            "showSizes": info.showSizes,
        ]
        return serialize(payload)
    }

    func configJSON(from qr: DrukkioQrOptions?) -> String? {
        guard let qr else { return nil }
        var payload: [String: Any] = [
            "product": qr.product,
            "sockets": qr.sockets,
            "options": qr.options,
            "size": qr.size,
            "color": qr.color,
            "tooltip": qr.tooltip,
        ]
        putAction(&payload, flag: qr.action, query: qr.actionQuery)
        return serialize(payload)
    }

    func putAction(_ payload: inout [String: Any], flag: Bool, query: String) {
        if !query.isEmpty {
            payload["action"] = query
        } else if flag {
            payload["action"] = true
        }
    }

    func serialize(_ payload: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              var text = String(data: data, encoding: .utf8) else {
            return nil
        }
        text = text.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        text = text.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return text
    }
}

public struct DrukkioPreview: View {
    private let options: DrukkioPreviewOptions
    private let onOpenUrl: ((URL) -> Void)?
    @State private var height: CGFloat = 360

    public init(
        product: String,
        origin: String = DrukkioOrigin.defaultOrigin,
        mode: String = "svg",
        placement: String = "",
        canvasColor: String = "",
        background: String = "",
        sockets: [String: String] = [:],
        showName: Bool = false,
        showPrice: Bool = false,
        showBuy: Bool = false,
        showQr: Bool = false,
        checkout: Bool = false,
        options: Bool = false,
        plain: Bool = false,
        tooltip: Bool = false,
        size: String = "",
        color: String = "",
        onOpenUrl: ((URL) -> Void)? = nil
    ) {
        self.options = DrukkioPreviewOptions(
            product: product,
            origin: origin,
            mode: mode,
            placement: placement,
            canvasColor: canvasColor,
            background: background,
            sockets: sockets,
            showName: showName,
            showPrice: showPrice,
            showBuy: showBuy,
            showQr: showQr,
            checkout: checkout,
            options: options,
            plain: plain,
            tooltip: tooltip,
            size: size,
            color: color
        )
        self.onOpenUrl = onOpenUrl
    }

    public var body: some View {
        EmbedRepresentable(
            make: { DrukkioPreviewView(options: options) },
            options: options,
            onOpenUrl: onOpenUrl
        ) { next in
            if abs(height - next) > 0.5 { height = next }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}

public struct DrukkioBuy: View {
    private let options: DrukkioBuyOptions
    private let onOpenUrl: ((URL) -> Void)?
    @State private var height: CGFloat = 360

    public init(
        product: String,
        origin: String = DrukkioOrigin.defaultOrigin,
        sockets: [String: String] = [:],
        action: Bool = false,
        actionQuery: String = "",
        options: Bool = false,
        size: String = "",
        color: String = "",
        buttonColor: String = "",
        borderColor: String = "",
        icon: String = "",
        showPrice: Bool = false,
        tooltip: Bool = false,
        onOpenUrl: ((URL) -> Void)? = nil
    ) {
        self.options = DrukkioBuyOptions(
            product: product,
            origin: origin,
            sockets: sockets,
            action: action,
            actionQuery: actionQuery,
            options: options,
            size: size,
            color: color,
            buttonColor: buttonColor,
            borderColor: borderColor,
            icon: icon,
            showPrice: showPrice,
            tooltip: tooltip
        )
        self.onOpenUrl = onOpenUrl
    }

    public var body: some View {
        EmbedRepresentable(
            make: { DrukkioBuyView(options: options) },
            options: options,
            onOpenUrl: onOpenUrl
        ) { next in
            if abs(height - next) > 0.5 { height = next }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}

public struct DrukkioLink: View {
    private let options: DrukkioLinkOptions
    private let onOpenUrl: ((URL) -> Void)?
    @State private var height: CGFloat = 360

    public init(
        product: String,
        origin: String = DrukkioOrigin.defaultOrigin,
        sockets: [String: String] = [:],
        action: Bool = false,
        actionQuery: String = "",
        tooltip: Bool = false,
        text: String = "",
        onOpenUrl: ((URL) -> Void)? = nil
    ) {
        self.options = DrukkioLinkOptions(
            product: product,
            origin: origin,
            sockets: sockets,
            action: action,
            actionQuery: actionQuery,
            tooltip: tooltip,
            text: text
        )
        self.onOpenUrl = onOpenUrl
    }

    public var body: some View {
        EmbedRepresentable(
            make: { DrukkioLinkView(options: options) },
            options: options,
            onOpenUrl: onOpenUrl
        ) { next in
            if abs(height - next) > 0.5 { height = next }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}

public struct DrukkioInfo: View {
    private let options: DrukkioInfoOptions
    private let onOpenUrl: ((URL) -> Void)?
    @State private var height: CGFloat = 360

    public init(
        product: String,
        origin: String = DrukkioOrigin.defaultOrigin,
        showPrice: Bool = false,
        showColors: Bool = false,
        showDescription: Bool = false,
        showSizes: Bool = false,
        onOpenUrl: ((URL) -> Void)? = nil
    ) {
        self.options = DrukkioInfoOptions(
            product: product,
            origin: origin,
            showPrice: showPrice,
            showColors: showColors,
            showDescription: showDescription,
            showSizes: showSizes
        )
        self.onOpenUrl = onOpenUrl
    }

    public var body: some View {
        EmbedRepresentable(
            make: { DrukkioInfoView(options: options) },
            options: options,
            onOpenUrl: onOpenUrl
        ) { next in
            if abs(height - next) > 0.5 { height = next }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}

public struct DrukkioQr: View {
    private let options: DrukkioQrOptions
    private let onOpenUrl: ((URL) -> Void)?
    @State private var height: CGFloat = 360

    public init(
        product: String,
        origin: String = DrukkioOrigin.defaultOrigin,
        sockets: [String: String] = [:],
        action: Bool = false,
        actionQuery: String = "",
        options: Bool = false,
        size: String = "",
        color: String = "",
        tooltip: Bool = false,
        onOpenUrl: ((URL) -> Void)? = nil
    ) {
        self.options = DrukkioQrOptions(
            product: product,
            origin: origin,
            sockets: sockets,
            action: action,
            actionQuery: actionQuery,
            options: options,
            size: size,
            color: color,
            tooltip: tooltip
        )
        self.onOpenUrl = onOpenUrl
    }

    public var body: some View {
        EmbedRepresentable(
            make: { DrukkioQrView(options: options) },
            options: options,
            onOpenUrl: onOpenUrl
        ) { next in
            if abs(height - next) > 0.5 { height = next }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}

private struct EmbedRepresentable<ViewType: DrukkioEmbedView, Options: Equatable>: UIViewRepresentable {
    let make: () -> ViewType
    var options: Options
    var onOpenUrl: ((URL) -> Void)?
    var onHeight: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenUrl: onOpenUrl, onHeight: onHeight)
    }

    func makeUIView(context: Context) -> ViewType {
        let view = make()
        let coordinator = context.coordinator
        view.onOpenUrl = { coordinator.onOpenUrl?($0) }
        view.onHeightChange = { coordinator.onHeight($0) }
        return view
    }

    func updateUIView(_ view: ViewType, context: Context) {
        context.coordinator.onOpenUrl = onOpenUrl
        context.coordinator.onHeight = onHeight
        if let preview = view as? DrukkioPreviewView, let next = options as? DrukkioPreviewOptions {
            preview.update(options: next)
        } else if let buy = view as? DrukkioBuyView, let next = options as? DrukkioBuyOptions {
            buy.update(options: next)
        } else if let link = view as? DrukkioLinkView, let next = options as? DrukkioLinkOptions {
            link.update(options: next)
        } else if let info = view as? DrukkioInfoView, let next = options as? DrukkioInfoOptions {
            info.update(options: next)
        } else if let qr = view as? DrukkioQrView, let next = options as? DrukkioQrOptions {
            qr.update(options: next)
        }
    }

    final class Coordinator {
        var onOpenUrl: ((URL) -> Void)?
        var onHeight: (CGFloat) -> Void

        init(onOpenUrl: ((URL) -> Void)?, onHeight: @escaping (CGFloat) -> Void) {
            self.onOpenUrl = onOpenUrl
            self.onHeight = onHeight
        }
    }
}

private let pageScript = #"""
(function () {
  var flagNames = {
    showName: "show-name",
    showPrice: "show-price",
    showBuy: "show-buy",
    showQr: "show-qr",
    checkout: "checkout",
    options: "options",
    plain: "plain",
    tooltip: "tooltip",
    showColors: "show-colors",
    showDescription: "show-description",
    showSizes: "show-sizes"
  };
  var reserved = {
    "product": 1, "mode": 1, "placement": 1, "id": 1, "class": 1, "style": 1, "title": 1, "slot": 1,
    "show-name": 1, "show-price": 1, "show-buy": 1, "show-qr": 1,
    "showname": 1, "showprice": 1, "showbuy": 1, "showqr": 1,
    "showName": 1, "showPrice": 1, "showBuy": 1, "showQr": 1,
    "canvas-color": 1, "canvas_color": 1, "canvascolor": 1, "canvasColor": 1,
    "checkout": 1, "options": 1, "action": 1, "tooltip": 1, "plain": 1, "background": 1, "icon": 1,
    "button-color": 1, "button_color": 1, "buttoncolor": 1, "buttonColor": 1,
    "border-color": 1, "border_color": 1, "bordercolor": 1, "borderColor": 1,
    "show-colors": 1, "show-description": 1, "show-sizes": 1,
    "showcolors": 1, "showdescription": 1, "showsizes": 1,
    "showColors": 1, "showDescription": 1, "showSizes": 1,
    "size": 1, "color": 1
  };

  function post(message) {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.drukkio) {
        window.webkit.messageHandlers.drukkio.postMessage(message);
        return;
      }
    } catch (ignored) {}
    var json;
    try {
      json = JSON.stringify(message);
    } catch (ignored) {
      return;
    }
    try {
      if (window.DrukkioNative && window.DrukkioNative.postMessage) {
        window.DrukkioNative.postMessage(json);
        return;
      }
    } catch (ignored) {}
    try {
      if (window.ReactNativeWebView && window.ReactNativeWebView.postMessage) {
        window.ReactNativeWebView.postMessage(json);
      }
    } catch (ignored) {}
  }

  function measure() {
    var el = document.getElementById("host");
    if (!el) return;
    var height = Math.ceil(el.getBoundingClientRect().height);
    if (height > 0 && height < 4000) post({ type: "height", height: height });
  }

  function apply(config) {
    var el = document.getElementById("host");
    if (!el || !config) return;
    var keep = { id: "host" };
    if (config.product) keep.product = String(config.product).slice(0, 64);
    if (config.mode != null && config.mode !== "") {
      keep.mode = config.mode === "3d" ? "3d" : "svg";
    }
    if (config.placement && /^[a-z0-9_]{1,32}$/.test(String(config.placement))) {
      keep.placement = String(config.placement);
    }
    if (config.canvasColor) keep["canvas-color"] = String(config.canvasColor).slice(0, 80);
    if (config.background) keep.background = String(config.background).slice(0, 80);
    if (config.size) keep.size = String(config.size).slice(0, 40);
    if (config.color) keep.color = String(config.color).slice(0, 80);
    if (config.buttonColor) keep["button-color"] = String(config.buttonColor).slice(0, 80);
    if (config.borderColor) keep["border-color"] = String(config.borderColor).slice(0, 80);
    if (config.icon) keep.icon = String(config.icon).slice(0, 40);
    if (config.action === true) {
      keep.action = "";
    } else if (config.action) {
      keep.action = String(config.action).slice(0, 2000);
    }
    var flag;
    for (flag in flagNames) {
      if (Object.prototype.hasOwnProperty.call(flagNames, flag) && config[flag]) {
        keep[flagNames[flag]] = "";
      }
    }
    var sockets = config.sockets || {};
    var key;
    for (key in sockets) {
      if (!Object.prototype.hasOwnProperty.call(sockets, key)) continue;
      if (!/^[A-Za-z][A-Za-z0-9_-]{0,63}$/.test(key)) continue;
      if (reserved[key]) continue;
      if (sockets[key] == null || sockets[key] === "") continue;
      keep[key] = String(sockets[key]).slice(0, 2000);
    }
    var names = el.getAttributeNames ? el.getAttributeNames() : [];
    var index;
    for (index = 0; index < names.length; index++) {
      if (!Object.prototype.hasOwnProperty.call(keep, names[index])) el.removeAttribute(names[index]);
    }
    for (key in keep) {
      if (Object.prototype.hasOwnProperty.call(keep, key) && el.getAttribute(key) !== keep[key]) {
        el.setAttribute(key, keep[key]);
      }
    }
    if (Object.prototype.hasOwnProperty.call(config, "text")) {
      el.textContent = config.text == null ? "" : String(config.text);
    }
    measure();
  }

  window.drukkioApply = apply;
  if (window.drukkioPending) {
    var pending = window.drukkioPending;
    window.drukkioPending = null;
    apply(pending);
  }

  document.addEventListener("click", function (event) {
    var path = event.composedPath ? event.composedPath() : [];
    var index;
    for (index = 0; index < path.length; index++) {
      var node = path[index];
      if (!node || String(node.tagName || "").toUpperCase() !== "A") continue;
      var href = node.href;
      if (!href || !/^https?:/i.test(href)) continue;
      event.preventDefault();
      post({ type: "open", url: href });
      return;
    }
  }, true);

  var host = document.getElementById("host");
  if (window.ResizeObserver && host) new ResizeObserver(measure).observe(host);
  window.addEventListener("load", measure);
  setTimeout(measure, 60);
  setTimeout(measure, 480);
})();
"""#

private func drukkioDocument(origin: String, tag: String) -> String {
    """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      html, body { margin: 0; padding: 0; background: transparent; overflow: hidden; }
      \(tag) { display: block; width: 100%; max-width: 100%; }
    </style>
    <script src="\(origin)/embed.js"></script>
    </head>
    <body>
    <\(tag) id="host"></\(tag)>
    <script>
    \(pageScript)
    </script>
    </body>
    </html>
    """
}