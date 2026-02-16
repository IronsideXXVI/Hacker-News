import SwiftUI
import WebKit

struct ArticleWebView: NSViewRepresentable {
    let url: URL
    @Binding var scrollProgress: Double

    init(url: URL, scrollProgress: Binding<Double> = .constant(0)) {
        self.url = url
        self._scrollProgress = scrollProgress
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let scrollScript = WKUserScript(
            source: Self.scrollObserverJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(scrollScript)
        config.userContentController.add(context.coordinator, name: "scrollHandler")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        context.coordinator.currentURL = url
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.currentURL != url {
            context.coordinator.currentURL = url
            DispatchQueue.main.async { scrollProgress = 0 }
            webView.load(URLRequest(url: url))
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "scrollHandler")
    }

    private static let scrollObserverJS = """
    (function() {
        if (window.__scrollObserverInstalled) return;
        window.__scrollObserverInstalled = true;
        function reportScroll() {
            var h = document.documentElement.scrollHeight - document.documentElement.clientHeight;
            var progress = h > 0 ? (document.documentElement.scrollTop / h) : 0;
            window.webkit.messageHandlers.scrollHandler.postMessage(Math.min(Math.max(progress, 0), 1));
        }
        window.addEventListener('scroll', reportScroll, { passive: true });
        window.addEventListener('resize', reportScroll, { passive: true });
        reportScroll();
    })();
    """

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: ArticleWebView
        var currentURL: URL?

        init(parent: ArticleWebView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if let value = message.body as? Double {
                DispatchQueue.main.async {
                    self.parent.scrollProgress = value
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(ArticleWebView.scrollObserverJS, completionHandler: nil)
        }
    }
}
