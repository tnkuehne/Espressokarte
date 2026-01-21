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
    @Published private(set) var userName: String?
    @Published private(set) var error: Error?

    private let tokenKey = "com.espressokarte.appleIdentityToken"
    private let userIdKey = "com.espressokarte.appleUserIdentifier"
    private let userNameKey = "com.espressokarte.appleUserName"

    private var keychainAccessGroup: String {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String
        else {
            fatalError("KeychainAccessGroup not found in Info.plist")
        }
        return group
    }

    private var signInContinuation: CheckedContinuation<String, Error>?

    override private init() {
        super.init()
        Task {
            await checkExistingCredentials()
        }
    }

    // MARK: - Public API

    func getValidToken() async throws -> String {
        if let token = getKeychainValue(forKey: tokenKey) {
            return token
        }
        throw AppleSignInError.notSignedIn
    }

    func checkExistingCredentials() async {
        guard let userId = getKeychainValue(forKey: userIdKey) else {
            isSignedIn = false
            return
        }

        do {
            let credentialState = try await ASAuthorizationAppleIDProvider()
                .credentialState(forUserID: userId)

            switch credentialState {
            case .authorized:
                if getKeychainValue(forKey: tokenKey) != nil {
                    userIdentifier = userId
                    userName = getKeychainValue(forKey: userNameKey)
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

    func signOut() {
        clearCredentials()
        isSignedIn = false
        userIdentifier = nil
        userName = nil
    }

    // MARK: - Keychain Helpers

    private func setKeychainValue(_ value: String, forKey key: String) {
        let data = Data(value.utf8)

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: keychainAccessGroup,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: keychainAccessGroup,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func getKeychainValue(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: keychainAccessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
            let data = result as? Data,
            let value = String(data: data, encoding: .utf8),
            !value.isEmpty
        else {
            return nil
        }

        return value
    }

    private func deleteKeychainValue(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: keychainAccessGroup,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func clearCredentials() {
        deleteKeychainValue(forKey: tokenKey)
        deleteKeychainValue(forKey: userIdKey)
        deleteKeychainValue(forKey: userNameKey)
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

            // Store credentials in Keychain
            setKeychainValue(identityToken, forKey: tokenKey)
            setKeychainValue(credential.user, forKey: userIdKey)

            // Store name if provided (only on first sign-in)
            if let fullName = credential.fullName {
                let givenName = fullName.givenName ?? ""
                let familyName = fullName.familyName ?? ""
                let displayName = [givenName, familyName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                if !displayName.isEmpty {
                    setKeychainValue(displayName, forKey: userNameKey)
                    userName = displayName
                }
            }

            // Load stored name if not set from this sign-in
            if userName == nil {
                userName = getKeychainValue(forKey: userNameKey)
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
