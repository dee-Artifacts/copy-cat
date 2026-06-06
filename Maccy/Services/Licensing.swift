import CryptoKit
import Foundation
import Observation
import Security

// MARK: - Configuration

/// All tunable licensing constants live here. Lemon Squeezy IDs are filled in
/// AFTER the LS account/product exist — the license validate/activate endpoints
/// themselves only need the license key, so verification works as soon as you
/// have real keys; the store/product IDs are only used to build checkout links.
enum LicenseConfig {
  // Agreed product rules.
  static let trialDays = 7
  static let offlineGraceDays = 3
  static let freePinboardLimit = 2   // first N pinboards stay usable when expired
  static let freeHistoryLimit = 15   // most-recent N history items when expired

  // Lemon Squeezy license API (unauthenticated; safe to call from the client).
  static let licenseApiBase = "https://api.lemonsqueezy.com/v1"

  // TODO(LemonSqueezy): fill these in after creating the account/product.
  // Only needed to build the "Buy a license" checkout URLs, NOT for validation.
  static let storeId = "398481"
  // £4.99 / 1 device
  static let checkoutURLSingle = "https://copy-cat.lemonsqueezy.com/checkout/buy/4d669b84-8d9e-4fbd-b1f3-942df61c2756"
  // £7.99 / 3 devices
  static let checkoutURLTrio = "https://copy-cat.lemonsqueezy.com/checkout/buy/8ce3ac19-70ab-464a-9038-5ffed232433e"
  // £9.99 / unlimited
  static let checkoutURLUnlimited = "https://copy-cat.lemonsqueezy.com/checkout/buy/95523d44-c4e9-4c01-bf34-72462ee10257"

  /// Pre-launch testing aid: lets us force a license state without a real key.
  /// Set UserDefaults `CopyCatLicenseDebugState` to licensed | trial | expired.
  /// Compiled in ONLY for DEBUG builds run from Xcode — the public Release DMG
  /// has this branch removed entirely, so the override (and its magic strings)
  /// do not exist in what ships. There is nothing to type, find, or crack.
  #if DEBUG
  static let allowDebugOverride = true
  #else
  static let allowDebugOverride = false
  #endif
  static var debugStateOverride: LicenseState? {
    guard allowDebugOverride,
          let raw = UserDefaults.standard.string(forKey: "CopyCatLicenseDebugState")
    else { return nil }
    switch raw {
    case "licensed": return .licensed
    case "trial": return .trial(daysLeft: trialDays)
    case "expired": return .expired
    default: return nil
    }
  }
}

// MARK: - State

enum LicenseState: Equatable {
  case licensed
  case trial(daysLeft: Int)
  case expired

  /// True when the user has full access (paid, or still inside the trial).
  var isFullAccess: Bool {
    switch self {
    case .licensed, .trial: return true
    case .expired: return false
    }
  }
}

// MARK: - Persisted record (Keychain — survives reinstall)

private struct LicenseRecord: Codable {
  var trialStart: Date?
  var licenseKey: String?
  var instanceId: String?
  /// Last known validity from Lemon Squeezy: nil = never checked, true/false = LS said so.
  var cachedValid: Bool?
  var lastValidatedAt: Date?
  var customerEmail: String?
  /// Highest wall-clock time we've ever observed. Only moves forward, so rolling
  /// the system clock backward can't rewind the trial (anti-rollback guard).
  var lastSeenDate: Date?
  /// HMAC over the license fields, written only after a real Lemon Squeezy
  /// confirmation. `cachedValid == true` is trusted only when this matches, so a
  /// hand-edited Keychain blob (fake key + cachedValid=true) is rejected.
  var validationSignature: String?
}

// MARK: - Tamper-evident signing for the cached "licensed" flag

/// Signs the license fields so a hand-edited Keychain record can't fake a paid
/// license. The secret is assembled at runtime (not one visible literal) — this
/// stops casual Keychain tampering (attack #3). A determined binary-patch
/// (attack #4) can still defeat it; that's the accepted ceiling for any offline
/// app and not worth chasing for a low-price product.
private enum LicenseSigner {
  private static var secret: SymmetricKey {
    let parts = ["cc", "9f3a2e", "keychain", "v1", "57D559", "024E50"]
    return SymmetricKey(data: Data(parts.joined(separator: "·").utf8))
  }

