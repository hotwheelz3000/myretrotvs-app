import Observation
import SwiftUI
import WebKit

/// The site's keyboard shortcuts, which the remote and gestures press.
enum RemoteKey: String {
    case power = " "
    case channelUp = "ArrowUp"
    case channelDown = "ArrowDown"
    case volumeUp = "+"
    case volumeDown = "-"
    case menu = "h"
    case mute = "m"
    case noise = "n"
    case glow = "g"
    case blackAndWhite = "b"
    case colorScheme = "c"
    case staticTransition = "o"
    case youtube = "y"
    case fullScreen = "f"
    case immersive = "i"
    case playlist = "p"
    case shuffle = "s"
    case escape = "Escape"

    /// What the remote's little LED display shows after a press.
    var led: String {
        switch self {
        case .power: return "POWER"
        case .channelUp: return "CH ▲"
        case .channelDown: return "CH ▼"
        case .volumeUp: return "VOL +"
        case .volumeDown: return "VOL −"
        case .menu: return "MENU"
        case .mute: return "SFX"
        case .noise: return "NOISE"
        case .glow: return "GLOW"
        case .blackAndWhite: return "B/W"
        case .colorScheme: return "COLOR"
        case .staticTransition: return "STATIC"
        case .youtube: return "YOUTUBE"
        case .fullScreen: return "FULL"
        case .immersive: return "FOCUS"
        case .playlist: return "PLAYLIST"
        case .shuffle: return "SHUFFLE"
        case .escape: return "EXIT"
        }
    }
}

/// Owns the web view for the TV screen and everything the native controls do to it.
@MainActor
@Observable
final class TVController {
    private(set) var decade: Decade
    var isLoading = true
    var hasError = false
    /// Whether the site's Immersive Mode (just the TV) is on for the current page.
    private(set) var isImmersive = false
    /// Whether the site's full-screen video mode is on, which also hides the app's bars.
    private(set) var isFullScreen = false
    /// The small floating remote shown over a full-screen picture (tap the screen).
    var overlayRemote = false
    /// Briefly true after each press, to show the LED over a full-screen picture.
    private(set) var toastVisible = false
    private(set) var ledText: String
    /// Bumped on every decade change, so the screen replays its switch-on flash.
    private(set) var tuneCount = 0

    @ObservationIgnored weak var webView: WKWebView?
    @ObservationIgnored private var ledReset: Task<Void, Never>?
    @ObservationIgnored private var immersiveTask: Task<Void, Never>?

    init(decade: Decade) {
        self.decade = decade
        self.ledText = "CH \(decade.id)"
    }

    var autoImmersive: Bool {
        UserDefaults.standard.object(forKey: "autoImmersive") as? Bool ?? true
    }

    func press(_ key: RemoteKey, haptic: Bool = true) {
        if haptic { Haptics.click() }
        switch key {
        case .volumeUp, .volumeDown:
            // iOS ignores the site's volume control; change the phone's media volume.
            let level = SystemVolume.shared.step(up: key == .volumeUp)
            flash(SystemVolume.meter(level))
            return
        case .immersive:
            isImmersive.toggle()
            webView?.scrollView.isScrollEnabled = !(isImmersive || isFullScreen)
        case .fullScreen:
            // The app's own full screen (the player stretched over the page), not the site's F key.
            isFullScreen.toggle()
            overlayRemote = false
            webView?.scrollView.isScrollEnabled = !(isImmersive || isFullScreen)
            webView?.evaluateJavaScript("window.__retroFull && window.__retroFull(\(isFullScreen));", completionHandler: nil)
            flash(isFullScreen ? "FULL" : "CH \(decade.id)")
            return
        default:
            break
        }
        flash(key.led)
        send(key.rawValue)
    }

    /// A tap on the picture shows or hides the floating remote (only shown when the
    /// app's own remote is hidden: full screen or landscape).
    func screenTapped() {
        overlayRemote.toggle()
    }

    func tune(to decade: Decade) {
        guard decade != self.decade else { return }
        Haptics.thunk()
        self.decade = decade
        UserDefaults.standard.set(decade.id, forKey: "lastDecade")
        tuneCount += 1
        flash("CH \(decade.id)")
        webView?.load(URLRequest(url: decade.url))
    }

    func reload() {
        hasError = false
        isLoading = true
        if webView?.url == nil {
            webView?.load(URLRequest(url: decade.url))
        } else {
            webView?.reload()
        }
    }

    // MARK: Web view events

    func pageStarted() {
        isLoading = true
        hasError = false
        immersiveTask?.cancel()
    }

    func pageCommitted() {
        // A new page starts with the site's normal layout.
        isImmersive = false
        webView?.scrollView.isScrollEnabled = !isFullScreen
    }

    func pageFinished() {
        isLoading = false
        hasError = false
        if isFullScreen {
            // A new decade keeps full screen on.
            webView?.evaluateJavaScript("window.__retroFull && window.__retroFull(true);", completionHandler: nil)
        }
        guard autoImmersive else { return }
        immersiveTask?.cancel()
        immersiveTask = Task { [weak self] in
            // Give the site a moment to set up the TV before switching modes.
            try? await Task.sleep(for: .milliseconds(1200))
            guard let self, !Task.isCancelled, !self.isImmersive else { return }
            self.press(.immersive, haptic: false)
            self.ledText = "CH \(self.decade.id)"
        }
    }

    func pageFailed() {
        isLoading = false
        hasError = true
    }

    // MARK: Private

    private func send(_ key: String) {
        guard let webView else { return }
        let escaped = key
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("window.__retroKey && window.__retroKey('\(escaped)');", completionHandler: nil)
    }

    private func flash(_ text: String) {
        ledText = text
        withAnimation(.easeOut(duration: 0.15)) { toastVisible = true }
        ledReset?.cancel()
        ledReset = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1400))
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.ledText = "CH \(self.decade.id)"
                self.toastVisible = false
            }
        }
    }
}
