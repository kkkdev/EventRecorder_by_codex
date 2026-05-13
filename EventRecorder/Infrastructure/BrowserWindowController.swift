import AppKit
import Foundation
import WebKit

@MainActor
public protocol BrowserWindowControlling: AnyObject {
    var hasWindow: Bool { get }
    func open(url: URL)
    func openFullScreen(url: URL)
    func toggleFullScreen()
    func openStartupBrowserIfNeeded()
}

@MainActor
public final class BrowserWindowController: NSObject, ObservableObject, BrowserWindowControlling {
    @Published public private(set) var currentURL: URL?
    public var hasWindow: Bool { window != nil }

    private var window: NSWindow?
    private var webView: WKWebView?
    private static let startupURL = URL(string: "about:blank")!

    public override init() {
        super.init()
    }

    public func open(url: URL) {
        let window = ensureWindow()
        load(url: url)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    public func openFullScreen(url: URL) {
        let window = ensureWindow()
        load(url: url)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }

    public func toggleFullScreen() {
        let window = ensureWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
    }

    public func openStartupBrowserIfNeeded() {
        guard !hasWindow else {
            return
        }
        open(url: Self.startupURL)
    }

    private func load(url: URL) {
        currentURL = url
        let request = URLRequest(url: url)
        webView?.load(request)
    }

    private func ensureWindow() -> NSWindow {
        if let window {
            return window
        }

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.autoresizingMask = [.width, .height]

        let window = NSWindow(
            contentRect: NSRect(x: 160, y: 120, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Event Browser"
        window.contentView = webView

        self.webView = webView
        self.window = window
        return window
    }
}
