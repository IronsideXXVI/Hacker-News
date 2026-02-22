import SwiftUI
import WebKit

@Observable
class WebViewProxy {
    weak var webView: WKWebView? {
        didSet {
            backForwardObservation?.invalidate()
            guard let webView else {
                canGoBack = false
                canGoForward = false
                return
            }
            backForwardObservation = webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.canGoBack = wv.canGoBack }
            }
            forwardObservation = webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.canGoForward = wv.canGoForward }
            }
        }
    }
    var canGoBack = false
    var canGoForward = false
    var matchCount: Int = 0
    var currentMatch: Int = 0
    private var backForwardObservation: NSKeyValueObservation?
    private var forwardObservation: NSKeyValueObservation?

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }

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

    var commentSort: HNCommentSort = .default

    func injectCommentSortUI() {
        guard let webView else { return }
        let jsMode: String
        switch commentSort {
        case .default: jsMode = "default"
        case .newest: jsMode = "newest"
        case .oldest: jsMode = "oldest"
        case .mostReplies: jsMode = "mostReplies"
        }
        webView.evaluateJavaScript(Self.commentSortUIJS(activeSort: jsMode), completionHandler: nil)
    }

    private static func commentSortUIJS(activeSort: String) -> String {
        """
        (function() {
            var table = document.querySelector('table.comment-tree');
            if (!table) return;

            if (!window.__hnOriginalOrder) {
                window.__hnOriginalOrder = Array.from(table.querySelectorAll('tr.athing.comtr'));
            }

            var existing = document.getElementById('hn-sort-bar');
            if (existing) existing.remove();
            if (!document.getElementById('hn-sort-style')) {
                var style = document.createElement('style');
                style.id = 'hn-sort-style';
                style.textContent = '\\
                    #hn-sort-bar { padding: 8px 0; margin: 4px 0 8px 0; display: flex; align-items: center; gap: 6px; font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif; } \\
                    #hn-sort-bar .hn-sort-label { font-size: 12px; color: #828282; margin-right: 2px; } \\
                    .hn-sort-btn { background: none; border: 1px solid #d5d5cf; border-radius: 6px; padding: 4px 10px; cursor: pointer; font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif; font-size: 12px; color: #666; transition: all 0.15s ease; } \\
                    .hn-sort-btn:hover { border-color: #ff6600; color: #ff6600; } \\
                    .hn-sort-btn.active { background: #ff6600; border-color: #ff6600; color: white; } \\
                    tr.athing.comtr > td > table > tbody > tr > td.ind { background: transparent; } \\
                    tr.athing.comtr > td > table > tbody > tr > td.votelinks { background: transparent; } \\
                    tr.athing.comtr > td > table > tbody > tr > td.default { background: rgb(234, 234, 234); border-radius: 8px; padding: 6px 8px; margin: 4px 0; border-left: 3px solid transparent; } \\
                    .fatitem { background: rgb(234, 234, 234); border-radius: 8px; padding: 8px; width: 100% !important; box-sizing: border-box; } \\
                    @media (prefers-color-scheme: dark) { \\
                        .hn-sort-btn { border-color: #444; color: #999; } \\
                        .hn-sort-btn:hover { border-color: #ff8533; color: #ff8533; } \\
                        .hn-sort-btn.active { background: #ff6600; border-color: #ff6600; color: white; } \\
                        #hn-sort-bar .hn-sort-label { color: #666; } \\
                        tr.athing.comtr > td > table > tbody > tr > td.default { background: rgb(51, 51, 51); } \\
                        .fatitem { background: rgb(51, 51, 51); } \\
                    } \\
                ';
                document.head.appendChild(style);
            }

            var sortBar = document.createElement('div');
            sortBar.id = 'hn-sort-bar';

            var label = document.createElement('span');
            label.className = 'hn-sort-label';
            label.textContent = 'Sort:';
            sortBar.appendChild(label);

            var modes = [
                { id: 'default', label: 'Default' },
                { id: 'newest', label: 'Newest' },
                { id: 'oldest', label: 'Oldest' },
                { id: 'mostReplies', label: 'Most Replies' }
            ];

            var activeSort = '\(activeSort)';

            modes.forEach(function(m) {
                var btn = document.createElement('button');
                btn.className = 'hn-sort-btn' + (m.id === activeSort ? ' active' : '');
                btn.setAttribute('data-sort', m.id);
                btn.textContent = m.label;
                btn.addEventListener('click', function() {
                    sortBar.querySelectorAll('.hn-sort-btn').forEach(function(b) { b.classList.remove('active'); });
                    btn.classList.add('active');
                    doSort(m.id);
                    try { window.webkit.messageHandlers.commentSortHandler.postMessage(m.id); } catch(e) {}
                });
                sortBar.appendChild(btn);
            });

            table.parentNode.insertBefore(sortBar, table);

            var addBtn = document.querySelector('input[value="add comment"]');
            if (addBtn) {
                var btnLeft = addBtn.getBoundingClientRect().left;
                var barLeft = sortBar.getBoundingClientRect().left;
                var offset = btnLeft - barLeft;
                if (offset > 0) sortBar.style.paddingLeft = offset + 'px';
            }

            var nestColors = ['#ff6600', '#3b82f6', '#a855f7', '#10b981', '#f59e0b', '#ef4444', '#06b6d4', '#ec4899'];
            table.querySelectorAll('tr.athing.comtr').forEach(function(row) {
                var indTd = row.querySelector('td.ind');
                var indent = indTd ? parseInt(indTd.getAttribute('indent') || '0', 10) : 0;
                var defTd = row.querySelector('td.default');
                if (defTd && indent > 0) {
                    defTd.style.borderLeftColor = nestColors[(indent - 1) % nestColors.length];
                }
            });

            function doSort(mode) {
                var parent = table.querySelector('tbody') || table;
                if (mode === 'default') {
                    var frag = document.createDocumentFragment();
                    window.__hnOriginalOrder.forEach(function(row) { frag.appendChild(row); });
                    parent.appendChild(frag);
                    fixPrevNext();
                    return;
                }

                var allRows = Array.from(parent.querySelectorAll('tr.athing.comtr'));
                var threads = [];
                var currentThread = null;

                allRows.forEach(function(row) {
                    var indTd = row.querySelector('td.ind');
                    var indent = indTd ? parseInt(indTd.getAttribute('indent') || '0', 10) : 0;
                    if (indent === 0) {
                        currentThread = { root: row, children: [], timestamp: 0, replyCount: 0 };
                        threads.push(currentThread);
                    } else if (currentThread) {
                        currentThread.children.push(row);
                    }
                });

                threads.forEach(function(thread) {
                    var ageSpan = thread.root.querySelector('span.age');
                    var title = ageSpan ? (ageSpan.getAttribute('title') || '') : '';
                    var parts = title.split(' ');
                    thread.timestamp = parts.length >= 2 ? parseInt(parts[parts.length - 1], 10) : 0;
                    if (isNaN(thread.timestamp)) {
                        var dateVal = Date.parse(parts[0]);
                        thread.timestamp = isNaN(dateVal) ? 0 : dateVal / 1000;
                    }
                    thread.replyCount = thread.children.length;
                });

                if (mode === 'newest') {
                    threads.sort(function(a, b) { return b.timestamp - a.timestamp; });
                } else if (mode === 'oldest') {
                    threads.sort(function(a, b) { return a.timestamp - b.timestamp; });
                } else if (mode === 'mostReplies') {
                    threads.sort(function(a, b) { return b.replyCount - a.replyCount; });
                }

                var frag = document.createDocumentFragment();
                threads.forEach(function(thread) {
                    frag.appendChild(thread.root);
                    thread.children.forEach(function(child) { frag.appendChild(child); });
                });
                parent.appendChild(frag);
                fixPrevNext();
            }

            function fixPrevNext() {
                if (!window.__hnOriginalPrevNext) {
                    window.__hnOriginalPrevNext = [];
                    table.querySelectorAll('tr.athing.comtr').forEach(function(row) {
                        row.querySelectorAll('.comhead a').forEach(function(a) {
                            var text = a.textContent.trim();
                            if (text === 'prev' || text === 'next') {
                                window.__hnOriginalPrevNext.push({ link: a, href: a.getAttribute('href'), display: a.style.display, prevText: a.previousSibling ? a.previousSibling.textContent : '' });
                            }
                        });
                    });
                }
                window.__hnOriginalPrevNext.forEach(function(entry) {
                    entry.link.style.display = '';
                    if (entry.link.previousSibling && entry.prevText) entry.link.previousSibling.textContent = entry.prevText;
                });
                var parent = table.querySelector('tbody') || table;
                var allRows = Array.from(parent.querySelectorAll('tr.athing.comtr'));
                allRows.forEach(function(row, rowIndex) {
                    var indTd = row.querySelector('td.ind');
                    var indent = indTd ? parseInt(indTd.getAttribute('indent') || '0', 10) : 0;
                    row.querySelectorAll('.comhead a').forEach(function(a) {
                        var text = a.textContent.trim();
                        if (text !== 'prev' && text !== 'next') return;
                        var dir = text === 'next' ? 1 : -1;
                        var targetId = null;
                        for (var i = rowIndex + dir; i >= 0 && i < allRows.length; i += dir) {
                            var td = allRows[i].querySelector('td.ind');
                            var ci = td ? parseInt(td.getAttribute('indent') || '0', 10) : 0;
                            if (ci === indent) { targetId = allRows[i].id; break; }
                            if (ci < indent) break;
                        }
                        if (targetId) {
                            var href = a.getAttribute('href') || '';
                            a.setAttribute('href', href.split('#')[0] + '#' + targetId);
                        } else {
                            a.style.display = 'none';
                            if (a.previousSibling && a.previousSibling.nodeType === 3) {
                                a.previousSibling.textContent = a.previousSibling.textContent.replace(/\\s*\\|\\s*$/, '');
                            }
                        }
                    });
                });
            }

            if (activeSort !== 'default') {
                doSort(activeSort);
            }
        })();
        """
    }
}

