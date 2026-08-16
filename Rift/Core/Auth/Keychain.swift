// SPDX-License-Identifier: GPL-3.0-only
//
// Keychain — minimal generic-password wrapper. Auth cookies are sensitive
// session credentials: they live here, never on disk in plaintext and never in
// logs. Thread-safe (the Security C API is), so it's callable from the async
// network layer off the main actor.

import Foundation
import Security

enum Keychain {
    private static let service = "com.mymusicapp.auth"

    /// Returns the raw OSStatus so UI can report *why* a write failed — e.g. an
    /// item created by another binary (the `security` CLI) whose ACL doesn't
    /// trust this app, where the delete is refused and the add then hits
    /// errSecDuplicateItem. Silent failure here is undiagnosable.
    @discardableResult
    static func set(_ data: Data, account: String) -> OSStatus {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess { return status }
        Log.auth.error("Keychain add failed for \(account, privacy: .public): OSStatus \(status)")
        guard status == errSecDuplicateItem else { return status }

        // Item survived the delete (foreign ACL): update the value in place.
        let find: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update = SecItemUpdate(find as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if update != errSecSuccess {
            Log.auth.error("Keychain update failed for \(account, privacy: .public): OSStatus \(update)")
        }
        return update
    }

    static func get(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
