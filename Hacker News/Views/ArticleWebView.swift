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

        let toolbarHideScript = WKUserScript(
            source: Self.cssInjectionJS(css: Self.toolbarHideCSS),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(toolbarHideScript)

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

    // MARK: - CSS Injection Helper

    private static func cssInjectionJS(css: String) -> String {
        let id = "hn-injected-\(abs(css.hashValue))"
        let escaped = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
        return """
        (function() {
            if (document.getElementById('\(id)')) return;
            var s = document.createElement('style');
            s.id = '\(id)';
            s.textContent = `\(escaped)`;
            document.head.appendChild(s);
        })();
        """
    }

    // MARK: - Toolbar-Hiding CSS

    private static let toolbarHideCSS = """
    #hnmain > tbody > tr:first-child { display: none !important; }
    #hnmain > tbody > tr:nth-child(2) { display: none !important; }
    """

    // MARK: - Profile / Form Styling CSS

    private static let formStylingCSS = """
    /* Remove HN's width constraint */
    body > center > table { width: 100% !important; }

    /* Shared styles for both modes */
    body {
        font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif !important;
    }

    input[type="text"], input[type="password"], input[type="email"],
    input[type="url"], input[type="number"], input[type="search"],
    textarea, select {
        font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif !important;
        font-size: 13px !important;
        border-radius: 6px !important;
        padding: 6px 10px !important;
        box-sizing: border-box !important;
        outline: none !important;
        transition: border-color 0.2s, box-shadow 0.2s !important;
    }

    input[type="text"]:focus, input[type="password"]:focus, input[type="email"]:focus,
    input[type="url"]:focus, input[type="number"]:focus, input[type="search"]:focus,
    textarea:focus, select:focus {
        border-color: #ff6600 !important;
        box-shadow: 0 0 0 3px rgba(255, 102, 0, 0.25) !important;
    }

    input[type="submit"] {
        font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif !important;
        font-size: 13px !important;
        font-weight: 500 !important;
        background-color: #ff6600 !important;
        color: white !important;
        border: none !important;
        border-radius: 6px !important;
        padding: 6px 16px !important;
        cursor: pointer !important;
        transition: background-color 0.2s !important;
    }

    input[type="submit"]:hover {
        background-color: #e55c00 !important;
    }

    a { color: #ff6600 !important; }
    a:visited { color: #cc5200 !important; }

    /* Dark mode */
    @media (prefers-color-scheme: dark) {
        body {
            background-color: #1e1e1e !important;
            color: #e0e0e0 !important;
        }

        body > center > table,
        #hnmain {
            background-color: #1e1e1e !important;
        }

        td { color: #e0e0e0 !important; }

        input[type="text"], input[type="password"], input[type="email"],
        input[type="url"], input[type="number"], input[type="search"],
        textarea, select {
            background-color: #2a2a2a !important;
            color: #e0e0e0 !important;
            border: 1px solid #444 !important;
        }

        select option {
            background-color: #2a2a2a !important;
            color: #e0e0e0 !important;
        }

        a { color: #ff8533 !important; }
        a:visited { color: #cc6b29 !important; }
    }

    /* Light mode */
    @media (prefers-color-scheme: light) {
        input[type="text"], input[type="password"], input[type="email"],
        input[type="url"], input[type="number"], input[type="search"],
        textarea, select {
            background-color: #fff !important;
            color: #1a1a1a !important;
            border: 1px solid #ccc !important;
        }
    }
    """

    // MARK: - Scroll Observer

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

            guard let host = webView.url?.host, host.contains("ycombinator.com") else { return }

            // Toolbar CSS is handled by the early WKUserScript, but re-inject
            // in case of client-side navigation where user scripts don't re-run
            let toolbarJS = ArticleWebView.cssInjectionJS(css: ArticleWebView.toolbarHideCSS)
            webView.evaluateJavaScript(toolbarJS, completionHandler: nil)

            let path = webView.url?.path ?? ""
            if path == "/user" || path == "/submit" || path.hasPrefix("/submit") {
                let formJS = ArticleWebView.cssInjectionJS(css: ArticleWebView.formStylingCSS)
                webView.evaluateJavaScript(formJS, completionHandler: nil)
            }
        }
    }
}
