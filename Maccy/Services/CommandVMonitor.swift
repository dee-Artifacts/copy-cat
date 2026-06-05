import AppKit
import Carbon
import KeyboardShortcuts

extension Notification.Name {
  static let commandVQuickNavigateLeft = Notification.Name("commandVQuickNavigateLeft")
  static let commandVQuickNavigateRight = Notification.Name("commandVQuickNavigateRight")
  static let commandVQuickNavigatePinboard = Notification.Name("commandVQuickNavigatePinboard")
  static let commandVQuickRelease = Notification.Name("commandVQuickRelease")
}

class CommandVMonitor {
  static let shared = CommandVMonitor()

  /// Marker stamped onto every keyboard event Copy Cat synthesizes itself
  /// (the simulated ⌘V paste, and re-injected normal pastes). The event tap
  /// reads this back via `.eventSourceUserData` and passes such events straight
  /// through. Using a tag carried by the event is deterministic, unlike a
  /// boolean flag whose reset can race against asynchronous event delivery.
  static let synthesizedEventMarker: Int64 = 0x636F7079636174 // "copycat"

  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var holdTimer: Timer?
  private var permissionWatchTimer: Timer?
  private var hasPromptedForPermission = false
  
  private var isQuickPasting = false
  private var isReinjecting = false
  var isSimulatingPaste = false
  private var pendingDownEvent: CGEvent?
  private var activeModifier: CGEventFlags?
  
  func writeDebugLog(_ message: String) {
    let logPath = "/Users/deepakkrishnar/.gemini/antigravity/scratch/copycat_debug.log"
    let logLine = "\(Date()): \(message)\n"
    if let fileHandle = FileHandle(forWritingAtPath: logPath) {
      fileHandle.seekToEndOfFile()
      if let data = logLine.data(using: .utf8) {
        fileHandle.write(data)
      }
      fileHandle.closeFile()
    } else {
      try? logLine.write(toFile: logPath, atomically: true, encoding: .utf8)
    }
  }
  
