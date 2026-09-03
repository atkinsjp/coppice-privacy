//
//  AccountService.swift
//  CoppiceHabitsThatRest
//
//  Sign in with Apple — the app's single identity anchor.
//
//  Design notes:
//
//  - There are no passwords, no email accounts, no server sessions here.
//    The identity is the user's Apple ID credential, resolved by the system
//    `AuthenticationServices` stack. That is deliberate: CoppiceHabitsThatRest has no
//    backend, so an account must cost nothing to run.
//  - The Apple **user identifier** is stored in the Keychain, not UserDefaults,
//    because Keychain survives delete + reinstall. A returning user who wiped
//    the app is recognized the moment they sign back in rather than being
//    treated as a stranger — the property trials and Pro restoration will
//    eventually hang off this identifier.
//  - Name and email are only ever delivered on the *first* authorization for
//    a given app; every later sign-in returns just the stable identifier.
//    So they are cached at first sight and never overwritten with empty
//    values afterward.
//

import Foundation
import Observation
import AuthenticationServices

@Observable
final class AccountService {
    /// The stable per-user identifier Apple returns (`user` on the credential).
    /// Non-nil means the user has signed in on this device.
    private(set) var appleUserIdentifier: String?

    /// Display name as delivered by Apple on first authorization. May be nil
    /// (Apple only sends it once; users can skip sharing it entirely).
    private(set) var fullName: String?

    /// The email address shared on first authorization, if the user chose
    /// "Share My Email" rather than Hide My Email.
    private(set) var email: String?

    /// Whether an Apple identity is currently attached on this device.
    var isSignedIn: Bool { appleUserIdentifier != nil }
    // MARK: - Storage keys

    private static let keychainService = "com.atkinsmedia.stillhabit.account"
    private static let keychainAccount = "appleUserIdentifier"
    private static let nameDefaultsKey = "stillhabit.appleFullName"
    private static let emailDefaultsKey = "stillhabit.appleEmail"

    init() {
        restorePersistedIdentity()
        Task { await refreshCredentialState() }
    }

    // MARK: - Public state

    /// A display string for Settings: the shared name, else the email,
    /// else a quiet placeholder for users who declined both.
    var displayName: String {
        if let fullName, !fullName.isEmpty { return fullName }
        if let email, !email.isEmpty { return email }
        return "Apple ID"
    }

    // MARK: - Sign in

    /// Builds the authorization request for the SwiftUI button: name and
    /// email scopes requested once — later grants return only the identifier.
    func makeRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    /// Consumes the result of a Sign in with Apple flow. Stores the stable
    /// identifier, captures first-delivery profile fields, and persists both.
    func handleAuthorization(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                CrashDiagnostics.note("siwa unexpected credential type")
                return
            }
            let identifier = credential.user

            // Profile fields arrive exactly once, ever — capture before they're gone.
            if let components = credential.fullName {
                let formatter = PersonNameComponentsFormatter()
                let composed = formatter.string(from: components)
                if !composed.isEmpty { fullName = composed }
            }
            if let sharedEmail = credential.email, !sharedEmail.isEmpty {
                email = sharedEmail
            }

            appleUserIdentifier = identifier
            persistIdentity()
            CrashDiagnostics.note("siwa success")

        case .failure(let error):
            // User-cancelled attempts surface here too; log without internals.
            CrashDiagnostics.note("siwa failed: \(error.localizedDescription)")
        }
    }

    /// Local sign-out. Apple offers no remote revoke of a device grant from
    /// inside the app; this detaches the identity locally and forgets the
    /// cached profile too. The user can sign back in any time and resolve to
    /// the same identifier.
    func signOut() {
        appleUserIdentifier = nil
        fullName = nil
        email = nil
        Self.deleteKeychainID()
        UserDefaults.standard.removeObject(forKey: Self.nameDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.emailDefaultsKey)
        CrashDiagnostics.note("account signed out")
    }

    // MARK: - Credential verification

    /// Re-validates the stored identifier against Apple. Called at launch and
    /// again on every foreground activation (that cadence replaces listening
    /// for Apple's global revocation notification). Revoked or removed
    /// credentials detach the account silently — e.g. when the user cuts the
    /// app off under iOS Settings → Sign-In & Security. The cached name/email
    /// are deliberately kept on a forced detach: they are display data and
    /// make the next sign-in read as a welcome-back instead of a blank form.
    func refreshCredentialState() async {
        guard let identifier = appleUserIdentifier else { return }
        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: identifier)
            switch state {
            case .authorized:
                break
            case .transferred:
                break
            case .revoked, .notFound:
                appleUserIdentifier = nil
                Self.deleteKeychainID()
                CrashDiagnostics.note("siwa credential detached by system")
            @unknown default:
                break
            }
        } catch {
            // Transient Keychain/AuthKit failures shouldn't eject the user;
            // keep the stored identity and retry next foreground.
            CrashDiagnostics.note("siwa state check unavailable")
        }
    }

    // MARK: - Persistence

    private func restorePersistedIdentity() {
        appleUserIdentifier = Self.readKeychainID()
        fullName = UserDefaults.standard.string(forKey: Self.nameDefaultsKey)
        email = UserDefaults.standard.string(forKey: Self.emailDefaultsKey)
    }

    private func persistIdentity() {
        if let identifier = appleUserIdentifier {
            Self.writeKeychainID(identifier)
        }
        UserDefaults.standard.set(fullName, forKey: Self.nameDefaultsKey)
        UserDefaults.standard.set(email, forKey: Self.emailDefaultsKey)
    }

    // MARK: - Keychain (identifier survives reinstall)

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
    }

    private static func readKeychainID() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychainID(_ value: String) {
        let data = Data(value.utf8)
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemUpdate(baseQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
    }

    private static func deleteKeychainID() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
