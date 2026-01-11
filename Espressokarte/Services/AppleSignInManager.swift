//
//  AppleSignInManager.swift
//  Espressokarte
//
//  Created by Claude on 07.01.26.
//

import AuthenticationServices
import Combine
import Foundation
import Security

/// Manages Apple Sign In authentication and token storage
@MainActor
final class AppleSignInManager: NSObject, ObservableObject {
    static let shared = AppleSignInManager()

    @Published private(set) var isSignedIn: Bool = false
    @Published private(set) var userIdentifier: String?
    @Published private(set) var error: Error?

    private let tokenKey = "com.espressokarte.appleIdentityToken"
    private let userIdKey = "com.espressokarte.appleUserIdentifier"
    private let userNameKey = "com.espressokarte.appleUserName"
    // App group for UserDefaults sharing
    private let appGroup = "group.com.timokuehne.Espressokarte"
    // Keychain access group for token sharing (read from Info.plist, includes team ID prefix)
    private var keychainAccessGroup: String {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String
        else {
            fatalError("KeychainAccessGroup not found in Info.plist")
        }
        return group
    }

    @Published private(set) var userName: String?

    private var signInContinuation: CheckedContinuation<String, Error>?

    override private init() {
        super.init()
        // Check for existing credentials on init
        Task {
            await checkExistingCredentials()
        }
    }

    // MARK: - Public API

    /// Returns a valid identity token, or throws if not signed in
    func getValidToken() async throws -> String {
        if let token = getStoredToken() {
            return token
        }
        throw AppleSignInError.notSignedIn
    }

    /// Check if user has valid stored credentials
    func checkExistingCredentials() async {
        let sharedDefaults = UserDefaults(suiteName: appGroup)

        guard let userId = sharedDefaults?.string(forKey: userIdKey) else {
            isSignedIn = false
            return
        }

        do {
            let credentialState = try await ASAuthorizationAppleIDProvider()
                .credentialState(forUserID: userId)

            switch credentialState {
            case .authorized:
                if getStoredToken() != nil {
                    userIdentifier = userId
                    userName = sharedDefaults?.string(forKey: userNameKey)
                    isSignedIn = true
                } else {
                    isSignedIn = false
                }
            case .revoked, .notFound:
                clearCredentials()
                isSignedIn = false
            case .transferred:
                isSignedIn = false
            @unknown default:
                isSignedIn = false
            }
        } catch {
            self.error = error
            isSignedIn = false
        }
    }

    /// Perform Sign in with Apple
    func signIn() async throws -> String {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self

        return try await withCheckedThrowingContinuation { continuation in
            self.signInContinuation = continuation
            controller.performRequests()
        }
    }

    /// Sign out and clear stored credentials
    func signOut() {
        clearCredentials()
        isSignedIn = false
        userIdentifier = nil
        userName = nil
    }

    // MARK: - Private Helpers

    private func getStoredToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecAttrAccessGroup as String: keychainAccessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
            let data = result as? Data,
            let token = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return token
    }

    private func storeToken(_ token: String) {
        let data = Data(token.utf8)

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecAttrAccessGroup as String: keychainAccessGroup,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecAttrAccessGroup as String: keychainAccessGroup,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func clearCredentials() {
        // Clear Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecAttrAccessGroup as String: keychainAccessGroup,
        ]
        SecItemDelete(query as CFDictionary)

        // Clear UserDefaults (use shared container for extension access)
        let sharedDefaults = UserDefaults(suiteName: appGroup)
        sharedDefaults?.removeObject(forKey: userIdKey)
        sharedDefaults?.removeObject(forKey: userNameKey)
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInManager: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let identityTokenData = credential.identityToken,
                let identityToken = String(data: identityTokenData, encoding: .utf8)
            else {
                signInContinuation?.resume(throwing: AppleSignInError.invalidCredential)
                signInContinuation = nil
                return
            }

            // Store credentials
            storeToken(identityToken)
            let sharedDefaults = UserDefaults(suiteName: appGroup)
            sharedDefaults?.set(credential.user, forKey: userIdKey)

            // Store full name if provided (only available on first sign-in)
            if let fullName = credential.fullName {
                let givenName = fullName.givenName ?? ""
                let familyName = fullName.familyName ?? ""
                let displayName = [givenName, familyName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                if !displayName.isEmpty {
                    sharedDefaults?.set(displayName, forKey: userNameKey)
                    userName = displayName
                }
            }

            // Load stored name if not set from this sign-in
            if userName == nil {
                userName = sharedDefaults?.string(forKey: userNameKey)
            }

            userIdentifier = credential.user
            isSignedIn = true
            error = nil

            signInContinuation?.resume(returning: identityToken)
            signInContinuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            self.error = error
            signInContinuation?.resume(throwing: error)
            signInContinuation = nil
        }
    }
}

// MARK: - Errors

enum AppleSignInError: LocalizedError {
    case notSignedIn
    case invalidCredential

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Please sign in with Apple to continue."
        case .invalidCredential:
            return "Failed to get valid credentials from Apple."
        }
    }
}
