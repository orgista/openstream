import Foundation
import Observation
import Security

public enum AppleKeychainStoreError: LocalizedError, Sendable {
    case unexpectedStatus(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }
            return "Keychain error \(status)."
        case .invalidData:
            return "The saved credential could not be read."
        }
    }
}

/// Stores credentials in the local data-protection Keychain. ThisDeviceOnly
/// accessibility keeps them out of device backups and iCloud Keychain sync.
public struct AppleKeychainStore: Sendable {
    private let service: String

    public init(service: String = "com.orgista.openstream.settings") {
        self.service = service
    }

    public func string(for account: String) throws -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw AppleKeychainStoreError.unexpectedStatus(status)
        }
        guard let data = value as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw AppleKeychainStoreError.invalidData
        }
        return string
    }

    public func set(_ value: String, for account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(for: account)
        let update = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw AppleKeychainStoreError.unexpectedStatus(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw AppleKeychainStoreError.unexpectedStatus(updateStatus)
        }
    }

    public func remove(_ account: String) throws {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppleKeychainStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }
}

@MainActor
@Observable
public final class AppleSettingsStore {
    public var metadataEnabled: Bool {
        didSet { defaults.set(metadataEnabled, forKey: DefaultsKey.metadataEnabled) }
    }

    public var tmdbAPIKey: String {
        didSet { persistSecret(tmdbAPIKey, account: SecretKey.tmdbAPIKey) }
    }

    public var omdbAPIKey: String {
        didSet { persistSecret(omdbAPIKey, account: SecretKey.omdbAPIKey) }
    }

    public var radarrURL: String {
        didSet { defaults.set(radarrURL, forKey: DefaultsKey.radarrURL) }
    }

    public var radarrAPIKey: String {
        didSet { persistSecret(radarrAPIKey, account: SecretKey.radarrAPIKey) }
    }

    public var sonarrURL: String {
        didSet { defaults.set(sonarrURL, forKey: DefaultsKey.sonarrURL) }
    }

    public var sonarrAPIKey: String {
        didSet { persistSecret(sonarrAPIKey, account: SecretKey.sonarrAPIKey) }
    }

    public var gatewayEnabled: Bool {
        didSet { defaults.set(gatewayEnabled, forKey: DefaultsKey.gatewayEnabled) }
    }

    public var gatewayURL: String {
        didSet { defaults.set(gatewayURL, forKey: DefaultsKey.gatewayURL) }
    }

    public var gatewayToken: String {
        didSet { persistSecret(gatewayToken, account: SecretKey.gatewayToken) }
    }

    public var traktClientID: String {
        didSet { persistSecret(traktClientID, account: SecretKey.traktClientID) }
    }

    public var traktClientSecret: String {
        didSet { persistSecret(traktClientSecret, account: SecretKey.traktClientSecret) }
    }

    public var captionsAutoOn: Bool {
        didSet { defaults.set(captionsAutoOn, forKey: DefaultsKey.captionsAutoOn) }
    }

    public var deleteAfterWatching: Bool {
        didSet { defaults.set(deleteAfterWatching, forKey: DefaultsKey.deleteAfterWatching) }
    }

    public private(set) var persistenceError: String?

    private let defaults: UserDefaults
    private let keychain: AppleKeychainStore

    public init(
        defaults: UserDefaults = .standard,
        keychain: AppleKeychainStore = AppleKeychainStore()
    ) {
        self.defaults = defaults
        self.keychain = keychain

        metadataEnabled = defaults.object(forKey: DefaultsKey.metadataEnabled) as? Bool ?? false
        radarrURL = defaults.string(forKey: DefaultsKey.radarrURL) ?? ""
        sonarrURL = defaults.string(forKey: DefaultsKey.sonarrURL) ?? ""
        gatewayEnabled = defaults.bool(forKey: DefaultsKey.gatewayEnabled)
        gatewayURL = defaults.string(forKey: DefaultsKey.gatewayURL) ?? ""
        captionsAutoOn = defaults.bool(forKey: DefaultsKey.captionsAutoOn)
        deleteAfterWatching = defaults.bool(forKey: DefaultsKey.deleteAfterWatching)

        tmdbAPIKey = (try? keychain.string(for: SecretKey.tmdbAPIKey)) ?? ""
        omdbAPIKey = (try? keychain.string(for: SecretKey.omdbAPIKey)) ?? ""
        radarrAPIKey = (try? keychain.string(for: SecretKey.radarrAPIKey)) ?? ""
        sonarrAPIKey = (try? keychain.string(for: SecretKey.sonarrAPIKey)) ?? ""
        gatewayToken = (try? keychain.string(for: SecretKey.gatewayToken)) ?? ""
        traktClientID = (try? keychain.string(for: SecretKey.traktClientID)) ?? ""
        traktClientSecret = (try? keychain.string(for: SecretKey.traktClientSecret)) ?? ""
        persistenceError = nil
    }

    public func clearPersistenceError() {
        persistenceError = nil
    }

    private func persistSecret(_ value: String, account: String) {
        do {
            if value.isEmpty {
                try keychain.remove(account)
            } else {
                try keychain.set(value, for: account)
            }
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    private enum DefaultsKey {
        static let metadataEnabled = "openstream.settings.metadata.enabled.v1"
        static let radarrURL = "openstream.settings.radarr.url.v1"
        static let sonarrURL = "openstream.settings.sonarr.url.v1"
        static let gatewayEnabled = "openstream.settings.gateway.enabled.v1"
        static let gatewayURL = "openstream.settings.gateway.url.v1"
        static let captionsAutoOn = "openstream.settings.captions.autoOn.v1"
        static let deleteAfterWatching = "openstream.settings.downloads.deleteAfterWatching.v1"
    }

    private enum SecretKey {
        static let tmdbAPIKey = "metadata.tmdb.apiKey"
        static let omdbAPIKey = "metadata.omdb.apiKey"
        static let radarrAPIKey = "downloads.radarr.apiKey"
        static let sonarrAPIKey = "downloads.sonarr.apiKey"
        static let gatewayToken = "transcode.gateway.token"
        static let traktClientID = "trakt.client.id"
        static let traktClientSecret = "trakt.client.secret"
    }
}
