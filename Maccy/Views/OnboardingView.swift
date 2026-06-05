import SwiftUI
import AppKit

private struct CardData {
  let icon: String
  let gradient: [Color]
  let title: String
  let body: String
  // Each inner array is one shortcut combo rendered as keycaps; multiple combos
  // are shown side by side, separated by a divider. nil = no shortcut bar.
  var shortcut: [[String]]? = nil
  var shortcutHint: String? = nil
  // When true this card is the Accessibility permission gate: it shows a live
  // status + grant button, and "Get Started" stays disabled until granted.
  var gatesAccessibility: Bool = false
}

private let cards: [CardData] = [
  CardData(icon: "gift.fill",
           gradient: [Color(red:0.16,green:0.73,blue:0.51), Color(red:0.23,green:0.51,blue:0.96)],
           title: "Welcome — your \(LicenseConfig.trialDays)-day free trial starts now",
           body: "Explore Copy Cat free for the next \(LicenseConfig.trialDays) days — full clipboard history, Quick Paste, and 2 free pinboards. Unlock unlimited pinboards anytime with a one-time purchase."),
  CardData(icon: "keyboard",
           gradient: [Color(red:0.23,green:0.51,blue:0.96), Color(red:0.44,green:0.27,blue:0.97)],
           title: "Your Clipboard, Always Ready",
           body: "Open Copy Cat's strip from any app, then tap any card to paste it into your active window. The search bar up top filters your entire history as you type.",
           shortcut: [["⇧", "⌘", "C"]],
           shortcutHint: "Open Copy Cat"),
  CardData(icon: "bolt.fill",
           gradient: [Color(red:0.55,green:0.27,blue:0.97), Color(red:0.94,green:0.27,blue:0.27)],
           title: "Quick Paste, Hands on Keys",
           body: "Hold ⌥ and tap A or D to flip through clips — W cycles pinboards — right where you're typing. Let go of ⌥ and the highlighted card pastes instantly.",
           shortcut: [["⌥", "A"], ["⌥", "D"], ["⌥", "W"]],
           shortcutHint: "Hold, navigate, release to paste"),
  CardData(icon: "pin.fill",
           gradient: [Color(red:0.96,green:0.62,blue:0.04), Color(red:0.94,green:0.27,blue:0.27)],
           title: "Pin & Organize",
           body: "Hover a card and click the pin to keep it front and center. Build color-coded pinboards that never expire, and right-click any card to move it where it belongs.",
           shortcut: [["⌘", "L"]],
           shortcutHint: "Pin the highlighted card"),
  CardData(icon: "pencil",
           gradient: [Color(red:0.94,green:0.27,blue:0.55), Color(red:0.96,green:0.62,blue:0.04)],
           title: "Make Every Card Yours",
           body: "Right-click to rename a card so it's easy to spot. In Settings → Pins you can edit the text of pinned cards directly and assign each one its own keyboard shortcut."),
  CardData(icon: "lock.shield.fill",
           gradient: [Color(red:0.20,green:0.78,blue:0.55), Color(red:0.23,green:0.51,blue:0.96)],
           title: "Smart & Private",
           body: "Links unfurl into rich previews so you recognize them at a glance. Passwords and other sensitive clips are detected and skipped automatically, while battery-friendly monitoring keeps Copy Cat feather-light."),
  CardData(icon: "accessibility",
           gradient: [Color(red:0.23,green:0.51,blue:0.96), Color(red:0.16,green:0.73,blue:0.51)],
           title: "One Last Step",
           body: "Copy Cat needs Accessibility permission to paste into your apps and power Quick Paste. Click below, switch Copy Cat ON in the list, and you're ready.",
           gatesAccessibility: true)
]

private struct Keycap: View {
  let label: String
  var body: some View {
    Text(label)
      .font(.system(size: 17, weight: .bold, design: .rounded))
      .foregroundStyle(.white)
      .frame(minWidth: 30, minHeight: 34)
      .padding(.horizontal, 6)
      .background(.white.opacity(0.22))
      .overlay(
        RoundedRectangle(cornerRadius: 9)
          .stroke(.white.opacity(0.35), lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: 9))
      .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
  }
}

private struct ShortcutBar: View {
  let combos: [[String]]
  let hint: String?
  var body: some View {
    VStack(spacing: 7) {
      HStack(spacing: 10) {
        ForEach(Array(combos.enumerated()), id: \.offset) { idx, combo in
          HStack(spacing: 5) {
            ForEach(Array(combo.enumerated()), id: \.offset) { _, key in
              Keycap(label: key)
            }
          }
          if idx < combos.count - 1 {
            Text("/")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(.white.opacity(0.5))
          }
        }
      }
      if let hint {
        Text(hint.uppercased())
          .font(.system(size: 10, weight: .semibold))
          .tracking(0.8)
          .foregroundStyle(.white.opacity(0.75))
      }
    }
  }
}

