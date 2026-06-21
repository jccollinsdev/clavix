import SwiftUI
import Supabase
import SafariServices
import Sentry

@main
struct ClavisApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var subscriptionManager = SubscriptionManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
                .environmentObject(subscriptionManager)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    Task { await subscriptionManager.refresh() }
                }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureCrashReporting()
        return true
    }

    private func configureCrashReporting() {
        guard let dsn = Bundle.main.infoDictionary?["SENTRY_DSN"] as? String else { return }
        let trimmed = dsn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return }

        SentrySDK.start { options in
            options.dsn = trimmed
            options.tracesSampleRate = 0.1
            options.profilesSampleRate = 0.0
            options.environment = "production"
            options.sendDefaultPii = false
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushNotificationManager.shared.handleRemoteNotificationRegistration(deviceToken, error: nil)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        PushNotificationManager.shared.handleRemoteNotificationRegistration(nil, error: error)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        completionHandler(.newData)
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["clavix", "clavis"].contains(scheme) else {
            return false
        }

        // Dismiss any presented SafariViewController (e.g. SnapTrade portal).
        if let rootController = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController,
           let safari = rootController.presentedViewController as? SFSafariViewController {
            safari.dismiss(animated: true)
        }

        // Supabase email confirmation / password-reset PKCE callback.
        // The URL looks like: clavix://auth/callback?code=<pkce_code>
        if url.host?.lowercased() == "auth" {
            print("[Auth] Received auth callback URL host=\(url.host ?? "") path=\(url.path)")
            NotificationCenter.default.post(name: .supabaseAuthCallbackReceived, object: url)
            return true
        }

        // SnapTrade brokerage connection callback.
        NotificationCenter.default.post(name: .snapTradeCallbackReceived, object: url)
        return true
    }
}
