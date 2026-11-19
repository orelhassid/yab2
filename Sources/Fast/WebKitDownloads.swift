import WebKit
import ObjectiveC

private var downloadAdapterKey: UInt8 = 0

@MainActor
final class WebKitDownloadEvents: NSObject, WKDownloadDelegate {
    let id = UUID()
    weak var listener: (any PageDownloadEvents)?
    // WKDownload's webView can disappear when its tab closes. Retrying in
    // the active tab instead changes the cookie jar/account and can turn
    // an authenticated file into a failed or unrelated download.
    var origin: WKWebView?
    var originURL: URL?
    var originTitle: String?

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        guard let listener else { completionHandler(nil); return }
        var answered = false
        listener.download(download, decideDestinationUsing: response, suggestedFilename: suggestedFilename) { url in
            guard !answered else { return }; answered = true
            completionHandler(url)
        }
    }
    func downloadDidFinish(_ download: WKDownload) { listener?.downloadDidFinish(download) }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        listener?.download(download, didFailWithError: error, resumeData: resumeData)
    }
}

extension WKDownload: PageDownload {
    var supportsPause: Bool { true }
    var isExtensionDownload: Bool {
        ExtensionDownloads.byExtension(self) || eventAdapter.originURL?.scheme == Extensions.scheme
    }
    var page: (any PageHandle)? { (webView ?? eventAdapter.origin) as? any PageHandle }
    var sourceView: NSView? { webView ?? eventAdapter.origin }
    var pageURL: URL? { eventAdapter.originURL }
    var pageTitle: String? { eventAdapter.originTitle }
    var downloadID: UUID { eventAdapter.id }
    private var eventAdapter: WebKitDownloadEvents {
        if let kept = objc_getAssociatedObject(self, &downloadAdapterKey) as? WebKitDownloadEvents { return kept }
        let made = WebKitDownloadEvents()
        made.origin = webView
        made.originURL = webView?.url
        made.originTitle = webView?.title
        objc_setAssociatedObject(self, &downloadAdapterKey, made, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return made
    }
    func cancelDownload(_ done: @escaping @MainActor (Data?) -> Void) {
        cancel { data in Task { @MainActor in done(data) } }
    }
    func restartDownload(from resumeData: Data?, fallback: (any PageHandle)?,
                         done: @escaping @MainActor ((any PageDownload)?) -> Void) {
        guard let view = webView ?? eventAdapter.origin else { done(nil); return }
        if let resumeData { view.resumeDownload(fromResumeData: resumeData) { done($0) } }
        else if let originalRequest { view.startDownload(using: originalRequest) { done($0) } }
        else { done(nil) }
    }
    var downloadEvents: (any PageDownloadEvents)? {
        get { eventAdapter.listener }
        set {
            eventAdapter.listener = newValue
            if newValue != nil { delegate = eventAdapter }
            else if delegate === eventAdapter { delegate = nil }
        }
    }
}

extension WebKitPageEvents {
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        SiteDownloads.became(download, in: webView, url: webView.url)
        guard let page = webView as? PageView else { return }
        listener?.page(page, became: download, isMainFrame: navigationAction.targetFrame?.isMainFrame != false)
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        if navigationResponse.isForMainFrame { DiaryPage.fit(webView.configuration.userContentController, to: webView.url) }
        SiteDownloads.became(download, in: webView, url: webView.url)
        guard let page = webView as? PageView else { return }
        listener?.page(page, became: download, isMainFrame: navigationResponse.isForMainFrame)
    }
}

extension Browser {
    // Compatibility for standalone WebKit surfaces and download fixtures.
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        SiteDownloads.became(download, in: webView, url: webView.url)
        if let page = webView as? any PageHandle {
            self.page(page, became: download, isMainFrame: navigationAction.targetFrame?.isMainFrame != false)
        } else { keep(download) }
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        if navigationResponse.isForMainFrame { DiaryPage.fit(webView.configuration.userContentController, to: webView.url) }
        SiteDownloads.became(download, in: webView, url: webView.url)
        if let page = webView as? any PageHandle {
            self.page(page, became: download, isMainFrame: navigationResponse.isForMainFrame)
        } else { keep(download) }
    }

}

extension PageHandle {
    func webKitOnlyFetched(_ fetching: [URL?]) -> Bool {
        if let chromium = self as? ChromiumPage { return chromium.onlyFetched(fetching) }
        guard let webKit else { return false }
        let list = webKit.backForwardList
        guard list.backItem == nil, list.forwardItem == nil else { return false }
        if let shown = list.currentItem?.url, shown.absoluteString != "about:blank",
           !fetching.contains(where: { $0 == shown }) { return false }
        return true
    }
    func webKitClose(in browser: Browser) {
        if let webKit { browser.webViewDidClose(webKit) } else { browser.pageClosed(self) }
    }
}

/// The WebKit extension system still identifies native downloads. Ordinary
/// download ownership, destination, progress, cancel and retry use the seam;
/// these hooks alone remain specific to that extension implementation.
extension PageDownload {
    var webKitDownload: WKDownload? { self as? WKDownload }
    var webKitByExtension: Bool { webKitDownload.map(ExtensionDownloads.byExtension) == true }
    func webKitCreated() { if let webKitDownload { ExtensionDownloads.created(webKitDownload) } }
    func webKitNamed(file: URL, response: URLResponse) {
        if let webKitDownload { ExtensionDownloads.named(webKitDownload, file: file, response: response) }
    }
    func webKitFinished(file: URL?) { if let webKitDownload { ExtensionDownloads.finished(webKitDownload, file: file) } }
    func webKitFailed(resumable: Bool, canceled: Bool) {
        if let webKitDownload { ExtensionDownloads.failed(webKitDownload, resumable: resumable, canceled: canceled) }
    }
    func webKitCarried(from old: ObjectIdentifier) { if let webKitDownload { ExtensionDownloads.carried(webKitDownload, from: old) } }
}
