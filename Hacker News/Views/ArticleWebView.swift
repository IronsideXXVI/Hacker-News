import SwiftUI
import WebKit

@Observable
class WebViewProxy {
    weak var webView: WKWebView?
    var matchCount: Int = 0
    var currentMatch: Int = 0

    private func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    func countMatches(_ text: String) async {
        guard !text.isEmpty, let webView else {
            matchCount = 0
            currentMatch = 0
            return
        }
        let js = """
        (function() {
            var query = '\(escaped(text))';
            var body = document.body.innerText;
            var count = 0;
            var lower = body.toLowerCase();
            var q = query.toLowerCase();
            var pos = lower.indexOf(q);
            while (pos !== -1) {
                count++;
                pos = lower.indexOf(q, pos + 1);
            }
            return count;
        })()
        """
        do {
            let result = try await webView.evaluateJavaScript(js)
            matchCount = (result as? Int) ?? 0
            currentMatch = matchCount > 0 ? 1 : 0
        } catch {
            matchCount = 0
            currentMatch = 0
        }
    }

    func findNext(_ text: String) {
        guard !text.isEmpty, let webView else { return }
        webView.evaluateJavaScript("window.find('\(escaped(text))', false, false, true)") { [weak self] result, _ in
            guard let self else { return }
            let found = (result as? Bool) ?? false
            if found && self.matchCount > 0 {
                DispatchQueue.main.async {
                    self.currentMatch = self.currentMatch >= self.matchCount ? 1 : self.currentMatch + 1
                }
            }
        }
    }

    func findPrevious(_ text: String) {
        guard !text.isEmpty, let webView else { return }
        webView.evaluateJavaScript("window.find('\(escaped(text))', false, true, true)") { [weak self] result, _ in
            guard let self else { return }
            let found = (result as? Bool) ?? false
            if found && self.matchCount > 0 {
                DispatchQueue.main.async {
                    self.currentMatch = self.currentMatch <= 1 ? self.matchCount : self.currentMatch - 1
                }
            }
        }
    }

    func findFirst(_ text: String) {
        guard !text.isEmpty, let webView else { return }
        // Move selection to start of document so find starts from top
        webView.evaluateJavaScript("window.getSelection().removeAllRanges()") { [weak self] _, _ in
            guard let self, let webView = self.webView else { return }
            webView.evaluateJavaScript("window.find('\(self.escaped(text))', false, false, true)", completionHandler: nil)
        }
    }

    func clearSelection() {
        webView?.evaluateJavaScript("window.getSelection().removeAllRanges()", completionHandler: nil)
        matchCount = 0
        currentMatch = 0
    }
}

struct ArticleWebView: NSViewRepresentable {
    let url: URL
    let adBlockingEnabled: Bool
    let popUpBlockingEnabled: Bool
    let textScale: Double
    var webViewProxy: WebViewProxy?
    @Binding var scrollProgress: Double
    @Binding var isLoading: Bool
    @Binding var loadError: String?
    @Environment(\.colorScheme) private var colorScheme

    private static var cachedContentRuleList: WKContentRuleList?

    init(url: URL, adBlockingEnabled: Bool = true, popUpBlockingEnabled: Bool = true, textScale: Double = 1.0, webViewProxy: WebViewProxy? = nil, scrollProgress: Binding<Double> = .constant(0), isLoading: Binding<Bool> = .constant(false), loadError: Binding<String?> = .constant(nil)) {
        self.url = url
        self.adBlockingEnabled = adBlockingEnabled
        self.popUpBlockingEnabled = popUpBlockingEnabled
        self.textScale = textScale
        self.webViewProxy = webViewProxy
        self._scrollProgress = scrollProgress
        self._isLoading = isLoading
        self._loadError = loadError
    }

    // MARK: - Ad Block Rules

    static let adBlockRulesJSON = """
    [
        {"trigger":{"url-filter":".*\\\\.doubleclick\\\\.net","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\\\.googlesyndication\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\\\.googleadservices\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\\\.google-analytics\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\\\.adnxs\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\\\.outbrain\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\\\.taboola\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\\\.criteo\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\\\.amazon-adsystem\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\\\.quantserve\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\\\.scorecardresearch\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\\\.rubiconproject\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\\\.sharethrough\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\\\.moatads\\\\.com","load-type":["third-party"]},"action":{"type":"block"}}
    ]
    """