  static func sign(_ rec: LicenseRecord) -> String {
    let payload = [
      rec.licenseKey ?? "",
      rec.instanceId ?? "",
      String(rec.lastValidatedAt?.timeIntervalSince1970 ?? 0),
      rec.cachedValid == true ? "1" : "0"
    ].joined(separator: "|")
    let mac = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: secret)
    return Data(mac).base64EncodedString()
  }

  /// True only when the record's signature matches its current fields — i.e. the
  /// fields were written by a genuine server confirmation, not hand-edited.
  static func confirms(_ rec: LicenseRecord) -> Bool {
    guard let sig = rec.validationSignature else { return false }
    return sig == sign(rec)
  }
}

// MARK: - Keychain helper

private enum LicenseKeychain {
  static let service = "com.copycat.app.license"
  static let account = "record"

  static func save(_ data: Data) {
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
    SecItemDelete(base as CFDictionary)
    var add = base
    add[kSecValueData as String] = data
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    SecItemAdd(add as CFDictionary, nil)
  }

  static func load() -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
    return result as? Data
  }

  static func clear() {
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
    SecItemDelete(base as CFDictionary)
  }
}

// MARK: - Verifier

struct LicenseValidation {
  var isValid: Bool
  var instanceId: String?
  var email: String?
}

enum LicenseError: Error {
  case activationLimitReached
  case invalidKey
  case network
}

protocol LicenseVerifier {
  func activate(key: String, instanceName: String) async throws -> LicenseValidation
  func validate(key: String, instanceId: String?) async throws -> LicenseValidation
  func deactivate(key: String, instanceId: String) async throws
}

/// Talks to Lemon Squeezy's unauthenticated license endpoints.
struct LemonSqueezyVerifier: LicenseVerifier {
  private func post(_ path: String, fields: [String: String]) async throws -> [String: Any] {
    guard let url = URL(string: "\(LicenseConfig.licenseApiBase)/\(path)") else {
      throw LicenseError.network
    }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.httpBody = fields
      .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? "")" }
      .joined(separator: "&")
      .data(using: .utf8)

    let (data, _) = try await URLSession.shared.data(for: req)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw LicenseError.network
    }
    return json
  }

  private func parse(_ json: [String: Any], validFlag: String) -> LicenseValidation {
    let isValid = (json[validFlag] as? Bool) ?? false
    let instance = json["instance"] as? [String: Any]
    let meta = json["meta"] as? [String: Any]
    return LicenseValidation(
      isValid: isValid,
      instanceId: instance?["id"] as? String,
      email: meta?["customer_email"] as? String
    )
  }

  func activate(key: String, instanceName: String) async throws -> LicenseValidation {
    let json = try await post("licenses/activate",
                              fields: ["license_key": key, "instance_name": instanceName])
    if let err = json["error"] as? String, !err.isEmpty,
       (json["activated"] as? Bool) != true {
      if err.lowercased().contains("activation limit") { throw LicenseError.activationLimitReached }
      throw LicenseError.invalidKey
    }
    return parse(json, validFlag: "activated")
  }

  func validate(key: String, instanceId: String?) async throws -> LicenseValidation {
    var fields = ["license_key": key]
    if let instanceId { fields["instance_id"] = instanceId }
    let json = try await post("licenses/validate", fields: fields)
    return parse(json, validFlag: "valid")
  }

  func deactivate(key: String, instanceId: String) async throws {
    _ = try await post("licenses/deactivate",
                       fields: ["license_key": key, "instance_id": instanceId])
  }
}

private extension CharacterSet {
  static let urlQueryValueAllowed: CharacterSet = {
    var set = CharacterSet.urlQueryAllowed
    set.remove(charactersIn: "&=+")
    return set
  }()
}

// MARK: - Manager (the brain)

@MainActor
@Observable
final class LicenseManager {
  static let shared = LicenseManager()

  private(set) var state: LicenseState = .trial(daysLeft: LicenseConfig.trialDays)
  private(set) var customerEmail: String?

