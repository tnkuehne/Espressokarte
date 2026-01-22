//
//  EspressokarteApp.swift
//  Espressokarte
//
//  Created by Timo Kuehne on 07.01.26.
//

import SwiftData
import SwiftUI

@main
struct EspressokarteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    let modelContainer: ModelContainer

    init() {
        // Create and configure the SwiftData container
        let container = SwiftDataCacheManager.createModelContainer()
        self.modelContainer = container

        // Configure the cache manager with the container
        SwiftDataCacheManager.shared.configure(with: container)
    }

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
        .modelContainer(modelContainer)
    }
}

/// App delegate for handling push notifications and CloudKit
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register for push notifications
        application.registerForRemoteNotifications()
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
