import SwiftUI
import WebKit

@MainActor
final class WebViewStore: NSObject, ObservableObject {
    @Published private(set) var created: [String] = []
    @Published private(set) var loading: Set<String> = []
    @Published private(set) var httpErrors: [String: Int] = [:]

    private var views: [String: WKWebView] = [:]
    private var navigations: [String: WKNavigation] = [:]
    private var timeouts: [String: Task<Void, Never>] = [:]
    private var failedURLs: [String: URL] = [:]

    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    func ensure(_ service: AIService) {
        guard service.kind == .web,
              views[service.id] == nil,
              let raw = service.url,
              let url = URL(string: raw) else { return }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.isElementFullscreenEnabled = true
        Log.write("web start: \(service.id)")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Self.userAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        // 页面渲染前用窗口底色，避免打开瞬间的白闪
        webView.underPageBackgroundColor = .windowBackgroundColor

        views[service.id] = webView
        created.append(service.id)
        begin(service.id, webView.load(URLRequest(url: url)))
    }

    func view(for id: String) -> WKWebView? {
        views[id]
    }

    func has(_ id: String) -> Bool {
        views[id] != nil
    }

    func isLoading(_ id: String) -> Bool {
        loading.contains(id)
    }

    func httpError(_ id: String) -> Int? {
        httpErrors[id]
    }

    private func begin(_ id: String, _ navigation: WKNavigation?) {
        guard let navigation else { return }
        if navigations[id] === navigation { return }
        timeouts[id]?.cancel()
        navigations[id] = navigation
        loading.insert(id)
        httpErrors.removeValue(forKey: id)
        failedURLs.removeValue(forKey: id)
        timeouts[id] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, self.navigations[id] === navigation else { return }
            self.loading.remove(id)
            self.httpErrors[id] = -1
        }
    }

    private func finish(_ id: String) {
        timeouts.removeValue(forKey: id)?.cancel()
        navigations.removeValue(forKey: id)
        loading.remove(id)
    }

    func retainServices(_ ids: Set<String>) {
        for id in created where !ids.contains(id) {
            finish(id)
            let view = views.removeValue(forKey: id)
            view?.navigationDelegate = nil
            view?.stopLoading()
            httpErrors.removeValue(forKey: id)
            failedURLs.removeValue(forKey: id)
            created.removeAll { $0 == id }
        }
    }

    private func id(for webView: WKWebView) -> String? {
        views.first { $0.value === webView }?.key
    }

    func reload(_ service: AIService) {
        guard let view = views[service.id] else { ensure(service); return }
        if let url = failedURLs[service.id] {
            begin(service.id, view.load(URLRequest(url: url)))
        } else if let navigation = view.reload() {
            begin(service.id, navigation)
        } else {
            goHome(service)
        }
    }

    func goHome(_ service: AIService) {
        guard let view = views[service.id] else { ensure(service); return }
        guard let raw = service.url, let url = URL(string: raw) else { return }
        begin(service.id, view.load(URLRequest(url: url)))
    }

    func openInBrowser(_ service: AIService) {
        if let url = failedURLs[service.id] ?? views[service.id]?.url ?? service.url.flatMap(URL.init(string:)),
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension WebViewStore: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if let id = id(for: webView) { begin(id, navigation) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let id = id(for: webView), navigations[id] === navigation else { return }
        finish(id)
        if httpErrors[id] == -1 { httpErrors.removeValue(forKey: id) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard let id = id(for: webView), navigations[id] === navigation else { return }
        finish(id)
        let error = error as NSError
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return }
        failedURLs[id] = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL
        httpErrors[id] = -1
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFail: navigation, withError: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let id = id(for: webView) else { return }
        finish(id)
        httpErrors[id] = -1
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse,
           response.statusCode >= 400,
           let id = id(for: webView) {
            httpErrors[id] = response.statusCode
            timeouts.removeValue(forKey: id)?.cancel()
            loading.remove(id)
            Log.write("http \(response.statusCode): \(id)")
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

enum Log {
    static let url = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Logs/AI-Workbench.log")

    static func write(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

struct WebViewContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
