//
//  EspressokarteApp.swift
//  Espressokarte
//
//  Created by Timo Kuehne on 07.01.26.
//

import SwiftUI

@main
struct EspressokarteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if hasSeenWelcome {
                MapView()
            } else {
                WelcomeView {
                    withAnimation {
                        hasSeenWelcome = true
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        Task { @MainActor in
            switch phase {
            case .active:
                // App became active - start processing any pending extractions
                BackgroundExtractionManager.shared.appDidBecomeActive()
            case .background:
                // App went to background - schedule background processing
                BackgroundExtractionManager.shared.appDidEnterBackground()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}

/// App delegate for handling push notifications, CloudKit, and background tasks
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register for push notifications
        application.registerForRemoteNotifications()

        // Register background task for price extraction
        BackgroundExtractionManager.shared.registerBackgroundTask()

        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Handle CloudKit notifications
        Task {
            await CloudKitManager.shared.handleNotification()
            completionHandler(.newData)
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Successfully registered for push notifications
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register for push notifications: \(error)")
    }
}
