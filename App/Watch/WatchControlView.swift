import SwiftUI
import WatchKit

struct WatchControlView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.session?.selectedUserId?.isEmpty == false {
                controls
            } else {
                setup
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.refreshTemperature() }
        }
        .onOpenURL { _ in
            Task { await store.refreshTemperature() }
        }
    }

    private var setup: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone")
                .font(.title3)
                .foregroundStyle(Theme.cool)
            Text("Set up on iPhone")
                .font(.headline)
            Text("Sign in and choose your side in Eight Sleep Grok.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
    }

    private var controls: some View {
        VStack(spacing: 2) {
            Text(store.session?.selectedName ?? "Your side")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(store.selectedSide?.title ?? "")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(hero)
                .font(.system(size: 48, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.levelColor(store.level))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
            HStack(spacing: 4) {
                if store.isSending {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let error = store.errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                stepButton(system: "minus", tint: Theme.cool, label: "Cooler", enabled: canCool) {
                    store.cooler()
                }
                stepButton(system: "plus", tint: Theme.warm, label: "Warmer", enabled: canWarm) {
                    store.warmer()
                }
            }
            .frame(height: 54)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 2)
    }

    private var hero: String {
        guard let level = store.level else { return "—" }
        return LevelMath.levelText(level)
    }

    private var caption: String {
        guard let level = store.level else { return "Reading" }
        let degrees = LevelMath.fahrenheitText(for: level)
        return store.isOn ? degrees : "Off · \(degrees)"
    }

    private var canCool: Bool {
        store.controlsEnabled && (store.level ?? 0) > AppConfig.levelMinimum
    }

    private var canWarm: Bool {
        store.controlsEnabled && (store.level ?? 0) < AppConfig.levelMaximum
    }

    private func stepButton(
        system: String,
        tint: Color,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            action()
        } label: {
            Image(systemName: system)
                .font(.system(size: 28, weight: .bold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .background(tint.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
