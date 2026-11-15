import AppKit
import Defaults
import Foundation
import Settings
import SwiftUI

@Observable
class AppState: Sendable {
  static let shared = AppState(history: History.shared, footer: Footer())

  let multiSelectionEnabled = false

  var appDelegate: AppDelegate?
  var popup: Popup
  var history: History
  var footer: Footer
  var navigator: NavigationManager
  var preview: SlideoutController

  var searchVisible: Bool {
    if !Defaults[.showSearch] { return false }
    switch Defaults[.searchVisibility] {
    case .always: return true
    case .duringSearch: return !history.searchQuery.isEmpty
    }
  }

  var menuIconText: String {
    var title = history.unpinnedItems.first?.text.shortened(to: 100)
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    title.unicodeScalars.removeAll(where: CharacterSet.newlines.contains)
    return title.shortened(to: 20)
  }

  private let about = About()
  private var settingsWindowController: SettingsWindowController?

  init(history: History, footer: Footer) {
    self.history = history
    self.footer = footer
    popup = Popup()
    navigator = NavigationManager(history: history, footer: footer)
    preview = SlideoutController(
      onContentResize: { contentWidth in
        Defaults[.windowSize].width = contentWidth
      },
      onSlideoutResize: { previewWidth in
        Defaults[.previewWidth] = previewWidth
      })
    preview.contentWidth = Defaults[.windowSize].width
    preview.slideoutWidth = Defaults[.previewWidth]
  }

  @MainActor
  func select() {
    if !navigator.selection.isEmpty {
      if navigator.isMultiSelectInProgress {
        navigator.isManualMultiSelect = false
        history.startPasteStack(selection: &navigator.selection)
      } else {
        history.select(navigator.selection.first)
      }
    } else if let item = footer.selectedItem {
      // TODO: Use item.suppressConfirmation, but it's not updated!
      if item.confirmation != nil, Defaults[.suppressClearAlert] == false {
        item.showConfirmation = true
      } else {
        item.action()
      }
    } else {
      Clipboard.shared.copy(history.searchQuery)
      history.searchQuery = ""
    }
  }

  @MainActor
  func togglePin() {
    withTransaction(Transaction()) {
      navigator.selection.forEach { _, item in
        history.togglePin(item)
      }
    }
  }

  @MainActor
  func removePasteStack() {
    history.interruptPasteStack()
    navigator.highlightFirst()
  }

  @MainActor
  func deleteSelection() {
    guard let leadItem = navigator.leadHistoryItem else { return }
    let nextUnselectedItem = history.visibleItems.nearest(to: leadItem) { !$0.isSelected }

    withTransaction(Transaction()) {
      navigator.selection.forEach { _, item in
        history.delete(item)
      }
      navigator.select(item: nextUnselectedItem)
    }
  }

  @MainActor
  func pinHoveredOrHighlighted() {
    guard let targetID = navigator.targetCardID else { return }
    if let dec = history.items.first(where: { $0.id == targetID }) {
      history.togglePin(dec)
    } else {
      for pinboard in PinboardStore.shared.pinboards {
        if let entry = PinboardStore.shared.entries(for: pinboard).first(where: { $0.id == targetID }) {
          PinboardStore.shared.togglePin(entry, in: pinboard)
          break
        }
      }
    }
  }

  @MainActor
  func deleteHoveredOrHighlighted() {
    guard let targetID = navigator.targetCardID else { return }
    if let dec = history.items.first(where: { $0.id == targetID }) {
      if navigator.hoveredCardID == targetID { navigator.hoveredCardID = nil }
      if navigator.activeQuickHighlightID == targetID { navigator.activeQuickHighlightID = nil }
      history.delete(dec)
    } else {
      for pinboard in PinboardStore.shared.pinboards {
        if let entry = PinboardStore.shared.entries(for: pinboard).first(where: { $0.id == targetID }) {
          if navigator.hoveredCardID == targetID { navigator.hoveredCardID = nil }
          if navigator.activeQuickHighlightID == targetID { navigator.activeQuickHighlightID = nil }
          PinboardStore.shared.delete(entry, from: pinboard)
          break
        }
      }
    }
  }

  func openAbout() {
    about.openAbout(nil)
  }

  @MainActor
  private func ensureSettingsController() { // swiftlint:disable:this function_body_length
    if settingsWindowController == nil {
      settingsWindowController = SettingsWindowController(
        panes: [
          Settings.Pane(
            identifier: Settings.PaneIdentifier.general,
            title: NSLocalizedString("Title", tableName: "GeneralSettings", comment: ""),
            toolbarIcon: NSImage.gearshape!
          ) {
            GeneralSettingsPane().settingsPaneSize()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.storage,
            title: NSLocalizedString("Title", tableName: "StorageSettings", comment: ""),
            toolbarIcon: NSImage.externaldrive!
          ) {
            StorageSettingsPane().settingsPaneSize()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.shortcuts,
            title: "Shortcuts",
            toolbarIcon: NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Shortcuts")!
          ) {
            ShortcutsSettingsPane().settingsPaneSize()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.ignore,
            title: NSLocalizedString("Title", tableName: "IgnoreSettings", comment: ""),
            toolbarIcon: NSImage.nosign!
          ) {
            IgnoreSettingsPane().settingsPaneSize()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.advanced,
            title: NSLocalizedString("Title", tableName: "AdvancedSettings", comment: ""),
            toolbarIcon: NSImage.gearshape2!
          ) {
            AdvancedSettingsPane().settingsPaneSize()
          }
        ]
      )
    }
  }

  // Each entry point uses a SINGLE `show(pane:)` call — calling `show()` and then
  // `show(pane:)` separately leaves the destination pane blank.
  @MainActor
  func openPreferences() {
    ensureSettingsController()
    settingsWindowController?.show(pane: .general)
    settingsWindowController?.window?.styleMask.insert(.resizable) // green expand button
    settingsWindowController?.window?.orderFrontRegardless()
    // Re-select on the next runloop so the pane's content lays out (the library
    // otherwise renders the first-opened pane blank until you switch tabs).
    DispatchQueue.main.async { [weak self] in
      self?.settingsWindowController?.show(pane: .general)
    }
  }

  func quit() {
    NSApp.terminate(self)
  }
}

extension View {
  /// Fixed size for every Settings pane so the window doesn't jump between tabs.
  func settingsPaneSize() -> some View {
    frame(width: 540, height: 480, alignment: .top)
  }
}
