import Combine
import SwiftUI

/// First run: explains why Tray reads the clipboard and asks for Accessibility (needed to paste for you).
struct OnboardingView: View {
    let model: AppModel
    let onDone: () -> Void
    @State private var trusted = Paster.isTrusted

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.S.s6) {
            VStack(alignment: .leading, spacing: Tokens.S.s2) {
                Text("Tray").font(Tokens.T.title)
                Text("Everything you copied, one keystroke away.")
                    .font(.system(size: 15)).foregroundStyle(Tokens.C.inkMuted)
            }

            point("doc.on.clipboard", "Tray reads what you copy",
                  "To keep your history, Tray checks the clipboard when it changes. If macOS asks whether Tray may paste from other apps, choose Allow.")
            point("lock", "It stays on this Mac",
                  "History is encrypted on disk. Nothing is sent anywhere. Copies from password managers are never saved, and secrets are masked.")
            point("keyboard", "Pasting needs Accessibility",
                  "So Return can paste straight into the app you're in, allow Tray under System Settings › Privacy & Security › Accessibility. Without it, Tray copies and you press ⌘V.")

            HStack {
                if trusted {
                    Label("Accessibility allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Tokens.C.inkMuted)
                } else {
                    Button("Allow Accessibility…") {
                        Paster.requestTrust()
                    }
                }
                Spacer()
                Button("Get started") { onDone() }
                    .keyboardShortcut(.defaultAction)
            }

            Text("Open Tray any time with ⌘⇧V.").font(Tokens.T.callout).foregroundStyle(Tokens.C.inkMuted)
        }
        .foregroundStyle(Tokens.C.ink)
        .padding(Tokens.S.s8)
        .frame(width: 560)
        .background(Tokens.C.surface)
        .tint(model.accent.color)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            trusted = Paster.isTrusted
        }
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Tokens.S.s3) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(model.accent.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Tokens.T.headline)
                Text(detail).font(Tokens.T.callout).foregroundStyle(Tokens.C.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
