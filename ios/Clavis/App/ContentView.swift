import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var hasCheckedSession = false

    var body: some View {
        Group {
            #if DEBUG
            if hifiReferenceEnabled {
                ClavixHiFiReferenceView()
            } else if debugVisualQAEnabled {
                ClavixVisualQARoot(open: debugVisualQAOpen)
            } else if allowDebugBypassLiveEntry {
                MainTabView()
            } else {
                authRoot
            }
            #else
            authRoot
            #endif
        }
        .onAppear {
            guard !debugVisualQAEnabled else { return }
            guard !allowDebugBypassLiveEntry else {
                hasCheckedSession = true
                return
            }
            guard !hasCheckedSession else { return }
            hasCheckedSession = true

            Task {
                await authViewModel.checkSession()
            }
        }
        .onChange(of: authViewModel.isAuthenticated) { _, isAuth in
            if !isAuth {
                hasCheckedSession = false
            } else {
                Task { await subscriptionManager.refresh() }
                Task { await PushNotificationManager.shared.requestPermission() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .supabaseAuthCallbackReceived)) { notification in
            guard !debugVisualQAEnabled else { return }
            guard let url = notification.object as? URL else { return }
            Task { await authViewModel.handleAuthDeepLink(url: url) }
        }
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var authRoot: some View {
        if allowDebugBypassLiveEntry && authViewModel.isAuthenticated {
            MainTabView()
        } else if authViewModel.isLoadingPreferences && !hasCheckedSession {
            LoadingView()
        } else if authViewModel.isAuthenticated && authViewModel.isLoadingPreferences {
            LoadingView()
        } else if authViewModel.isAuthenticated {
            if authViewModel.hasCompletedOnboarding || allowDebugBypassLiveEntry {
                if shouldShowExpiredPaywall {
                    ExpiredPaywallView()
                } else {
                    MainTabView()
                }
            } else {
                OnboardingContainerView()
            }
        } else {
            LoginView()
        }
    }

    /// Loads the bundled Clavix Hi-Fi v2 HTML in WKWebView for pixel-level
    /// parity comparison during the design build. Enable with
    /// `CLAVIX_USE_HIFI_REFERENCE=1` in the Xcode scheme env vars.
    private var hifiReferenceEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["CLAVIX_USE_HIFI_REFERENCE"] == "1"
        #else
        false
        #endif
    }

    // Live tabs are now the default everywhere. The static VisualQA mock is
    // reachable in DEBUG only by explicitly setting CLAVIX_USE_VQA_MOCK=1.
    private var debugVisualQAEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["CLAVIX_USE_VQA_MOCK"] == "1"
        #else
        false
        #endif
    }

    private var debugVisualQAOpen: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["CLAVIX_DEBUG_OPEN"]
        #else
        nil
        #endif
    }

    private var allowDebugBypassLiveEntry: Bool {
        #if DEBUG
        SupabaseAuthService.shared.isUsingDebugBypass
        #else
        false
        #endif
    }

    private var shouldShowExpiredPaywall: Bool {
        switch subscriptionManager.status {
        case .notSubscribed, .expired:
            return true
        case .unknown, .trial, .active:
            return false
        }
    }
}

struct LoadingView: View {
    var body: some View {
        ZStack {
            Color.clavixPage.ignoresSafeArea()
            VStack(spacing: 24) {
                Image("clavix_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                ProgressView()
                    .tint(.clavixInk3)
            }
        }
    }
}