struct ArticleWebView: NSViewRepresentable {
    let url: URL
    let adBlockingEnabled: Bool
    let popUpBlockingEnabled: Bool
    let textScale: Double
    var webViewProxy: WebViewProxy?
    var onCommentSortChanged: ((String) -> Void)?
    @Binding var scrollProgress: Double
    @Binding var isLoading: Bool
    @Binding var loadError: String?
    @Environment(\.colorScheme) private var colorScheme

    private static var cachedContentRuleList: WKContentRuleList?

    init(url: URL, adBlockingEnabled: Bool = true, popUpBlockingEnabled: Bool = true, textScale: Double = 1.0, webViewProxy: WebViewProxy? = nil, onCommentSortChanged: ((String) -> Void)? = nil, scrollProgress: Binding<Double> = .constant(0), isLoading: Binding<Bool> = .constant(false), loadError: Binding<String?> = .constant(nil)) {
        self.url = url
        self.adBlockingEnabled = adBlockingEnabled
        self.popUpBlockingEnabled = popUpBlockingEnabled
        self.textScale = textScale
        self.webViewProxy = webViewProxy
        self.onCommentSortChanged = onCommentSortChanged
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

        let formStylingScript = WKUserScript(
            source: Self.earlyFormStylingJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(formStylingScript)

        let scrollScript = WKUserScript(
            source: Self.scrollObserverJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(scrollScript)
        config.userContentController.add(context.coordinator, name: "scrollHandler")
        config.userContentController.add(context.coordinator, name: "commentSortHandler")

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
        let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)!
        webView.appearance = appearance
        appearance.performAsCurrentDrawingAppearance {
            webView.underPageBackgroundColor = .windowBackgroundColor
        }
        webView.pageZoom = CGFloat(textScale)
        webViewProxy?.webView = webView
        context.coordinator.currentURL = url
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)!
        webView.appearance = appearance
        appearance.performAsCurrentDrawingAppearance {
            webView.underPageBackgroundColor = .windowBackgroundColor
        }
        let scheme = colorScheme == .dark ? "dark" : "light"
        webView.evaluateJavaScript("document.documentElement.style.colorScheme = '\(scheme)'", completionHandler: nil)
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
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "commentSortHandler")
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