private struct AccessibilityGate: View {
  let granted: Bool
  let onGrant: () -> Void
  var body: some View {
    VStack(spacing: 12) {
      Button(action: onGrant) {
        Text(granted ? "Open Accessibility Settings" : "Enable Accessibility")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.black)
          .padding(.horizontal, 26).padding(.vertical, 10)
          .background(.white)
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)

      HStack(spacing: 7) {
        Image(systemName: granted ? "checkmark.circle.fill" : "clock.fill")
          .font(.system(size: 13))
        Text(granted ? "Permission granted — you're all set!" : "Waiting for permission…")
          .font(.system(size: 12, weight: .medium))
      }
      .foregroundStyle(.white.opacity(granted ? 1.0 : 0.8))
      .animation(.easeInOut(duration: 0.25), value: granted)
    }
  }
}

struct OnboardingView: View {
  var onDismiss: () -> Void
  @State private var index = 0
  @State private var accessibilityGranted = Accessibility.allowed
  private let pollTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  private func openAccessibilitySettings() {
    Accessibility.requestIfNeeded()
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
    }
  }

  var body: some View {
    let card = cards[index]
    let gateBlocksAdvance = card.gatesAccessibility && !accessibilityGranted
    ZStack {
      LinearGradient(colors: card.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.45), value: index)

      VStack(spacing: 0) {
        Spacer()

        Image(systemName: card.icon)
          .font(.system(size: 64, weight: .thin))
          .foregroundStyle(.white)
          .frame(width: 120, height: 120)
          .background(.white.opacity(0.15))
          .clipShape(RoundedRectangle(cornerRadius: 30))
          .shadow(color: .black.opacity(0.2), radius: 20)
          .padding(.bottom, 24)
          .transition(.scale.combined(with: .opacity))
          .id(index)

        Text(card.title)
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(.white)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 32)
          .padding(.bottom, 12)

        if let shortcut = card.shortcut {
          ShortcutBar(combos: shortcut, hint: card.shortcutHint)
            .padding(.bottom, 14)
            .transition(.scale.combined(with: .opacity))
            .id(index)
        }

        Text(card.body)
          .font(.system(size: 14))
          .foregroundStyle(.white.opacity(0.85))
          .multilineTextAlignment(.center)
          .lineSpacing(2)
          .padding(.horizontal, 40)

        if card.gatesAccessibility {
          AccessibilityGate(granted: accessibilityGranted, onGrant: openAccessibilitySettings)
            .padding(.top, 18)
        }

        Spacer()

        HStack(spacing: 7) {
          ForEach(0..<cards.count, id: \.self) { i in
            Capsule()
              .fill(.white.opacity(i == index ? 1.0 : 0.4))
              .frame(width: i == index ? 18 : 6, height: 6)
              .animation(.spring(duration: 0.25), value: index)
          }
        }
        .padding(.bottom, 20)

        HStack(spacing: 12) {
          if index > 0 {
            Button(action: { withAnimation(.easeInOut(duration: 0.3)) { index -= 1 } }) {
              Text("Back")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(.white.opacity(0.15))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
          }
          Button(action: {
            if index == cards.count - 1 { onDismiss() }
            else { withAnimation(.easeInOut(duration: 0.3)) { index += 1 } }
          }) {
            Text(index == cards.count - 1 ? "Get Started" : "Next")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.black)
              .padding(.horizontal, 32).padding(.vertical, 10)
              .background(.white.opacity(gateBlocksAdvance ? 0.45 : 1.0))
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)
          .focusable(false)
          .disabled(gateBlocksAdvance)
          .help(gateBlocksAdvance ? "Enable Accessibility above to continue" : "")
        }
        .padding(.bottom, gateBlocksAdvance ? 10 : 36)

        if gateBlocksAdvance {
          Button(action: onDismiss) {
            Text("Skip for now")
              .font(.system(size: 12))
              .foregroundStyle(.white.opacity(0.6))
              .underline()
          }
          .buttonStyle(.plain)
          .padding(.bottom, 18)
        }
      }
    }
    .frame(width: 440, height: 470)
    .onReceive(pollTimer) { _ in
      let now = Accessibility.allowed
      if now != accessibilityGranted {
        withAnimation(.easeInOut(duration: 0.25)) { accessibilityGranted = now }
      }
    }
  }
}
