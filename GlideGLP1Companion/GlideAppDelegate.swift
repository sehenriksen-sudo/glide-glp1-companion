// GlideAppDelegate.swift
//
// UIApplicationDelegate + UNUserNotificationCenterDelegate.
// Bridges UIKit notification callbacks into DeepLinkRouter.
//
// Wired in GlideApp via:
//   @UIApplicationDelegateAdaptor(GlideAppDelegate.self) var appDelegate

import UIKit
import UserNotifications

final class GlideAppDelegate: NSObject, UIApplicationDelegate {

    /// Injected by GlideApp immediately after the delegate is created.
    var router: DeepLinkRouter?

    // MARK: UIApplicationDelegate

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register this object as the notification delegate so
        // foreground notifications are shown AND taps are routed.
        UNUserNotificationCenter.current().delegate = self
        return true
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension GlideAppDelegate: UNUserNotificationCenterDelegate {

    /// Show notifications as banners even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Route taps and action-button presses to DeepLinkRouter.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            router?.handle(response: response)
        }
        completionHandler()
    }
}
