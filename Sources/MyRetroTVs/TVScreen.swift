import SwiftUI
import UIKit

/// One decade's TV: the site's picture in a native frame, with the remote below
/// (portrait) or a full-screen picture with a pop-up remote (landscape).
struct TVScreen: View {
    @State private var controller: TVController
    @State private var showEffects = false
    @State private var showRemote = false
    @State private var hideRemote: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    init(decade: Decade) {
        _controller = State(initialValue: TVController(decade: decade))
    }

    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.background.ignoresSafeArea()

            // One layout for both orientations, so turning the phone never
            // reloads the web view: the bars and remote just come and go.
            VStack(spacing: isLandscape ? 0 : 12) {
                if !isLandscape {
                    topBar
                }
                picture
                    .clipShape(RoundedRectangle(cornerRadius: isLandscape ? 0 : 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: isLandscape ? 0 : 20, style: .continuous)
                            .strokeBorder(controller.decade.glow.opacity(isLandscape ? 0 : 0.35), lineWidth: 1.5)
                    )
                    .shadow(color: controller.decade.glow.opacity(isLandscape ? 0 : 0.3), radius: 24)
                    .padding(.horizontal, isLandscape ? 0 : 10)
                if !isLandscape {
                    RemoteControl(controller: controller) { showEffects = true }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                }
            }
            .ignoresSafeArea(.all, edges: isLandscape ? .all : [])

            if isLandscape {
                landscapeControls
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showEffects) {
            EffectsSheet(controller: controller)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            UserDefaults.standard.set(controller.decade.id, forKey: "lastDecade")
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: isLandscape) {
            showRemote = false
        }
    }

    // MARK: Portrait

    private var topBar: some View {
        HStack(spacing: 12) {
            CircleIconButton(symbol: "chevron.down", label: "Back to all TVs") {
                Haptics.click()
                dismiss()
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("The \(controller.decade.id)")
                    .font(Theme.display(22))
                    .foregroundStyle(Theme.cream)
                    .contentTransition(.numericText())
                Text(controller.decade.years)
                    .font(Theme.label(12, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .animation(.snappy, value: controller.decade)
            Spacer()
            if controller.isLoading {
                ProgressView().tint(Theme.amber)
            }
            CircleIconButton(symbol: "arrow.clockwise", label: "Reload") {
                Haptics.click()
                controller.reload()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: Landscape

    /// Small floating buttons over the full-screen picture; the full remote slides in from the right.
    private var landscapeControls: some View {
        ZStack(alignment: .topLeading) {
            HStack {
                CircleIconButton(symbol: "chevron.down", label: "Back to all TVs") {
                    Haptics.click()
                    dismiss()
                }
                Spacer()
                CircleIconButton(symbol: showRemote ? "xmark" : "av.remote", label: "Remote") {
                    Haptics.click()
                    toggleRemote()
                }
            }
            .padding(14)
            .opacity(showRemote ? 1 : 0.55)

            if showRemote {
                HStack {
                    Spacer()
                    RemoteControl(controller: controller, compact: true) { showEffects = true }
                        .frame(width: 360)
                        .padding(.trailing, 12)
                        .padding(.vertical, 8)
                        .simultaneousGesture(TapGesture().onEnded { scheduleHide() })
                }
                .frame(maxHeight: .infinity)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showRemote)
    }

    private func toggleRemote() {
        showRemote.toggle()
        if showRemote { scheduleHide() }
    }

    private func scheduleHide() {
        hideRemote?.cancel()
        hideRemote = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            showRemote = false
        }
    }

    // MARK: Picture

    private var picture: some View {
        ZStack {
            Color.black
            RetroWebView(controller: controller)
                .opacity(controller.hasError ? 0 : 1)

            if controller.isLoading && !controller.hasError {
                TuningOverlay(decade: controller.decade)
                    .transition(.opacity)
            }
            if controller.hasError {
                NoSignalView { controller.reload() }
                    .transition(.opacity)
            }
            PowerOnFlash()
                .id(controller.tuneCount)
        }
        .animation(.easeOut(duration: 0.35), value: controller.isLoading)
        .animation(.easeOut(duration: 0.25), value: controller.hasError)
    }
}

/// Snow and a channel readout while a set loads.
struct TuningOverlay: View {
    let decade: Decade

    var body: some View {
        ZStack {
            StaticNoise(cell: 4, brightness: 0.55)
            Scanlines(spacing: 3, opacity: 0.3)
            VStack(spacing: 6) {
                Text(decade.id)
                    .font(Theme.display(54))
                    .foregroundStyle(.white)
                    .shadow(color: decade.glow, radius: 14)
                Text(L10n.tvTuning)
                    .font(Theme.led(14))
                    .foregroundStyle(Theme.amber)
                    .shadow(color: Theme.amber, radius: 6)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.55)))
        }
        .allowsHitTesting(false)
    }
}

/// Shown when a set can't load (no connection).
struct NoSignalView: View {
    let retry: () -> Void

    var body: some View {
        ZStack {
            StaticNoise(cell: 6, brightness: 0.25)
            Scanlines()
            VStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                Text(L10n.tvOfflineTitle)
                    .font(Theme.display(24))
                    .foregroundStyle(Theme.cream)
                Text(L10n.tvOfflineBody)
                    .font(Theme.label(14, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
                Button {
                    Haptics.click()
                    retry()
                } label: {
                    Text(L10n.tvRetry)
                        .font(Theme.label(15, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(Theme.amber))
                }
                .buttonStyle(PressableStyle())
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.black.opacity(0.75)))
            .padding(20)
        }
    }
}

struct CircleIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.cream)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
                .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(label)
    }
}