    private static var earlyFormStylingJS: String {
        return """
        if (location.hostname.indexOf('ycombinator.com') !== -1) {
            \(cssInjectionJS(css: formStylingCSS))
        }
        """
    }

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
            background-color: transparent !important;
            color: #ffffff !important;
        }

        body > center > table,
        #hnmain {
            background-color: transparent !important;
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
        body {
            background-color: transparent !important;
            color: #1a1a1a !important;
        }

        body > center > table,
        #hnmain {
            background-color: transparent !important;
        }

        td, .commtext, .commtext *, font, span, p { color: #1a1a1a !important; }

        input[type="text"], input[type="password"], input[type="email"],
        input[type="url"], input[type="number"], input[type="search"],
        textarea, select {
            background-color: #ffffff !important;
            color: #1a1a1a !important;
            border: 1px solid #d5d5cf !important;
        }

        select option {
            background-color: #ffffff !important;
            color: #1a1a1a !important;
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
            if message.name == "commentSortHandler", let mode = message.body as? String {
                DispatchQueue.main.async {
                    self.parent.onCommentSortChanged?(mode)
                }
                return
            }
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

            let formJS = ArticleWebView.cssInjectionJS(css: ArticleWebView.formStylingCSS)
            webView.evaluateJavaScript(formJS, completionHandler: nil)

            parent.webViewProxy?.injectCommentSortUI()
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