  /// Thread-safe snapshot for CommandVMonitor's event-tap callback, which runs
  /// off the main actor and cannot touch `state` directly. A word-sized Bool;
  /// the benign read/write race is acceptable for a feature gate.
  nonisolated(unsafe) static var quickPasteAllowedFlag = true
  /// True once the trial has expired — read off the main actor (e.g. the
  /// clipboard poll) to freeze recording until a license is activated.
  nonisolated(unsafe) static var isExpiredFlag = false
  /// True only for a paid/activated license — read off the main actor (e.g. the
  /// status-bar menu) to hide "Activate License…" once the user is licensed.
  nonisolated(unsafe) static var isLicensedFlag = false

  private let verifier: LicenseVerifier

  /// Hourly safety tick + a precise one-shot at the exact expiry instant, so the
  /// pill counts down and the lock lands on time WITHOUT a relaunch.
  private var refreshTimer: Timer?
  private var expiryTimer: Timer?

  init(verifier: LicenseVerifier = LemonSqueezyVerifier()) {
    self.verifier = verifier
    resolveOnLaunch()
  }

  private func setState(_ newState: LicenseState) {
    state = newState
    Self.quickPasteAllowedFlag = newState.isFullAccess
    Self.isExpiredFlag = (newState == .expired)
    Self.isLicensedFlag = (newState == .licensed)
    scheduleRefreshTimers()
  }

  // MARK: Live refresh (no relaunch needed)

  /// Re-evaluate state in place — no trialStart re-stamp, no network. Lets the
  /// trial count down and flip to Expired while the app stays open.
  func refreshState() {
    if let override = LicenseConfig.debugStateOverride {
      setState(override)
      return
    }
    var rec = loadRecord()
    let now = monotonicNow(rec)
    if rec.lastSeenDate != now {
      rec.lastSeenDate = now
      saveRecord(rec)
    }
    setState(computeState(from: rec, asOf: now))
  }

  /// (Re)arm the refresh timers. The hourly tick is a safety net; the one-shot
  /// fires at trialStart + trialDays so expiry locks the moment it's due.
  private func scheduleRefreshTimers() {
    if refreshTimer == nil {
      let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
        Task { @MainActor in self?.refreshState() }
      }
      RunLoop.main.add(timer, forMode: .common)
      refreshTimer = timer
    }

