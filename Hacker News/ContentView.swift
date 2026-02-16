//
//  ContentView.swift
//  Hacker News
//
//  Created by Dylan Ironside on 2/16/26.
//

import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct ContentView: View {
    var body: some View {
        WebView(url: URL(string: "https://news.ycombinator.com/")!)
            .frame(minWidth: 800, minHeight: 600)
    }
}

#Preview {
    ContentView()
}
