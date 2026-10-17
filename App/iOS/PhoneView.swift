import SwiftUI

struct PhoneView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if store.session == nil {
                LoginView(store: store)
            } else {
                BedSetupView(store: store)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, store.session != nil else { return }
            Task { await store.reloadBed() }
        }
    }
}

private struct LoginView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text("EIGHT SLEEP")
                    .font(.caption.weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(Theme.cool)
                Text("Grok")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                Text("Sign in, pick your side, and change the bed from your watch.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                TextField("Email", text: $store.emailDraft)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .fieldStyle()
                SecureField("Password", text: $store.passwordDraft)
                    .textContentType(.password)
                    .fieldStyle()
                    .onSubmit { Task { await store.signIn() } }
            }
            if let error = store.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button {
                Task { await store.signIn() }
            } label: {
                Group {
                    if store.busy {
                        ProgressView()
                    } else {
                        Text("Sign In")
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 22)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.cool)
            .controlSize(.large)
            .disabled(store.busy)
            Spacer()
        }
        .padding(24)
    }
}

private struct BedSetupView: View {
    @ObservedObject var store: SessionStore
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Which side is yours?")
                        .font(.title2.weight(.semibold))
                    Text("The watch only changes this side. Names come from the Eight Sleep account on each side.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(store.sides) { side in
                            SideCard(
                                side: side,
                                selected: store.selectedSide == side.side
                            ) {
                                store.choose(side)
                            }
                        }
                    }
                    if let selected = store.sides.first(where: { $0.side == store.selectedSide }) {
                        LevelReadout(side: selected)
                    }
                    if let error = store.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Text("Plus and minus are on the watch.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.background)
            .navigationTitle("Eight Sleep Grok")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out", role: .destructive) {
                        confirmSignOut = true
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await store.reloadBed() }
                    } label: {
                        if store.busy {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(store.busy)
                    .accessibilityLabel("Refresh")
                }
            }
            .refreshable { await store.reloadBed() }
            .confirmationDialog("Sign out of Eight Sleep?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { store.signOut() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

private struct SideCard: View {
    var side: BedSide
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(side.side.title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(selected ? Theme.cool : .secondary)
                Text(side.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                if side.isAway {
                    Text("Away")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let level = side.level {
                    Text(LevelMath.levelText(level))
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.levelColor(level))
                } else if side.canControl {
                    Text("—")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                if selected {
                    Label("Yours", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.cool)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(selected ? Theme.cool : Color.white.opacity(0.06), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!side.canControl)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var text = "\(side.side.title) side, \(side.name)"
        if side.isAway { text += ", away" }
        if selected { text += ", selected" }
        return text
    }
}

private struct LevelReadout: View {
    var side: BedSide

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(side.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let level = side.level {
                Text(LevelMath.levelText(level))
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.levelColor(level))
                Text(caption(level))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                Text("No reading yet")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private func caption(_ level: Int) -> String {
        let degrees = LevelMath.fahrenheitText(for: level)
        if side.isOn == false {
            return "Off · \(degrees)"
        }
        return "On · \(degrees)"
    }
}

private extension View {
    func fieldStyle() -> some View {
        self
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
    }
}