    expiryTimer?.invalidate()
    expiryTimer = nil
    guard case .trial = state, LicenseConfig.debugStateOverride == nil else { return }
    let rec = loadRecord()
    guard let start = rec.trialStart,
          let expiry = Calendar.current.date(byAdding: .day, value: LicenseConfig.trialDays, to: start),
          expiry > Date() else { return }
    let oneShot = Timer(timeInterval: expiry.timeIntervalSinceNow + 1, repeats: false) { [weak self] _ in
      Task { @MainActor in self?.refreshState() }
    }
    RunLoop.main.add(oneShot, forMode: .common)
    expiryTimer = oneShot
  }

  // MARK: Gate-query helpers (read by the app to enforce the soft cap)

  var quickPasteAllowed: Bool { state.isFullAccess }

  /// True only for a paid/activated license (NOT during the trial).
  var isLicensed: Bool { if case .licensed = state { return true } else { return false } }

  /// nil = unlimited; otherwise only the most-recent N history items are reachable.
  var historyAccessLimit: Int? { state.isFullAccess ? nil : LicenseConfig.freeHistoryLimit }

  /// nil = unlimited; otherwise new pinboards beyond N are buy-gated.
  var pinboardCreateLimit: Int? { state.isFullAccess ? nil : LicenseConfig.freePinboardLimit }

  /// Pinboards are preserved on expiry; only access to index >= limit is gated.
  func canAccessPinboard(at index: Int) -> Bool {
    state.isFullAccess || index < LicenseConfig.freePinboardLimit
  }

  var trialDaysLeft: Int? {
    if case let .trial(days) = state { return days }
    return nil
  }

  // MARK: Persistence

  private func loadRecord() -> LicenseRecord {
    guard let data = LicenseKeychain.load(),
          let rec = try? JSONDecoder().decode(LicenseRecord.self, from: data) else {
      return LicenseRecord()
    }
    return rec
  }

  private func saveRecord(_ rec: LicenseRecord) {
    if let data = try? JSONEncoder().encode(rec) { LicenseKeychain.save(data) }
  }

  // MARK: State resolution

  func resolveOnLaunch() {
    if let override = LicenseConfig.debugStateOverride {
      setState(override)
      return
    }
    var rec = loadRecord()
    // Very first launch ever → stamp the trial start (survives reinstall).
    if rec.trialStart == nil && rec.licenseKey == nil {
      rec.trialStart = Date()
      saveRecord(rec)
    }
    // Anti-rollback: advance the high-water-mark clock and persist it, so a
    // backward clock change can't hand the user free trial time.
    let now = monotonicNow(rec)
    if rec.lastSeenDate != now {
      rec.lastSeenDate = now
      saveRecord(rec)
    }
    customerEmail = rec.customerEmail
    setState(computeState(from: rec, asOf: now))

    // Re-validate a licensed user quietly in the background (fail-open).
    if let key = rec.licenseKey, !key.isEmpty {
      Task { await self.revalidate(key: key, instanceId: rec.instanceId) }
    }
  }

  /// Monotonic "now": never earlier than the furthest-forward time we've ever
  /// recorded. Reading the raw system clock is fine for moving *forward*, but a
  /// rewind is clamped to the high-water-mark so the trial can't be replayed.
  private func monotonicNow(_ rec: LicenseRecord) -> Date {
    max(Date(), rec.lastSeenDate ?? .distantPast)
  }

  private func computeState(from rec: LicenseRecord, asOf now: Date) -> LicenseState {
    // Licensed path: trust a cached "valid" ONLY when a genuine server
    // confirmation signed it. A key with no/invalid signature (never validated,
    // or a hand-edited Keychain blob) falls through — a background revalidation
    // on launch can still upgrade a real key once the network confirms it.
    if let key = rec.licenseKey, !key.isEmpty {
      if rec.cachedValid == true, LicenseSigner.confirms(rec) {
        return .licensed
      }
      // explicitly invalid / unverified / tampered → fall through to trial/expired
    }
    // Trial path.
    if let start = rec.trialStart {
      let days = Calendar.current.dateComponents([.day], from: start, to: now).day ?? 0
      let left = LicenseConfig.trialDays - days
      if left > 0 { return .trial(daysLeft: left) }
    }
    return .expired
  }

  // MARK: Actions

  /// Activate a pasted key against Lemon Squeezy and persist it. Returns the
  /// resulting state; throws LicenseError on limit-reached / invalid / network.
  @discardableResult
  func activate(key: String) async throws -> LicenseState {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    let result = try await verifier.activate(key: trimmed, instanceName: Host.current().localizedName ?? "Mac")
    guard result.isValid else { throw LicenseError.invalidKey }

    var rec = loadRecord()
    rec.licenseKey = trimmed
    rec.instanceId = result.instanceId
    rec.cachedValid = true
    rec.lastValidatedAt = Date()
    rec.customerEmail = result.email
    rec.validationSignature = LicenseSigner.sign(rec) // sign AFTER all fields set
    saveRecord(rec)

    customerEmail = result.email
    setState(.licensed)
    return state
  }

  /// Background re-check; only an explicit invalid result downgrades the user.
  func revalidate(key: String, instanceId: String?) async {
    do {
      let result = try await verifier.validate(key: key, instanceId: instanceId)
      var rec = loadRecord()
      rec.cachedValid = result.isValid
      rec.lastValidatedAt = Date()
      if let email = result.email { rec.customerEmail = email }
      // Sign on a genuine "valid"; clear the signature otherwise so the cached
      // flag can never be trusted without a real confirmation.
      rec.validationSignature = result.isValid ? LicenseSigner.sign(rec) : nil
      saveRecord(rec)
      if !result.isValid {
        setState(computeState(from: rec, asOf: monotonicNow(rec))) // refunded/disabled
      } else {
        customerEmail = rec.customerEmail
        setState(.licensed)
      }
    } catch {
      // Network/ambiguous error → fail open, keep current state.
    }
  }

  /// Remove the license from this Mac (frees an activation slot).
  func deactivateLocal() async {
    let rec = loadRecord()
    if let key = rec.licenseKey, let inst = rec.instanceId {
      try? await verifier.deactivate(key: key, instanceId: inst)
    }
    var cleared = rec
    cleared.licenseKey = nil
    cleared.instanceId = nil
    cleared.cachedValid = nil
    cleared.customerEmail = nil
    cleared.validationSignature = nil
    saveRecord(cleared)
    customerEmail = nil
    setState(computeState(from: cleared, asOf: monotonicNow(cleared)))
  }
}
