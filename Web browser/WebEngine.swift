//
//  WebEngine.swift
//  Web browser
//
//  One long-lived WKWebView backing the viewport, so history survives moving
//  between sites and the menu bar can drive it.
//

import Combine
import SwiftUI
import WebKit

@MainActor
final class WebEngine: NSObject, ObservableObject {
    let webView: WKWebView

    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var currentURL: URL?
    @Published private(set) var isLoading = false

    /// Called whenever the view lands on a new address, however it got there —
    /// a click, a link, a keyboard shortcut WebKit handled itself.
    var onNavigate: ((URL) -> Void)?

    private var observations: [NSKeyValueObservation] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = .all
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true

        observe(\.canGoBack) { $0.canGoBack = $1.canGoBack }
        observe(\.canGoForward) { $0.canGoForward = $1.canGoForward }
        observe(\.url) { engine, webView in
            engine.currentURL = webView.url
            if let url = webView.url { engine.onNavigate?(url) }
        }
        observe(\.isLoading) { $0.isLoading = $1.isLoading }
    }

    private func observe<Value>(_ keyPath: KeyPath<WKWebView, Value> & Sendable,
                                update: @escaping @MainActor (WebEngine, WKWebView) -> Void) {
        let observation = webView.observe(keyPath, options: [.initial, .new]) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                update(self, webView)
            }
        }
        observations.append(observation)
    }

    func load(_ url: URL) {
        guard webView.url != url else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        webView.load(request)
    }

    /// Empty the view, so switching to a frame with no sites doesn't leave the
    /// last page sitting there.
    func clear() {
        webView.loadHTMLString("", baseURL: nil)
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
}

extension WebEngine: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {}
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {}
}

extension WebEngine: WKUIDelegate {
    /// Keep target="_blank" links inside the viewport instead of dropping them.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}

/// Hosts the engine's single web view; SwiftUI just positions it.
struct WebViewport: NSViewRepresentable {
    let engine: WebEngine

    func makeNSView(context: Context) -> WKWebView {
        engine.webView.appearance = NSApp.effectiveAppearance
        return engine.webView
    }

    /// The window is pinned light for the title bar's sake; don't drag the
    /// sites you're viewing along with it.
    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.appearance = NSApp.effectiveAppearance
    }
}
