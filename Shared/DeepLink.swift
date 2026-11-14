import Foundation

/// Ways into the app from outside it.
///
/// Two of these existed as promises before they existed as code: the widget's
/// description said "tap to scan" while having no tap target, and the Shortcuts action
/// said it opened the app "ready to scan a barcode" while only launching it. Both now
/// land in the same place.
enum DeepLink {
    static let scheme = "binmate"
    static let scanHost = "scan"

    /// What the widget opens. A URL is the only route available to it: a widget runs in
    /// its own process and cannot reach into the app's state.
    static var scan: URL {
        URL(string: "\(scheme)://\(scanHost)")!
    }

    static func isScanRequest(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme && url.host?.lowercased() == scanHost
    }
}

/// A request left for the app to act on when it next becomes active.
///
/// Used by the Shortcuts action rather than a URL. App Intents declared by the app
/// itself — with no separate intents extension — run *inside the app's process*, so
/// `UserDefaults.standard` here is the app's own and needs no App Group. That is the
/// opposite of the widget's situation, which is why the two use different routes.
enum PendingAction {
    private static let scannerKey = "pendingScannerRequest"

    static func requestScanner(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: scannerKey)
    }

    /// Reads the request and clears it, so a relaunch days later does not reopen the
    /// scanner out of nowhere.
    static func consumeScannerRequest(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.bool(forKey: scannerKey) else { return false }
        defaults.removeObject(forKey: scannerKey)
        return true
    }
}
