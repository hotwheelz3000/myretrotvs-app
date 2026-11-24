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

/// A year on the site's year bar (2000...2009).
struct GuideYear: Identifiable, Equatable {
    let index: Int
    let name: String
    let selected: Bool
    var id: Int { index }
}

/// One of the site's content filters ("Cartoons (4584)").
struct GuideCategory: Identifiable, Equatable {
    let code: String
    let name: String
    let count: Int
    var checked: Bool
    var id: String { code }
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
    /// Whether the site's Shuffle Mode (random years on channel change) is on for this page.
    private(set) var isShuffle = false
    /// The small floating remote shown over a full-screen picture (tap the screen).
    var overlayRemote = false
    /// Briefly true after each press, to show the LED over a full-screen picture.
    private(set) var toastVisible = false
    /// The site's status line ("Tube glow effect is now enabled"), shown as a banner for a moment.
    private(set) var banner: String?

    // What's on, read from the page.
    private(set) var nowTitle = ""
    private(set) var channelLabel = ""
    private(set) var years: [GuideYear] = []
    private(set) var categories: [GuideCategory] = []

    /// "MUSIC" from "MUSIC - CH 9946".
    var nowCategory: String {
        let parts = channelLabel.components(separatedBy: " - ")
        return parts.count > 1 ? parts[0].trimmingCharacters(in: .whitespaces) : ""
    }

    /// "9946" from "MUSIC - CH 9946".
    var channelNumber: String? {
        guard let range = channelLabel.range(of: #"CH\s*(\d+)"#, options: .regularExpression) else { return nil }
        return channelLabel[range].filter(\.isNumber)
    }
    private(set) var ledText: String
    /// Bumped on every decade change, so the screen replays its switch-on flash.
    private(set) var tuneCount = 0

    @ObservationIgnored weak var webView: WKWebView?
    @ObservationIgnored private var ledReset: Task<Void, Never>?
    @ObservationIgnored private var immersiveTask: Task<Void, Never>?
    @ObservationIgnored private var bannerReset: Task<Void, Never>?
    @ObservationIgnored private var applyFilters: Task<Void, Never>?
    @ObservationIgnored private var quietImmersiveStatus = false
    @ObservationIgnored private var relayoutTask: Task<Void, Never>?

    init(decade: Decade) {
        self.decade = decade
        self.ledText = "CH \(decade.id)"
    }

    /// What the LED shows when nothing was just pressed.
    private var idleLED: String {
        if let number = channelNumber { return "CH \(number)" }
        return "CH \(decade.id)"
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
        case .shuffle:
            isShuffle.toggle()
        case .fullScreen:
            // The app's own full screen (the player stretched over the page), not the site's F key.
            isFullScreen.toggle()
            overlayRemote = false
            webView?.scrollView.isScrollEnabled = !(isImmersive || isFullScreen)
            webView?.evaluateJavaScript("window.__retroFull && window.__retroFull(\(isFullScreen));", completionHandler: nil)
            flash(isFullScreen ? "FULL" : idleLED)
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
        isShuffle = false
        webView?.scrollView.isScrollEnabled = !isFullScreen
        nowTitle = ""
        channelLabel = ""
        years = []
        categories = []
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
            self.quietImmersiveStatus = true
            self.press(.immersive, haptic: false)
            self.ledText = self.idleLED
        }
    }

    func pageFailed() {
        isLoading = false
        hasError = true
    }

    /// After the picture changes size (leaving full screen, turning the phone), scroll
    /// the page back to the top and tell the site its window resized so it re-centers
    /// the TV. Runs again a moment later, after the resize animation has settled.
    func relayout() {
        relayoutTask?.cancel()
        relayoutTask = Task { [weak self] in
            for delay in [150, 500, 600] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard let self, !Task.isCancelled, let webView = self.webView else { return }
                webView.scrollView.setContentOffset(.zero, animated: false)
                webView.evaluateJavaScript(
                    "window.scrollTo(0, 0); window.dispatchEvent(new Event('resize'));",
                    completionHandler: nil
                )
            }
        }
    }

    // MARK: Guide

    func selectYear(_ year: GuideYear) {
        guard !year.selected else { return }
        Haptics.thunk()
        flash(year.name)
        webView?.evaluateJavaScript("window.__retroGuide && window.__retroGuide.year(\(year.index));", completionHandler: nil)
    }

    func setCategory(_ code: String, on: Bool) {
        Haptics.tick()
        if let index = categories.firstIndex(where: { $0.code == code }) {
            categories[index].checked = on
        }
        let safe = code.filter { $0.isLetter }
        webView?.evaluateJavaScript("window.__retroGuide && window.__retroGuide.category('\(safe)', \(on));", completionHandler: nil)
        scheduleFilterApply()
    }

    func selectAllCategories(_ on: Bool) {
        Haptics.click()
        for index in categories.indices { categories[index].checked = on }
        webView?.evaluateJavaScript("window.__retroGuide && window.__retroGuide.\(on ? "all" : "none")();", completionHandler: nil)
        if on { scheduleFilterApply() }
    }

    /// The site applies filter changes on the next channel change, so change channel
    /// once the switches settle.
    private func scheduleFilterApply() {
        applyFilters?.cancel()
        applyFilters = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, !Task.isCancelled, self.categories.contains(where: \.checked) else { return }
            self.send(RemoteKey.channelUp.rawValue)
        }
    }

    /// Messages from the page script (Scripts.pageState).
    func handlePage(_ body: [String: Any]) {
        switch body["type"] as? String {
        case "status":
            guard let text = body["text"] as? String, !text.isEmpty else { return }
            if quietImmersiveStatus && text.localizedCaseInsensitiveContains("immersive") {
                quietImmersiveStatus = false
                return
            }
            showBanner(text)
        case "state":
            let title = body["title"] as? String ?? ""
            if title != nowTitle { nowTitle = title }
            let label = body["channel"] as? String ?? ""
            if label != channelLabel {
                channelLabel = label
                if !toastVisible { ledText = idleLED }
            }
            let newYears: [GuideYear] = (body["years"] as? [[String: Any]] ?? []).compactMap { item in
                guard let index = (item["index"] as? NSNumber)?.intValue, let name = item["name"] as? String else { return nil }
                return GuideYear(index: index, name: name, selected: (item["selected"] as? NSNumber)?.boolValue ?? false)
            }
            if newYears != years { years = newYears }
            let newCategories: [GuideCategory] = (body["categories"] as? [[String: Any]] ?? []).compactMap { item in
                guard let code = item["code"] as? String, let name = item["name"] as? String else { return nil }
                return GuideCategory(
                    code: code,
                    name: name,
                    count: (item["count"] as? NSNumber)?.intValue ?? 0,
                    checked: (item["checked"] as? NSNumber)?.boolValue ?? false
                )
            }
            if newCategories != categories { categories = newCategories }
        default:
            break
        }
    }

    private func showBanner(_ text: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { banner = text }
        bannerReset?.cancel()
        bannerReset = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2400))
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.banner = nil }
        }
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
                self.ledText = self.idleLED
                self.toastVisible = false
            }
        }
    }
}