  func start() {
    writeDebugLog("CommandVMonitor: start() called, Accessibility.allowed = \(Accessibility.allowed)")
    guard eventTap == nil else {
      writeDebugLog("CommandVMonitor: start() - eventTap is already non-nil")
      return
    }
    
    let eventMask = (1 << CGEventType.keyDown.rawValue) |
                    (1 << CGEventType.keyUp.rawValue) |
                    (1 << CGEventType.flagsChanged.rawValue)
                    
    eventTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: CGEventMask(eventMask),
      callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
        let monitor = Unmanaged<CommandVMonitor>.fromOpaque(refcon!).takeUnretainedValue()
        return monitor.handleEvent(proxy: proxy, type: type, event: event)
      },
      userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    )
    
    guard let eventTap = eventTap else {
      // Permission isn't active yet. Instead of giving up (which forced the user
      // to quit & relaunch after granting), surface the system prompt once and
      // then watch for the grant — the moment it lands we create the tap, with no
      // relaunch needed.
      writeDebugLog("CommandVMonitor: start() - tap not created yet (Accessibility not granted); watching for permission")
      fputs("Copy Cat: Accessibility not granted yet; waiting for permission.\n", stderr)
      fflush(stderr)
      beginWatchingForPermission()
      return
    }

    permissionWatchTimer?.invalidate()
    permissionWatchTimer = nil
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
    writeDebugLog("CommandVMonitor: event tap created and enabled")
  }

  /// Polls for Accessibility permission and starts the tap the instant it's
  /// granted, so the user never has to quit & reopen after enabling the toggle.
  private func beginWatchingForPermission() {
    if !hasPromptedForPermission {
      hasPromptedForPermission = true
      Accessibility.requestIfNeeded()
    }
    guard permissionWatchTimer == nil else { return }
    permissionWatchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      guard let self = self else { return }
      guard Accessibility.allowed else { return }
      self.writeDebugLog("CommandVMonitor: Accessibility granted — starting tap without relaunch")
      self.permissionWatchTimer?.invalidate()
      self.permissionWatchTimer = nil
      self.start()
    }
  }

  func stop() {
    permissionWatchTimer?.invalidate()
    permissionWatchTimer = nil
    if let runLoopSource = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
      self.runLoopSource = nil
    }
    if let eventTap = eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      self.eventTap = nil
    }
    holdTimer?.invalidate()
    holdTimer = nil
  }
  
  private func eventMatchesShortcut(_ event: CGEvent, name: KeyboardShortcuts.Name) -> Bool {
    guard let shortcut = KeyboardShortcuts.Shortcut(name: name) else {
      writeDebugLog("eventMatchesShortcut name=\(name.rawValue) - no shortcut found")
      return false
    }
    
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let isKeyMatch = (keyCode == shortcut.carbonKeyCode)
    
    var isModifierMatch = false
    var eventModsStr = ""
    var shortcutModsStr = ""
    
    if let nsEvent = NSEvent(cgEvent: event) {
      let eventModifiers = nsEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
      let shortcutModifiers = shortcut.modifiers.intersection(.deviceIndependentFlagsMask)
      isModifierMatch = (eventModifiers == shortcutModifiers)
      eventModsStr = String(describing: eventModifiers)
      shortcutModsStr = String(describing: shortcutModifiers)
    }
    
    let isMatch = isKeyMatch && isModifierMatch
    writeDebugLog("eventMatchesShortcut name=\(name.rawValue) key=\(keyCode) vs \(shortcut.carbonKeyCode) [match=\(isKeyMatch)], mods=\(eventModsStr) vs \(shortcutModsStr) [match=\(isModifierMatch)] -> result: \(isMatch)")
    return isMatch
  }

  private func getShortcutModifiersFlags(name: KeyboardShortcuts.Name) -> CGEventFlags {
    guard let shortcut = KeyboardShortcuts.Shortcut(name: name) else {
      return CGEventFlags()
    }
    var reqFlags = CGEventFlags()
    let nsModifiers = shortcut.modifiers
    if nsModifiers.contains(.command) { reqFlags.insert(.maskCommand) }
    if nsModifiers.contains(.option) { reqFlags.insert(.maskAlternate) }
    if nsModifiers.contains(.control) { reqFlags.insert(.maskControl) }
    if nsModifiers.contains(.shift) { reqFlags.insert(.maskShift) }
    return reqFlags
  }

  private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    // macOS disables a tap if its callback runs too long or under heavy input.
    // Re-enable it immediately so quick-paste keeps working without a relaunch.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      writeDebugLog("CommandVMonitor: tap disabled (\(type.rawValue)) — re-enabling")
      if let eventTap = eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }
      return Unmanaged.passRetained(event)
    }

    // Pass through any event we synthesized ourselves. The tag travels with the
    // event, so this is immune to the timing race that the isReinjecting /
    // isSimulatingPaste flags suffer from (their async reset can fire before the
    // posted event is delivered here, causing our own ⌘V to be swallowed).
    if event.getIntegerValueField(.eventSourceUserData) == Self.synthesizedEventMarker {
      return Unmanaged.passRetained(event)
    }

    // Quick Paste (hold-⌘V + ⌥-navigation) is a paid/trial feature. When access
    // has lapsed the tap goes transparent, so ⌘V is a normal system paste again.
    if !LicenseManager.quickPasteAllowedFlag {
      return Unmanaged.passRetained(event)
    }

    if isReinjecting || isSimulatingPaste {
      return Unmanaged.passRetained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    let isCommandDown = flags.contains(.maskCommand)

    writeDebugLog("handleEvent: type=\(type.rawValue), keyCode=\(keyCode), flags=\(flags.rawValue), isQuickPasting=\(isQuickPasting)")

    let matchesLeft = eventMatchesShortcut(event, name: .quickAccessLeft)
    let matchesRight = eventMatchesShortcut(event, name: .quickAccessRight)
    let matchesCycle = eventMatchesShortcut(event, name: .quickAccessCycle)

    let isOptNavTrigger = matchesLeft || matchesRight || matchesCycle

    switch type {
    case .keyDown:
      let isCmdVTrigger = (keyCode == kVK_ANSI_V && isCommandDown)
      
      if isCmdVTrigger {
        if isQuickPasting {
          return nil
        }
        
        pendingDownEvent = event.copy()
        activeModifier = .maskCommand
        DispatchQueue.main.async { [weak self] in
          self?.startHoldTimer()
        }
        return nil
      }
      
      if isOptNavTrigger {
        if !isQuickPasting {
          isQuickPasting = true
          let name: KeyboardShortcuts.Name = matchesLeft ? .quickAccessLeft : (matchesRight ? .quickAccessRight : .quickAccessCycle)
          activeModifier = getShortcutModifiersFlags(name: name)
          
          AppState.shared.popup.open(height: AppState.shared.popup.height)
          AppState.shared.navigator.highlightFirstCardInCurrentTab()
          
          if matchesCycle {
            NotificationCenter.default.post(name: .commandVQuickNavigatePinboard, object: nil)
          }
        } else {
          if matchesLeft {
            NotificationCenter.default.post(name: .commandVQuickNavigateLeft, object: nil)
          } else if matchesRight {
            NotificationCenter.default.post(name: .commandVQuickNavigateRight, object: nil)
          } else if matchesCycle {
            NotificationCenter.default.post(name: .commandVQuickNavigatePinboard, object: nil)
          }
        }
        
        return nil
      }
      
      if isQuickPasting {
        let eventModifierFlags = flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        if let activeMod = activeModifier, eventModifierFlags.contains(activeMod) {
          if matchesLeft || (keyCode == kVK_LeftArrow) {
            NotificationCenter.default.post(name: .commandVQuickNavigateLeft, object: nil)
            return nil
          } else if matchesRight || (keyCode == kVK_RightArrow) {
            NotificationCenter.default.post(name: .commandVQuickNavigateRight, object: nil)
            return nil
          } else if matchesCycle {
            NotificationCenter.default.post(name: .commandVQuickNavigatePinboard, object: nil)
            return nil
          }
        }
        return nil
      }
      
    case .keyUp:
      let isLeftKey = KeyboardShortcuts.Shortcut(name: .quickAccessLeft)?.key.map { keyCode == Int($0.rawValue) } ?? false
      let isRightKey = KeyboardShortcuts.Shortcut(name: .quickAccessRight)?.key.map { keyCode == Int($0.rawValue) } ?? false
      let isCycleKey = KeyboardShortcuts.Shortcut(name: .quickAccessCycle)?.key.map { keyCode == Int($0.rawValue) } ?? false
      let isArrowKey = (keyCode == kVK_LeftArrow || keyCode == kVK_RightArrow)
      let isVKey = (keyCode == kVK_ANSI_V)
      
      let isTriggerKey = isLeftKey || isRightKey || isCycleKey || isArrowKey || isVKey
      
      if isTriggerKey {
        if isQuickPasting {
          return nil
        }
        
        if holdTimer != nil {
          // Capture the pending ⌘V *before* cancelHoldTimer() clears it,
          // otherwise reinjectNormalPaste() sees a nil event and no paste fires.
          let pending = pendingDownEvent
          cancelHoldTimer()
          if let pending {
            reinjectNormalPaste(pending)
          }
          return nil
        }
      }

      if isQuickPasting {
        return nil
      }
      
    case .flagsChanged:
      if let activeMod = activeModifier {
        let modifierIsStillDown = flags.contains(activeMod)
        if !modifierIsStillDown {
          if holdTimer != nil {
            // Capture before cancelHoldTimer() clears pendingDownEvent.
            let pending = pendingDownEvent
            cancelHoldTimer()
            if let pending {
              reinjectNormalPaste(pending)
            }
            return Unmanaged.passRetained(event)
          }
          
          if isQuickPasting {
            isQuickPasting = false
            activeModifier = nil
            NotificationCenter.default.post(name: .commandVQuickRelease, object: nil)
            return Unmanaged.passRetained(event)
          }
        }
      }
      
    default:
      break
    }

    return Unmanaged.passRetained(event)
  }
  
  private func startHoldTimer() {
    holdTimer?.invalidate()
    holdTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
      self?.triggerQuickPasteMode()
    }
  }

  private func cancelHoldTimer() {
    holdTimer?.invalidate()
    holdTimer = nil
    pendingDownEvent = nil
    activeModifier = nil
  }

  private func triggerQuickPasteMode() {
    holdTimer = nil
    pendingDownEvent = nil
    isQuickPasting = true
    
    AppState.shared.popup.open(height: AppState.shared.popup.height)
    AppState.shared.navigator.highlightFirstCardInCurrentTab()
  }

  private func reinjectNormalPaste(_ downEvent: CGEvent) {
    pendingDownEvent = nil
    activeModifier = nil

    isReinjecting = true

    downEvent.setIntegerValueField(.eventSourceUserData, value: Self.synthesizedEventMarker)
    downEvent.post(tap: .cgAnnotatedSessionEventTap)

    if let source = CGEventSource(stateID: .combinedSessionState) {
      let keyCode = downEvent.getIntegerValueField(.keyboardEventKeycode)
      let upEvent = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false)
      upEvent?.flags = downEvent.flags
      upEvent?.setIntegerValueField(.eventSourceUserData, value: Self.synthesizedEventMarker)
      upEvent?.post(tap: .cgAnnotatedSessionEventTap)
    }
    
    DispatchQueue.main.async { [weak self] in
      self?.isReinjecting = false
    }
  }
}
