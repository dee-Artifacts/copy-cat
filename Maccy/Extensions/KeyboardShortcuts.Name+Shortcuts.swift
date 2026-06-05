import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  static let popup = Self("popup", default: Shortcut(.c, modifiers: [.command, .shift]))
  static let activatePasteStack = Self("activatePasteStack", default: Shortcut(.v, modifiers: [.command]))
  static let pastePlainText = Self("pastePlainText", default: Shortcut(.v, modifiers: [.command, .option]))
  static let search = Self("search", default: Shortcut(.f, modifiers: [.command]))
  static let pin = Self("pin", default: Shortcut(.l, modifiers: [.command]))
  static let delete = Self("delete", default: Shortcut(.delete, modifiers: [.command]))
  static let togglePreview = Self("togglePreview", default: Shortcut(.space, modifiers: [.control]))
  static let quickAccessLeft = Self("quickAccessLeft", default: Shortcut(.a, modifiers: [.option]))
  static let quickAccessRight = Self("quickAccessRight", default: Shortcut(.d, modifiers: [.option]))
  static let quickAccessCycle = Self("quickAccessCycle", default: Shortcut(.w, modifiers: [.option]))
}
