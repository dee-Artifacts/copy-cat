import SwiftUI
import KeyboardShortcuts

struct ShortcutRow: View {
  let label: String
  let desc: String
  let shortcutName: KeyboardShortcuts.Name
  let defaultShortcutText: String
  let onReset: () -> Void

  var body: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 2) {
        Text(label)
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(.white)
        Text(desc)
          .font(.system(size: 10))
          .foregroundStyle(.white.opacity(0.55))
      }
      Spacer()
      KeyboardShortcuts.Recorder(for: shortcutName)
      Button(action: onReset) {
        Text("Reset")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.white.opacity(0.85))
          .padding(.horizontal, 10).padding(.vertical, 4)
          .background(.white.opacity(0.12))
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)
    }
    .padding(.vertical, 6)
  }
}

struct CustomizeShortcutView: View {
  var onDismiss: () -> Void

  var body: some View {
    ZStack {
      // Sleek background gradient
      LinearGradient(
        colors: [Color(red: 0.12, green: 0.12, blue: 0.18), Color(red: 0.06, green: 0.06, blue: 0.09)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      VStack(spacing: 0) {
        HStack(spacing: 12) {
          Image(systemName: "keyboard")
            .font(.system(size: 24, weight: .thin))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))

          VStack(alignment: .leading, spacing: 2) {
            Text("Customize Shortcuts")
              .font(.system(size: 16, weight: .bold))
              .foregroundStyle(.white)
            Text("Set custom keyboard shortcuts for Copy Cat actions.")
              .font(.system(size: 11))
              .foregroundStyle(.white.opacity(0.7))
          }
          Spacer()
        }
        .padding(.top, 16)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)

        Divider().background(.white.opacity(0.15))

        ScrollView {
          VStack(spacing: 2) {
            ShortcutRow(
              label: "Quick Access - Move Left",
              desc: "Hold modifier and press to move left (default ⌥A)",
              shortcutName: .quickAccessLeft,
              defaultShortcutText: "⌥A",
              onReset: {
                KeyboardShortcuts.reset(.quickAccessLeft)
              }
            )

            Divider().background(.white.opacity(0.08))

            ShortcutRow(
              label: "Quick Access - Move Right",
              desc: "Hold modifier and press to move right (default ⌥D)",
              shortcutName: .quickAccessRight,
              defaultShortcutText: "⌥D",
              onReset: {
                KeyboardShortcuts.reset(.quickAccessRight)
              }
            )

            Divider().background(.white.opacity(0.08))

            ShortcutRow(
              label: "Quick Access - Cycle Tabs",
              desc: "Hold modifier and press to cycle pinboards (default ⌥W)",
              shortcutName: .quickAccessCycle,
              defaultShortcutText: "⌥W",
              onReset: {
                KeyboardShortcuts.reset(.quickAccessCycle)
              }
            )

            Divider().background(.white.opacity(0.08))

            ShortcutRow(
              label: "Open Paste History",
              desc: "Launches the Paste tray from bottom of screen",
              shortcutName: .popup,
              defaultShortcutText: "⇧⌘C",
              onReset: {
                KeyboardShortcuts.reset(.popup)
                AppState.shared.popup.initEventsMonitor()
              }
            )

            Divider().background(.white.opacity(0.08))

            ShortcutRow(
              label: "Activate Paste Stack",
              desc: "Start a Paste Stack with selected items",
              shortcutName: .activatePasteStack,
              defaultShortcutText: "⇧⌘C",
              onReset: {
                KeyboardShortcuts.reset(.activatePasteStack)
              }
            )

            Divider().background(.white.opacity(0.08))

            ShortcutRow(
              label: "Paste as Plain Text",
              desc: "Pastes last item stripped of formatting",
              shortcutName: .pastePlainText,
              defaultShortcutText: "⌥⌘V",
              onReset: {
                KeyboardShortcuts.reset(.pastePlainText)
              }
            )

            Divider().background(.white.opacity(0.08))

            ShortcutRow(
              label: "Search History",
              desc: "Focuses the search bar in active Paste tray",
              shortcutName: .search,
              defaultShortcutText: "⌘F",
              onReset: {
                KeyboardShortcuts.reset(.search)
              }
            )

            Divider().background(.white.opacity(0.08))

            ShortcutRow(
              label: "Pin / Unpin Item",
              desc: "Saves selected items to active Pinboards",
              shortcutName: .pin,
              defaultShortcutText: "⌘L",
              onReset: {
                KeyboardShortcuts.reset(.pin)
              }
            )

            Divider().background(.white.opacity(0.08))

            ShortcutRow(
              label: "Delete Item",
              desc: "Deletes selected items from history",
              shortcutName: .delete,
              defaultShortcutText: "⌘⌫",
              onReset: {
                KeyboardShortcuts.reset(.delete)
              }
            )
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 8)
        }

        Divider().background(.white.opacity(0.15))

        HStack {
          Spacer()
          Button(action: onDismiss) {
            Text("Done")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(.black)
              .padding(.horizontal, 32).padding(.vertical, 8)
              .background(.white)
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
      }
    }
    .frame(width: 520, height: 480)
  }
}