    static func precompileAdBlockRules() {
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "HNAdBlockRules",
            encodedContentRuleList: adBlockRulesJSON
        ) { ruleList, error in
            if let ruleList {
                cachedContentRuleList = ruleList
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.applicationNameForUserAgent = "Version/18.3 Safari/605.1.15"

        let toolbarHideScript = WKUserScript(
            source: Self.cssInjectionJS(css: Self.toolbarHideCSS),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(toolbarHideScript)

        let colorSchemeScript = WKUserScript(
            source: Self.colorSchemeMetaJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(colorSchemeScript)

        let scrollScript = WKUserScript(
            source: Self.scrollObserverJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(scrollScript)
        config.userContentController.add(context.coordinator, name: "scrollHandler")

        if adBlockingEnabled, let ruleList = Self.cachedContentRuleList {
            config.userContentController.add(ruleList)
        }

        if popUpBlockingEnabled {
            config.preferences.javaScriptCanOpenWindowsAutomatically = false
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        webView.underPageBackgroundColor = colorScheme == .dark ? NSColor(white: 0.12, alpha: 1) : .white
        webView.pageZoom = CGFloat(textScale)
        webViewProxy?.webView = webView
        context.coordinator.currentURL = url
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        webView.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        webView.underPageBackgroundColor = colorScheme == .dark ? NSColor(white: 0.12, alpha: 1) : .white
        webView.pageZoom = CGFloat(textScale)
        if context.coordinator.currentURL != url {
            webView.evaluateJavaScript(Self.pauseAllMediaJS, completionHandler: nil)
            context.coordinator.currentURL = url
            DispatchQueue.main.async { scrollProgress = 0 }
            webView.load(URLRequest(url: url))
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.loadHTMLString("", baseURL: nil)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "scrollHandler")
        webView.configuration.userContentController.removeAllContentRuleLists()
    }

    // MARK: - Media Cleanup

    private static let pauseAllMediaJS = """
    document.querySelectorAll('video, audio').forEach(el => { el.pause(); el.src = ''; });
    """

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
            color: #ffffff !important;
        }

        body > center > table,
        #hnmain {
            background-color: #1e1e1e !important;
        }

        td, .commtext, .commtext * , font, span, p { color: #ffffff !important; }

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
        td, .commtext, .commtext *, font, span, p { color: #000000 !important; }

        input[type="text"], input[type="password"], input[type="email"],
        input[type="url"], input[type="number"], input[type="search"],
        textarea, select {
            background-color: #fff !important;
            color: #1a1a1a !important;
            border: 1px solid #ccc !important;
        }
    }
    """

    // MARK: - Color Scheme Meta Tag

    private static let colorSchemeMetaJS = """
    (function() {
        var meta = document.createElement('meta');
        meta.name = 'color-scheme';
        meta.content = 'light dark';
        document.head.appendChild(meta);
    })();
    """

    // MARK: - Scroll Observer

    private static let scrollObserverJS = """
    (function() {
        if (window.__scrollObserverInstalled) return;
        window.__scrollObserverInstalled = true;
        function reportScroll() {
            var scrollTop = window.pageYOffset || document.documentElement.scrollTop || document.body.scrollTop || 0;
            var docHeight = Math.max(
                document.body.scrollHeight || 0, document.documentElement.scrollHeight || 0,
                document.body.offsetHeight || 0, document.documentElement.offsetHeight || 0
            );
            var winHeight = window.innerHeight || document.documentElement.clientHeight || 0;
            var h = docHeight - winHeight;
            var progress = h > 0 ? (scrollTop / h) : 0;
            window.webkit.messageHandlers.scrollHandler.postMessage(Math.min(Math.max(progress, 0), 1));
        }
        window.addEventListener('scroll', reportScroll, { passive: true });
        document.addEventListener('scroll', reportScroll, { passive: true });
        window.addEventListener('resize', reportScroll, { passive: true });
        reportScroll();
    })();
    """

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
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

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
                self.parent.loadError = nil
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.loadError = nil
                self.parent.isLoading = false
            }
            webView.evaluateJavaScript(ArticleWebView.scrollObserverJS, completionHandler: nil)

            guard let host = webView.url?.host, host.contains("ycombinator.com") else { return }

            // Toolbar CSS is handled by the early WKUserScript, but re-inject
            // in case of client-side navigation where user scripts don't re-run
            let toolbarJS = ArticleWebView.cssInjectionJS(css: ArticleWebView.toolbarHideCSS)
            webView.evaluateJavaScript(toolbarJS, completionHandler: nil)

            let path = webView.url?.path ?? ""
            if path == "/item" || path == "/user" || path == "/submit" || path.hasPrefix("/submit") {
                let formJS = ArticleWebView.cssInjectionJS(css: ArticleWebView.formStylingCSS)
                webView.evaluateJavaScript(formJS, completionHandler: nil)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.loadError = error.localizedDescription
                self.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.loadError = error.localizedDescription
                self.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
