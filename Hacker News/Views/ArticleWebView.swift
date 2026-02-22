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

    // MARK: - Reader Mode

    private static let readabilityJS: String? = {
        guard let url = Bundle.main.url(forResource: "Readability", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return source
    }()

    private static let readerableJS: String? = {
        guard let url = Bundle.main.url(forResource: "Readability-readerable", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return source
    }()

    func checkReadability() async -> Bool {
        guard let webView,
              let readerableJS = Self.readerableJS else { return false }
        let js = """
        (function() {
            \(readerableJS)
            return isProbablyReaderable(document);
        })()
        """
        do {
            let result = try await webView.evaluateJavaScript(js)
            return (result as? Bool) ?? false
        } catch {
            return false
        }
    }

    func activateReaderMode(pageZoom: CGFloat) async {
        guard let webView,
              let readabilityJS = Self.readabilityJS else { return }
        let js = """
        (function() {
            \(readabilityJS)
            var article = new Readability(document.cloneNode(true)).parse();
            if (!article) return null;
            return JSON.stringify({
                title: article.title || '',
                byline: article.byline || '',
                siteName: article.siteName || '',
                content: article.content || ''
            });
        })()
        """
        do {
            guard let jsonString = try await webView.evaluateJavaScript(js) as? String,
                  let data = jsonString.data(using: .utf8),
                  let article = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
            let title = article["title"] ?? ""
            let byline = article["byline"] ?? ""
            let siteName = article["siteName"] ?? ""
            let content = article["content"] ?? ""
            let html = Self.buildReaderHTML(title: title, byline: byline, siteName: siteName, content: content, pageZoom: pageZoom)
            webView.loadHTMLString(html, baseURL: webView.url)
        } catch {
            return
        }
    }

    func prepareForReaderMode() {
        if let coordinator = webView?.navigationDelegate as? ArticleWebView.Coordinator {
            coordinator.isActivatingReaderMode = true
        }
    }

    func deactivateReaderMode(url: URL) {
        webView?.load(URLRequest(url: url))
    }

    private static func buildReaderHTML(title: String, byline: String, siteName: String, content: String, pageZoom: CGFloat) -> String {
        let escapedTitle = title.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let escapedByline = byline.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let escapedSiteName = siteName.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let fontSize = 18.0 * Double(pageZoom)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <style>
            * { box-sizing: border-box; }
            body {
                font-family: 'New York', 'Georgia', 'Times New Roman', serif;
                font-size: \(fontSize)px;
                line-height: 1.7;
                max-width: 680px;
                margin: 0 auto;
                padding: 40px 20px 80px;
                color: #1a1a1a;
                background: #ffffff;
                -webkit-font-smoothing: antialiased;
            }
            @media (prefers-color-scheme: dark) {
                body { color: #e0e0e0; background: #1a1a1a; }
                a { color: #ff8533; }
                a:visited { color: #cc6b29; }
                img { opacity: 0.9; }
                blockquote { border-left-color: #444; }
                hr { border-color: #333; }
                code, pre { background: #2a2a2a; }
                table, th, td { border-color: #444; }
            }
            .reader-header { margin-bottom: 32px; }
            .reader-title {
                font-size: 1.8em;
                line-height: 1.25;
                font-weight: 700;
                margin: 0 0 12px 0;
            }
            .reader-meta {
                font-size: 0.8em;
                color: #666;
                font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
            }
            @media (prefers-color-scheme: dark) {
                .reader-meta { color: #999; }
            }
            .reader-content img {
                max-width: 100%;
                height: auto;
                border-radius: 4px;
            }
            .reader-content a { color: #ff6600; }
            .reader-content a:visited { color: #cc5200; }
            @media (prefers-color-scheme: dark) {
                .reader-content a { color: #ff8533; }
                .reader-content a:visited { color: #cc6b29; }
            }
            .reader-content p { margin: 0 0 1em 0; }
            .reader-content h1, .reader-content h2, .reader-content h3,
            .reader-content h4, .reader-content h5, .reader-content h6 {
                line-height: 1.3;
                margin-top: 1.5em;
                margin-bottom: 0.5em;
            }
            .reader-content blockquote {
                margin: 1em 0;
                padding: 0 0 0 1em;
                border-left: 3px solid #ddd;
                color: #555;
            }
            @media (prefers-color-scheme: dark) {
                .reader-content blockquote { color: #aaa; }
            }
            .reader-content pre {
                overflow-x: auto;
                padding: 12px;
                background: #f5f5f5;
                border-radius: 6px;
                font-size: 0.85em;
                line-height: 1.5;
            }
            .reader-content code {
                font-size: 0.9em;
                background: #f5f5f5;
                padding: 2px 4px;
                border-radius: 3px;
            }
            .reader-content pre code {
                background: none;
                padding: 0;
            }
            .reader-content table {
                border-collapse: collapse;
                width: 100%;
                margin: 1em 0;
            }
            .reader-content th, .reader-content td {
                border: 1px solid #ddd;
                padding: 8px 12px;
                text-align: left;
            }
            .reader-content figure {
                margin: 1.5em 0;
            }
            .reader-content figcaption {
                font-size: 0.85em;
                color: #666;
                margin-top: 8px;
            }
            @media (prefers-color-scheme: dark) {
                .reader-content figcaption { color: #999; }
            }
        </style>
        </head>
        <body>
        <div class="reader-header">
            <h1 class="reader-title">\(escapedTitle)</h1>
            <div class="reader-meta">
                \(!escapedByline.isEmpty ? escapedByline : "")\(!escapedByline.isEmpty && !escapedSiteName.isEmpty ? " · " : "")\(!escapedSiteName.isEmpty ? escapedSiteName : "")
            </div>
        </div>
        <div class="reader-content">
            \(content)
        </div>
        </body>
        </html>
        """
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
                    .hn-inline-reply { margin: 8px 0 4px 0; font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif; } \\
                    .hn-inline-reply textarea { width: 100%; min-height: 80px; max-height: 300px; font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif; font-size: 13px; border: 1px solid #d5d5cf; border-radius: 6px; padding: 8px 10px; box-sizing: border-box; outline: none; transition: border-color 0.2s, box-shadow 0.2s; resize: vertical; background: #fff; color: #1a1a1a; } \\
                    .hn-inline-reply textarea:focus { border-color: #ff6600; box-shadow: 0 0 0 3px rgba(255, 102, 0, 0.25); } \\
                    .hn-reply-actions { display: flex; align-items: center; gap: 8px; margin-top: 6px; } \\
                    .hn-reply-submit { background: #ff6600; border: none; border-radius: 6px; padding: 5px 14px; color: white; font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif; font-size: 12px; font-weight: 500; cursor: pointer; transition: background-color 0.15s; } \\
                    .hn-reply-submit:hover { background: #e55c00; } \\
                    .hn-reply-submit:disabled { background: #ccc; cursor: default; } \\
                    .hn-reply-cancel { background: none; border: 1px solid #d5d5cf; border-radius: 6px; padding: 4px 12px; color: #666; font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif; font-size: 12px; cursor: pointer; transition: all 0.15s; } \\
                    .hn-reply-cancel:hover { border-color: #ff6600; color: #ff6600; } \\
                    .hn-reply-status { font-size: 12px; color: #828282; } \\
                    @media (prefers-color-scheme: dark) { \\
                        .hn-inline-reply textarea { background: #2a2a2a; color: #e0e0e0; border-color: #444; } \\
                        .hn-reply-cancel { border-color: #444; color: #999; } \\
                        .hn-reply-cancel:hover { border-color: #ff8533; color: #ff8533; } \\
                        .hn-reply-submit:disabled { background: #555; } \\
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

            function needsPipe(el) {
                var prev = el.previousSibling;
                if (!prev) return true;
                if (prev.nodeType === 3 && prev.textContent.trim() === '|') return false;
                if (prev.nodeType === 3 && prev.textContent.indexOf('|') !== -1) return false;
                return true;
            }
            document.querySelectorAll('.comhead').forEach(function(head) {
                var age = head.querySelector('.age');
                if (age && needsPipe(age)) {
                    age.parentNode.insertBefore(document.createTextNode(' | '), age);
                }
                var togg = head.querySelector('.togg');
                if (togg && needsPipe(togg)) {
                    togg.parentNode.insertBefore(document.createTextNode(' | '), togg);
                }
                var walker = document.createTreeWalker(head, NodeFilter.SHOW_TEXT, null);
                var node;
                while (node = walker.nextNode()) {
                    if (node.textContent.indexOf('[flagged]') !== -1) {
                        var text = node.textContent;
                        var idx = text.indexOf('[flagged]');
                        var before = text.substring(0, idx);
                        var after = text.substring(idx + 9);
                        node.textContent = before + '| [flagged]';
                        if (after) {
                            node.parentNode.insertBefore(document.createTextNode(after), node.nextSibling);
                        }
                        break;
                    }
                }
            });

            var nestColors = ['#ff6600', '#3b82f6', '#a855f7', '#10b981', '#f59e0b', '#ef4444', '#06b6d4', '#ec4899'];
            table.querySelectorAll('tr.athing.comtr').forEach(function(row) {
                var indTd = row.querySelector('td.ind');
                var indent = indTd ? parseInt(indTd.getAttribute('indent') || '0', 10) : 0;
                var defTd = row.querySelector('td.default');
                if (defTd && indent > 0) {
                    defTd.style.borderLeftColor = nestColors[(indent - 1) % nestColors.length];
                }
            });

            // Inline reply handling
            table.querySelectorAll('a[href^="reply"]').forEach(function(replyLink) {
                replyLink.addEventListener('click', function(e) {
                    e.preventDefault();
                    var commentRow = replyLink.closest('tr.athing.comtr');
                    if (!commentRow) return;

                    var existing = commentRow.querySelector('.hn-inline-reply');
                    if (existing) { existing.remove(); return; }

                    document.querySelectorAll('.hn-inline-reply').forEach(function(f) { f.remove(); });

                    var container = document.createElement('div');
                    container.className = 'hn-inline-reply';

                    var ta = document.createElement('textarea');
                    ta.placeholder = 'Write your reply...';
                    container.appendChild(ta);

                    var actions = document.createElement('div');
                    actions.className = 'hn-reply-actions';

                    var submitBtn = document.createElement('button');
                    submitBtn.className = 'hn-reply-submit';
                    submitBtn.textContent = 'Reply';

                    var cancelBtn = document.createElement('button');
                    cancelBtn.className = 'hn-reply-cancel';
                    cancelBtn.textContent = 'Cancel';

                    var statusEl = document.createElement('span');
                    statusEl.className = 'hn-reply-status';

                    actions.appendChild(submitBtn);
                    actions.appendChild(cancelBtn);
                    actions.appendChild(statusEl);
                    container.appendChild(actions);

                    var defTd2 = commentRow.querySelector('td.default');
                    if (defTd2) defTd2.appendChild(container);
                    ta.focus();

                    var replyHref = replyLink.getAttribute('href');

                    submitBtn.addEventListener('click', function() {
                        var text = ta.value.trim();
                        if (!text) {
                            statusEl.textContent = 'Please enter a reply.';
                            statusEl.style.color = '#ef4444';
                            return;
                        }
                        submitBtn.disabled = true;
                        cancelBtn.disabled = true;
                        statusEl.textContent = 'Submitting...';
                        statusEl.style.color = '#828282';

                        fetch(replyHref, { credentials: 'include' })
                            .then(function(resp) {
                                if (!resp.ok) throw new Error('Failed to load reply page');
                                return resp.text();
                            })
                            .then(function(html) {
                                var parser = new DOMParser();
                                var doc = parser.parseFromString(html, 'text/html');
                                var form = doc.querySelector('form[action="comment"]');
                                if (!form) throw new Error('Not logged in or reply not available');
                                var hmacInput = form.querySelector('input[name="hmac"]');
                                var parentInput = form.querySelector('input[name="parent"]');
                                var gotoInput = form.querySelector('input[name="goto"]');
                                if (!hmacInput || !parentInput) throw new Error('Could not extract reply token');
                                var formData = new URLSearchParams();
                                formData.append('parent', parentInput.value);
                                formData.append('goto', gotoInput ? gotoInput.value : '');
                                formData.append('hmac', hmacInput.value);
                                formData.append('text', text);
                                return fetch('/comment', {
                                    method: 'POST',
                                    credentials: 'include',
                                    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                                    body: formData.toString()
                                });
                            })
                            .then(function(resp) {
                                if (!resp.ok) throw new Error('Failed to submit reply');
                                statusEl.textContent = 'Reply posted!';
                                statusEl.style.color = '#10b981';
                                setTimeout(function() { window.location.reload(); }, 1000);
                            })
                            .catch(function(err) {
                                statusEl.textContent = err.message || 'Error submitting reply';
                                statusEl.style.color = '#ef4444';
                                submitBtn.disabled = false;
                                cancelBtn.disabled = false;
                            });
                    });

                    cancelBtn.addEventListener('click', function() { container.remove(); });
                });
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
    var onReadabilityChecked: ((Bool) -> Void)?
    @Binding var scrollProgress: Double
    @Binding var isLoading: Bool
    @Binding var loadError: String?
    @Environment(\.colorScheme) private var colorScheme

    private static var cachedContentRuleList: WKContentRuleList?

    init(url: URL, adBlockingEnabled: Bool = true, popUpBlockingEnabled: Bool = true, textScale: Double = 1.0, webViewProxy: WebViewProxy? = nil, onCommentSortChanged: ((String) -> Void)? = nil, onReadabilityChecked: ((Bool) -> Void)? = nil, scrollProgress: Binding<Double> = .constant(0), isLoading: Binding<Bool> = .constant(false), loadError: Binding<String?> = .constant(nil)) {
        self.url = url
        self.adBlockingEnabled = adBlockingEnabled
        self.popUpBlockingEnabled = popUpBlockingEnabled
        self.textScale = textScale
        self.webViewProxy = webViewProxy
        self.onCommentSortChanged = onCommentSortChanged
        self.onReadabilityChecked = onReadabilityChecked
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
            forMainFrameOnly: true
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
        webView.evaluateJavaScript("if (location.hostname.indexOf('ycombinator.com') !== -1) { document.documentElement.style.colorScheme = '\(scheme)'; }", completionHandler: nil)
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
        if (location.hostname.indexOf('ycombinator.com') !== -1) {
            var meta = document.createElement('meta');
            meta.name = 'color-scheme';
            meta.content = 'light dark';
            document.head.appendChild(meta);
        }
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
        var isActivatingReaderMode = false

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
            if isActivatingReaderMode {
                return
            }
            DispatchQueue.main.async {
                self.parent.isLoading = true
                self.parent.loadError = nil
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if isActivatingReaderMode {
                isActivatingReaderMode = false
                DispatchQueue.main.async {
                    self.parent.isLoading = false
                }
                webView.evaluateJavaScript(ArticleWebView.scrollObserverJS, completionHandler: nil)
                return
            }

            DispatchQueue.main.async {
                self.parent.loadError = nil
            }
            webView.evaluateJavaScript(ArticleWebView.scrollObserverJS, completionHandler: nil)

            guard let host = webView.url?.host, host.contains("ycombinator.com") else {
                // For non-HN pages with a readability callback, defer isLoading = false
                // to the callback so the loading overlay stays up until reader mode
                // HTML is ready (if reader mode is active).
                if let proxy = parent.webViewProxy, let callback = parent.onReadabilityChecked {
                    Task { @MainActor in
                        let isReaderable = await proxy.checkReadability()
                        callback(isReaderable)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.parent.isLoading = false
                    }
                }
                return
            }

            DispatchQueue.main.async {
                self.parent.isLoading = false
            }

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
