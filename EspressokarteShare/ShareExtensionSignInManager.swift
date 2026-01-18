//
//  ShareExtensionSignInManager.swift
//  EspressokarteShare
//
//  Created by Claude on 11.01.26.
//

import AuthenticationServices
import Foundation
import Security
import UIKit

/// Manages Apple Sign In authentication within the share extension
final class ShareExtensionSignInManager: NSObject {
    private let tokenKey = "com.espressokarte.appleIdentityToken"
    private let userIdKey = "com.espressokarte.appleUserIdentifier"
    private let userNameKey = "com.espressokarte.appleUserName"
    private let userNameKeychainKey = "com.espressokarte.appleUserNameKeychain"
    private let appGroup = "group.com.timokuehne.Espressokarte"

    private var keychainAccessGroup: String {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String
        else {
            fatalError("KeychainAccessGroup not found in Info.plist")
        }
        return group
    }

    private weak var presentationAnchor: UIWindow?
    private var signInContinuation: CheckedContinuation<String, Error>?

    /// Perform Sign in with Apple using the provided window as presentation anchor
    func signIn(presentingFrom window: UIWindow?) async throws -> String {
        guard let window = window else {
            throw ShareExtensionSignInError.noWindow
        }
        self.presentationAnchor = window

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { continuation in
            self.signInContinuation = continuation
            controller.performRequests()
        }
    }

    /// Check if user is signed in
    func isSignedIn() -> Bool {
        return getStoredToken() != nil && getUserRecordID() != nil
    }

    /// Get stored token
    func getStoredToken() -> String? {
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

    private func getUserRecordID() -> String? {
        let sharedDefaults = UserDefaults(suiteName: appGroup)
        return sharedDefaults?.string(forKey: userIdKey)
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

    /// Stores user name in Keychain for persistence across app reinstalls
    private func storeUserNameInKeychain(_ name: String) {
        let data = Data(name.utf8)

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: userNameKeychainKey,
            kSecAttrAccessGroup as String: keychainAccessGroup,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: userNameKeychainKey,
            kSecAttrAccessGroup as String: keychainAccessGroup,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    /// Retrieves user name from Keychain
    func getUserNameFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: userNameKeychainKey,
            kSecAttrAccessGroup as String: keychainAccessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
            let data = result as? Data,
            let name = String(data: data, encoding: .utf8),
            !name.isEmpty
        else {
            return nil
        }

        return name
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension ShareExtensionSignInManager: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let identityTokenData = credential.identityToken,
            let identityToken = String(data: identityTokenData, encoding: .utf8)
        else {
            signInContinuation?.resume(throwing: ShareExtensionSignInError.invalidCredential)
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
                // Store in both UserDefaults (for extension) and Keychain (for persistence)
                sharedDefaults?.set(displayName, forKey: userNameKey)
                storeUserNameInKeychain(displayName)
            }
        }

        signInContinuation?.resume(returning: identityToken)
        signInContinuation = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        signInContinuation?.resume(throwing: error)
        signInContinuation = nil
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension ShareExtensionSignInManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Safe to force unwrap - we validate window exists in signIn() before reaching here
        return presentationAnchor!
    }
}

// MARK: - Errors

enum ShareExtensionSignInError: LocalizedError {
    case invalidCredential
    case noWindow

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Failed to get valid credentials from Apple."
        case .noWindow:
            return "Unable to present sign-in. Please try again."
        }
    }
}
