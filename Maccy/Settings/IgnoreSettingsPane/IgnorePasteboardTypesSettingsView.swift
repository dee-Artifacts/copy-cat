import Defaults
import SwiftUI

struct IgnorePasteboardTypesSettingsView: View {
  @Default(.ignoredPasteboardTypes) private var ignoredPasteboardTypes

  @FocusState private var focus: String.ID?
  @State private var edit = ""
  @State private var selection = ""

  /// Plain-English names + descriptions for the built-in ignored types so users
  /// understand what each one skips. Unknown/custom types just show their id.
  private static let known: [String: (name: String, desc: String)] = [
    "Pasteboard generator type":
      ("Auto-generated copies", "Text put on the clipboard by software automatically, not copied by you."),
    "com.agilebits.onepassword":
      ("1Password", "Anything copied from the 1Password app (passwords, logins)."),
    "com.typeit4me.clipping":
      ("TypeIt4Me", "Snippets expanded by the TypeIt4Me text-expander app."),
    "de.petermaurer.TransientPasteboardType":
      ("Transient clips", "Copies apps mark as temporary / “do not store”, like password fields."),
    "net.antelle.keeweb":
      ("KeeWeb", "Anything copied from the KeeWeb password manager.")
  ]

  var body: some View {
    VStack(alignment: .leading) {
      List(selection: $selection) {
        ForEach(ignoredPasteboardTypes.sorted()) { type in
          VStack(alignment: .leading, spacing: 2) {
            if let info = Self.known[type] {
              Text(info.name).font(.system(size: 12, weight: .semibold))
              Text(info.desc).font(.system(size: 10)).foregroundStyle(.gray)
              Text(type).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary.opacity(0.6))
            } else {
              TextField("", text: Binding(
                get: { type },
                set: {
                  guard !$0.isEmpty, type != $0 else { return }
                  edit = $0
                })
              )
              .onSubmit {
                remove(type)
                ignoredPasteboardTypes.insert(edit)
              }
              .focused($focus, equals: type)
              Text("Custom type").font(.system(size: 10)).foregroundStyle(.gray)
            }
          }
          .padding(.vertical, 2)
          .tag(type)
        }
      }
      .onDeleteCommand {
        remove(selection)
      }

      HStack {
        ControlGroup {
          Button("", systemImage: "plus") {
            ignoredPasteboardTypes.insert("xxx.yyy.zzz")
            focus = "xxx.yyy.zzz"
          }
          Button("", systemImage: "minus") {
            remove(selection)
          }
        }
        .frame(width: 50)

        Spacer()

        Button {
          Defaults.reset(.ignoredPasteboardTypes)
        } label: {
          Text("IgnoredPasteboardTypesReset", tableName: "IgnoreSettings")
        }
      }

      Text("IgnoredPasteboardTypesDescription", tableName: "IgnoreSettings")
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.gray)
        .controlSize(.small)
    }
    .padding()
  }

  private func remove(_ type: String?) {
    guard let type else { return }

    ignoredPasteboardTypes.remove(type)
  }
}

#Preview {
  IgnorePasteboardTypesSettingsView()
    .environment(\.locale, .init(identifier: "en"))
}
