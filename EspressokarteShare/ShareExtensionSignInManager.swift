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

    private var keychainAccessGroup: String {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String
        else {
            fatalError("KeychainAccessGroup not found in Info.plist")
        }
        return group
    }

    private weak var presentationAnchor: UIWindow?
    private var signInContinuation: CheckedContinuation<String, Error>?

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

    func isSignedIn() -> Bool {
        return getKeychainValue(forKey: tokenKey) != nil && getKeychainValue(forKey: userIdKey) != nil
    }

    func getStoredToken() -> String? {
        return getKeychainValue(forKey: tokenKey)
    }

    func getUserName() -> String? {
        return getKeychainValue(forKey: userNameKey)
    }

    func getUserId() -> String? {
        return getKeychainValue(forKey: userIdKey)
    }

    // MARK: - Keychain Helpers

    private func setKeychainValue(_ value: String, forKey key: String) {
        let data = Data(value.utf8)

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: keychainAccessGroup,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: keychainAccessGroup,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: true,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func getKeychainValue(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: keychainAccessGroup,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
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
