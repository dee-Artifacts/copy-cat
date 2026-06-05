import AppKit
import Settings
import SwiftUI

struct LicenseSettingsPane: View {
  @State private var manager = LicenseManager.shared
  @State private var keyInput = ""
  @State private var working = false
  @State private var message: String?
  @State private var messageIsError = false

  @Environment(\.colorScheme) private var colorScheme
  private var brandAccent: Color {
    colorScheme == .dark ? Color(hex: "57D559")! : Color(hex: "024E50")!
  }

  var body: some View {
    Settings.Container(contentWidth: 450) {
      Settings.Section(bottomDivider: true, label: { Text("Status") }) {
        statusRow
      }

      Settings.Section(bottomDivider: true, label: { Text("License Key") }) {
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 8) {
            TextField("Paste your license key", text: $keyInput)
              .textFieldStyle(.roundedBorder)
              .frame(width: 250)
              .onSubmit(activate)
            Button(action: activate) {
              if working {
                ProgressView().controlSize(.small)
              } else {
                Text("Submit").frame(minWidth: 56)
              }
            }
            .buttonStyle(.borderedProminent)
            .disabled(working || keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
          }
          if let message {
            Text(message)
              .controlSize(.small)
              .foregroundStyle(messageIsError ? Color.red : brandAccent)
          }
          if case .licensed = manager.state {
            Button("Deactivate this Mac", role: .destructive, action: deactivate)
              .controlSize(.small)
              .disabled(working)
          }
        }
      }

      Settings.Section(label: { Text("Buy a License") }) {
        VStack(alignment: .leading, spacing: 6) {
          buyButton("Single device — £4.99", url: LicenseConfig.checkoutURLSingle)
          buyButton("3 devices — £7.99", url: LicenseConfig.checkoutURLTrio)
          buyButton("Unlimited devices — £9.99", url: LicenseConfig.checkoutURLUnlimited)
          Text("Includes free updates. A \(LicenseConfig.trialDays)-day free trial is active on first install.")
            .controlSize(.small)
            .foregroundStyle(.gray)
        }
      }
    }
  }

  @ViewBuilder private var statusRow: some View {
    switch manager.state {
    case .licensed:
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "checkmark.seal.fill").foregroundStyle(brandAccent).padding(.top, 1)
        VStack(alignment: .leading, spacing: 2) {
          Text("Licensed").font(.system(size: 13, weight: .semibold))
          if let email = manager.customerEmail {
            Text("Licensed to \(email)").controlSize(.small).foregroundStyle(.gray)
          }
        }
      }
    case let .trial(daysLeft):
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "clock.fill").foregroundStyle(brandAccent).padding(.top, 1)
        VStack(alignment: .leading, spacing: 2) {
          Text("Free trial — \(daysLeft) day\(daysLeft == 1 ? "" : "s") left")
            .font(.system(size: 13, weight: .semibold))
          Text("All features unlocked during the trial.").controlSize(.small).foregroundStyle(.gray)
        }
        HStack(spacing: 4) {
          Image(systemName: "clock").font(.system(size: 9))
          Text("\(daysLeft)d • Trial").font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(brandAccent)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(brandAccent.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(brandAccent.opacity(0.35), lineWidth: 1))
        .fixedSize()
      }
    case .expired:
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "lock.fill").foregroundStyle(.orange).padding(.top, 1)
        VStack(alignment: .leading, spacing: 2) {
          Text("Trial ended").font(.system(size: 13, weight: .semibold))
          Text("Copy Cat is locked. Enter a license key below to unlock everything again.")
            .controlSize(.small).foregroundStyle(.gray)
        }
      }
    }
  }

  private func buyButton(_ label: String, url: String) -> some View {
    Button(label) {
      if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
    .disabled(url.isEmpty)
  }

  private func activate() {
    let key = keyInput
    working = true
    message = nil
    Task {
      defer { working = false }
      do {
        _ = try await manager.activate(key: key)
        message = "License activated. Thank you!"
        messageIsError = false
        keyInput = ""
      } catch LicenseError.activationLimitReached {
        message = "This license has reached its device limit. Deactivate another Mac or buy more seats."
        messageIsError = true
      } catch LicenseError.invalidKey {
        message = "That license key wasn't recognized. Double-check and try again."
        messageIsError = true
      } catch {
        message = "Couldn't reach the licensing server. Check your connection and try again."
        messageIsError = true
      }
    }
  }

  private func deactivate() {
    working = true
    message = nil
    Task {
      defer { working = false }
      await manager.deactivateLocal()
      message = "License removed from this Mac."
      messageIsError = false
    }
  }
}

// MARK: - License gating for Settings panes

extension View {
  /// One fixed size for every Settings pane, so the window doesn't resize per
  /// tab and the first-opened pane renders instead of appearing blank.
  func settingsPaneSize() -> some View {
    frame(width: 540, height: 480, alignment: .top)
  }
}

/// Wraps a Settings pane. Once the trial has expired the pane is replaced by a
/// "Buy Copy Cat" notice — every screen except License is locked until activated.
struct LicenseGatedPane<Content: View>: View {
  @ViewBuilder var content: () -> Content
  @State private var manager = LicenseManager.shared

  var body: some View {
    if case .expired = manager.state {
      BuyCopyCatNotice()
    } else {
      content()
    }
  }
}

struct BuyCopyCatNotice: View {
  @Environment(\.colorScheme) private var colorScheme
  private var accent: Color { colorScheme == .dark ? Color(hex: "57D559")! : Color(hex: "024E50")! }

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "lock.fill").font(.system(size: 34)).foregroundStyle(accent)
      Text("Your free trial has ended").font(.system(size: 16, weight: .bold))
      Text("Buy Copy Cat to keep using it. Enter your license key in the License tab to unlock everything again.")
        .font(.system(size: 12)).foregroundStyle(.gray)
        .multilineTextAlignment(.center).frame(maxWidth: 320)
      Button {
        AppState.shared.openLicensePane()
      } label: {
        Text("Buy Copy Cat").fontWeight(.semibold).frame(minWidth: 140)
      }
      .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }
}
