import SwiftUI
import Defaults

struct AdvancedSettingsPane: View {
  private var appDelegate: AppDelegate? { NSApp.delegate as? AppDelegate }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Defaults.Toggle(key: .clearOnQuit) {
        Text("ClearHistoryOnQuit", tableName: "AdvancedSettings")
      }.help(Text("ClearHistoryOnQuitTooltip", tableName: "AdvancedSettings"))

      Defaults.Toggle(key: .clearSystemClipboard) {
        Text("ClearSystemClipboard", tableName: "AdvancedSettings")
      }.help(Text("ClearSystemClipboardTooltip", tableName: "AdvancedSettings"))

      Divider()

      Button {
        appDelegate?.checkAccessibility()
      } label: {
        Label("Check Auto-Paste Permission", systemImage: "accessibility")
      }

      Button {
        appDelegate?.uninstallApp()
      } label: {
        Label("Uninstall Copy Cat…", systemImage: "trash")
      }

      Divider()

      Button(role: .destructive) {
        NSApp.terminate(nil)
      } label: {
        Label("Quit Copy Cat", systemImage: "power")
      }
    }
    .frame(minWidth: 350, maxWidth: 450, alignment: .leading)
    .padding()
  }
}

#Preview {
  AdvancedSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
