import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = SettingsViewModel()
    @StateObject private var brokerageViewModel = BrokerageViewModel()
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let message = viewModel.preferencesMessage {
                        SettingsMessageCard(message: message, fill: .clavixWarnSoft, foreground: .clavixWarnInk)
                    }
                    if let message = viewModel.accountMessage {
                        SettingsMessageCard(message: message, fill: .clavixAccentSoft, foreground: .clavixAccentInk)
                    }

                    NavigationLink {
                        ProfileSettingsDetailView(viewModel: viewModel)
                    } label: {
                        SettingsSectionCard("PROFILE") {
                            SettingsValueRow("Name", value: profileDisplayName, detail: profileDetail)
                            Divider()
                            SettingsValueRow(
                                "Plan",
                                value: planSummary,
                                valueColor: isFreeTier ? .clavixInk3 : .clavixAccent
                            )
                        }
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        MorningReportSettingsDetailView(viewModel: viewModel)
                    } label: {
                        SettingsSectionCard("MORNING REPORT") {
                            SettingsValueRow("Delivery time", value: deliveryTimeValue)
                            Divider()
                            SettingsValueRow("Length", value: viewModel.summaryLength.rawValue)
                        }
                    }
                    .buttonStyle(.plain)

                    // Notifications — shown always; push is pending APNs enrollment
                    SettingsSectionCard("NOTIFICATIONS") {
                        SettingsValueRow(
                            "Push alerts",
                            value: "Coming soon",
                            detail: "Grade changes and major events will notify you once push notifications are enabled.",
                            valueColor: .clavixInk3
                        )
                        Divider()
                        NavigationLink {
                            NotificationPrefsDetailView(viewModel: viewModel)
                        } label: {
                            SettingsValueRow("Alert preferences", value: "Configure")
                        }
                        .buttonStyle(.plain)
                    }

                    // Brokerage — shown always; hidden behind coming-soon when not enabled
                    if FeatureFlags.brokerageEnabled {
                        NavigationLink {
                            BrokerageSettingsDetailView(viewModel: brokerageViewModel)
                        } label: {
                            SettingsSectionCard("BROKERAGE") {
                                SettingsValueRow(
                                    "Connected brokerage",
                                    value: brokerageStatusValue,
                                    detail: brokerageDetail,
                                    valueColor: brokerageViewModel.isConnected ? .clavixGood : .clavixInk3
                                )
                                Divider()
                                SettingsValueRow(
                                    "Auto-sync",
                                    value: brokerageViewModel.autoSyncEnabled ? "On" : "Off",
                                    valueColor: brokerageViewModel.autoSyncEnabled ? .clavixGood : .clavixInk3
                                )
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        SettingsSectionCard("BROKERAGE") {
                            SettingsValueRow(
                                "Brokerage sync",
                                value: "Coming later",
                                detail: "Read-only portfolio sync from your brokerage. Available in a future update.",
                                valueColor: .clavixInk3
                            )
                        }
                    }

                    NavigationLink {
                        ReferenceSettingsDetailView()
                    } label: {
                        SettingsSectionCard("REFERENCE") {
                            SettingsValueRow("Methodology", value: "Open")
                        }
                    }
                    .buttonStyle(.plain)

                    SettingsSectionCard("ACCOUNT") {
                        NavigationLink {
                            ExportDataDetailView(viewModel: viewModel)
                        } label: {
                            SettingsActionRow("Export data")
                        }
                        .buttonStyle(.plain)

                        Divider()

                        NavigationLink {
                            SupportLegalDetailView()
                        } label: {
                            SettingsActionRow("Support & legal")
                        }
                        .buttonStyle(.plain)

                        Divider()

                        Button {
                            Task { await authViewModel.signOut() }
                        } label: {
                            SettingsActionRow("Sign out")
                        }
                        .buttonStyle(.plain)

                        Divider()

                        NavigationLink {
                            DeleteAccountDetailView(viewModel: viewModel)
                                .environmentObject(authViewModel)
                        } label: {
                            SettingsActionRow("Delete account", foreground: .clavixBad)
                        }
                        .buttonStyle(.plain)
                    }

                    versionFooter
                }
                .padding(.horizontal, ClavixLayout.pad)
                .padding(.top, 8)
                .padding(.bottom, ClavixLayout.bottomPad)
            }
            .background(Color.clavixPage.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                ClavixStickyBar()
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                guard !hasLoaded else { return }
                hasLoaded = true
                await viewModel.load()
                await brokerageViewModel.loadStatus()
            }
            .sheet(
                isPresented: Binding(
                    get: { brokerageViewModel.presentedURL != nil },
                    set: { if !$0 { brokerageViewModel.presentedURL = nil } }
                )
            ) {
                if let url = brokerageViewModel.presentedURL {
                    SafariView(url: url)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .snapTradeCallbackReceived)) { notification in
                guard let url = notification.object as? URL else { return }
                Task { await brokerageViewModel.handleCallback(url: url) }
            }
        }
    }

    private var profileDisplayName: String {
        let trimmed = viewModel.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if viewModel.userEmail != "Unknown",
           let emailName = viewModel.userEmail.split(separator: "@").first,
           !emailName.isEmpty {
            return String(emailName)
        }
        return "Clavix member"
    }

    private var profileDetail: String? {
        viewModel.userEmail == "Unknown" ? "Email unavailable" : viewModel.userEmail
    }

    private var planSummary: String {
        switch subscriptionManager.status {
        case .trial(let expiresAt):
            return "TRIAL · \(expiresAt.formatted(date: .abbreviated, time: .omitted))"
        case .active:
            return "PRO"
        case .unknown:
            return "CHECKING"
        case .notSubscribed, .expired:
            return "INACTIVE"
        }
    }

    private var deliveryTimeValue: String {
        viewModel.digestTime.formatted(date: .omitted, time: .shortened)
    }

    private var brokerageStatusValue: String {
        brokerageViewModel.isConnected ? "Live" : "Not connected"
    }

    private var brokerageDetail: String? {
        guard brokerageViewModel.isConnected else { return nil }
        return brokerageViewModel.status?.lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "Last synced unavailable"
    }

    private var versionFooter: some View {
        Text(cleanVersionLabel)
            .font(ClavisTypography.clavixMono(10, weight: .regular))
            .tracking(0.6)
            .foregroundColor(.clavixInk4)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
    }

    private var cleanVersionLabel: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "CLAVIX · VERSION \(short)"
    }

    private var isFreeTier: Bool { false }

}

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ClavixEyebrow(title)
            ClavixCard(padding: 0) {
                VStack(spacing: 0) {
                    content
                }
            }
        }
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String
    var detail: String? = nil
    var valueColor: Color = .clavixInk3

    init(_ title: String, value: String, detail: String? = nil, valueColor: Color = .clavixInk3) {
        self.title = title
        self.value = value
        self.detail = detail
        self.valueColor = valueColor
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ClavisTypography.bodyEmphasis)
                    .foregroundColor(.clavixInk)
                if let detail {
                    Text(detail)
                        .font(ClavisTypography.clavixCaption)
                        .foregroundColor(.clavixInk3)
                }
            }
            Spacer()
            if !value.isEmpty {
                Text(value)
                    .font(ClavisTypography.clavixMono(12, weight: .regular))
                    .foregroundColor(valueColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct SettingsActionRow: View {
    let title: String
    var foreground: Color = .clavixInk

    init(_ title: String, foreground: Color = .clavixInk) {
        self.title = title
        self.foreground = foreground
    }

    var body: some View {
        HStack {
            Text(title)
                .font(ClavisTypography.bodyEmphasis)
                .foregroundColor(foreground)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct SettingsMessageCard: View {
    let message: String
    let fill: Color
    let foreground: Color

    var body: some View {
        ClavixCard(fill: fill) {
            Text(message)
                .font(ClavisTypography.clavixCaption)
                .foregroundColor(foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsInputField: View {
    let title: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ClavixEyebrow(title)
            TextField(title, text: $text, prompt: Text(title).foregroundColor(.clavixInk3))
                .font(ClavisTypography.clavixMono(14, weight: .regular))
                .foregroundColor(.clavixInk)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(Color.clavixPaper)
                .overlay(
                    RoundedRectangle(cornerRadius: ClavixLayout.cardRadius)
                        .stroke(Color.clavixRule, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.cardRadius, style: .continuous))
                .keyboardType(keyboard)
        }
    }
}

private struct SettingsToggleButtonRow: View {
    let title: String
    @Binding var isOn: Bool
    let save: () async -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(ClavisTypography.bodyEmphasis)
                .foregroundColor(.clavixInk)
            Spacer()
            Button {
                isOn.toggle()
                Task { await save() }
            } label: {
                CX2Toggle(isOn: $isOn)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct SettingsDismissButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(action: { dismiss() }) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.clavixInk)
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileSettingsDetailView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var editorField: ProfileEditorField?

    var body: some View {
        ClavixScreen(eyebrow: "Profile", title: "Account", trailing: AnyView(SettingsDismissButton())) {
            if let message = viewModel.accountMessage {
                SettingsMessageCard(message: message, fill: .clavixAccentSoft, foreground: .clavixAccentInk)
            }

            ClavixCard(fill: .clavixPaper) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName)
                            .font(ClavisTypography.clavixSerif(24, weight: .medium))
                            .foregroundColor(.clavixInk)
                        Text(emailLine)
                            .font(ClavisTypography.clavixCaption)
                            .foregroundColor(.clavixInk3)
                    }
                    Spacer()
                    Text(viewModel.subscriptionTier == "free" ? "FREE" : viewModel.subscriptionTier.uppercased())
                        .font(ClavisTypography.clavixMono(10, weight: .bold))
                        .tracking(0.4)
                        .foregroundColor(viewModel.subscriptionTier == "free" ? .clavixInk3 : .clavixAccentInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(viewModel.subscriptionTier == "free" ? Color.clavixPaper2 : Color.clavixAccentSoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.clavixRule, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }

            SettingsSectionCard("DETAILS") {
                VStack(spacing: 0) {
                    Button {
                        editorField = .displayName
                    } label: {
                        SettingsValueRow("Display name", value: displayName)
                    }
                    .buttonStyle(.plain)

                    Divider()

                    Button {
                        editorField = .birthYear
                    } label: {
                        SettingsValueRow("Birth year", value: birthYearValue)
                    }
                    .buttonStyle(.plain)

                    Divider()

                    SettingsValueRow(
                        "Region",
                        value: "Unavailable",
                        detail: "Waiting on backend support."
                    )
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editorField) { field in
            ProfileFieldEditorSheet(
                field: field,
                initialValue: field == .displayName ? viewModel.userName : viewModel.birthYear.map(String.init) ?? ""
            ) { newValue in
                switch field {
                case .displayName:
                    await viewModel.saveProfile(name: newValue, birthYear: viewModel.birthYear)
                case .birthYear:
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    await viewModel.saveProfile(
                        name: viewModel.userName,
                        birthYear: trimmed.isEmpty ? nil : Int(trimmed)
                    )
                }
            }
        }
    }

    private var displayName: String {
        let trimmed = viewModel.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Clavix member" : trimmed
    }

    private var birthYearValue: String {
        viewModel.birthYear.map(String.init) ?? "—"
    }

    private var emailLine: String {
        viewModel.userEmail == "Unknown" ? "Email unavailable" : viewModel.userEmail
    }
}

private struct MorningReportSettingsDetailView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showUpgradeSheet = false

    var body: some View {
        ClavixScreen(eyebrow: "Morning Report", title: "Delivery", trailing: AnyView(SettingsDismissButton())) {
            if let message = viewModel.preferencesMessage {
                SettingsMessageCard(message: message, fill: .clavixWarnSoft, foreground: .clavixWarnInk)
            }

            SettingsSectionCard("DELIVERY") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Delivery time")
                            .font(ClavisTypography.bodyEmphasis)
                            .foregroundColor(.clavixInk)
                        Spacer()
                        DatePicker("Delivery time", selection: $viewModel.digestTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .tint(.clavixAccent)
                            .onChange(of: viewModel.digestTime, initial: false) { _, _ in
                                Task { await viewModel.saveDigestTime() }
                            }
                    }

                    Rectangle()
                        .fill(Color.clavixRule)
                        .frame(height: 1)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Length")
                            .font(ClavisTypography.bodyEmphasis)
                            .foregroundColor(.clavixInk)
                        HStack(spacing: 8) {
                            ForEach(SummaryLength.allCases, id: \.rawValue) { option in
                                Button {
                                    selectDigestLength(option)
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(option.rawValue)
                                        if option == .verbose {
                                            Text("Pro")
                                                .font(ClavisTypography.clavixMono(9, weight: .bold))
                                        }
                                    }
                                    .font(ClavisTypography.clavixMono(10, weight: .bold))
                                    .tracking(0.4)
                                    .foregroundColor(viewModel.summaryLength == option ? .clavixPaper : .clavixInk2)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(viewModel.summaryLength == option ? Color.clavixInk : Color.clavixPaper2)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.clavixRule, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Rectangle()
                        .fill(Color.clavixRule)
                        .frame(height: 1)

                    NavigationLink {
                        NotificationPrefsDetailView(viewModel: viewModel)
                    } label: {
                        SettingsValueRow("Notifications", value: "Open")
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showUpgradeSheet) {
            PaywallView(triggerContext: .verboseDigest)
                .environmentObject(SubscriptionManager.shared)
        }
    }

    private func selectDigestLength(_ option: SummaryLength) {
        if option == .verbose && !SubscriptionManager.shared.isPro {
            showUpgradeSheet = true
            return
        }
        viewModel.summaryLength = option
        Task { await viewModel.saveSummaryLength() }
    }
}

private struct NotificationPrefsDetailView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showQuietHoursEditor = false

    var body: some View {
        ClavixScreen(eyebrow: "Alerts", title: "Notifications", trailing: AnyView(SettingsDismissButton())) {
            if let message = viewModel.preferencesMessage {
                SettingsMessageCard(message: message, fill: .clavixWarnSoft, foreground: .clavixWarnInk)
            }

            ClavixInlineNoticeCard(
                eyebrow: "Push delivery",
                title: "Push notifications not yet active",
                message: "Alert preferences are saved and will apply once push notifications are enabled. In-app alerts in the Alerts tab are active now.",
                footnote: "Clavix alerts you about grade changes, major news, and portfolio risk signals affecting your held positions.",
                glyph: "bell.badge"
            )

            SettingsSectionCard("DELIVERY") {
                VStack(spacing: 0) {
                    Button {
                        viewModel.notificationsEnabled.toggle()
                        Task { await viewModel.saveNotifications() }
                    } label: {
                        SettingsValueRow("Morning Report", value: onOffValue(viewModel.notificationsEnabled))
                    }
                    .buttonStyle(.plain)

                    Divider()

                    Button {
                        showQuietHoursEditor = true
                    } label: {
                        SettingsValueRow("Quiet hours", value: quietHoursValue, detail: quietHoursDetail)
                    }
                    .buttonStyle(.plain)
                }
            }

            SettingsSectionCard("RULES") {
                VStack(spacing: 0) {
                    Button {
                        viewModel.alertsGradeChanges.toggle()
                        Task { await viewModel.saveAlertSettings() }
                    } label: {
                        SettingsValueRow("Grade changes", value: onOffValue(viewModel.alertsGradeChanges))
                    }
                    .buttonStyle(.plain)

                    Divider()

                    Button {
                        viewModel.alertsMajorEvents.toggle()
                        Task { await viewModel.saveAlertSettings() }
                    } label: {
                        SettingsValueRow("Major news", value: onOffValue(viewModel.alertsMajorEvents))
                    }
                    .buttonStyle(.plain)

                    Divider()

                    Button {
                        viewModel.alertsPortfolioRisk.toggle()
                        Task { await viewModel.saveAlertSettings() }
                    } label: {
                        SettingsValueRow("Portfolio grade", value: onOffValue(viewModel.alertsPortfolioRisk))
                    }
                    .buttonStyle(.plain)

                    Divider()

                    SettingsValueRow(
                        "Macro shock",
                        value: "Coming soon",
                        detail: "Waiting on backend delivery rules."
                    )
                    Divider()
                    SettingsValueRow(
                        "Tracked ticker alerts",
                        value: "Coming soon",
                        detail: "Waiting on tracked-alert preferences."
                    )
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showQuietHoursEditor) {
            QuietHoursEditorSheet(viewModel: viewModel)
        }
    }

    private var quietHoursValue: String {
        guard viewModel.quietHoursEnabled else { return "Off" }
        return "\(timeString(viewModel.quietHoursStart))-\(timeString(viewModel.quietHoursEnd))"
    }

    private var quietHoursDetail: String? {
        viewModel.quietHoursEnabled ? "Delivered after quiet hours end." : nil
    }

    private func onOffValue(_ isOn: Bool) -> String {
        isOn ? "On" : "Off"
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter.string(from: date).lowercased()
    }
}

private enum ProfileEditorField: String, Identifiable {
    case displayName
    case birthYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .displayName:
            return "Display name"
        case .birthYear:
            return "Birth year"
        }
    }

    var keyboard: UIKeyboardType {
        switch self {
        case .displayName:
            return .default
        case .birthYear:
            return .numberPad
        }
    }
}

private struct ProfileFieldEditorSheet: View {
    let field: ProfileEditorField
    let initialValue: String
    let onSave: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftValue = ""

    var body: some View {
        NavigationStack {
            ClavixScreen(
                eyebrow: "Profile",
                title: field.title,
                trailing: AnyView(sheetDismissButton)
            ) {
                SettingsInputField(title: field.title, text: $draftValue, keyboard: field.keyboard)

                ClavisPrimaryButton(title: "Save") {
                    Task {
                        await onSave(draftValue)
                        dismiss()
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                draftValue = initialValue
            }
        }
    }

    private var sheetDismissButton: some View {
        Button("Close") { dismiss() }
            .font(ClavisTypography.clavixMono(10, weight: .semibold))
            .foregroundColor(.clavixAccent)
            .buttonStyle(.plain)
    }
}

private struct QuietHoursEditorSheet: View {
    @ObservedObject var viewModel: SettingsViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var quietHoursEnabled = false
    @State private var quietHoursStart = Date()
    @State private var quietHoursEnd = Date()

    var body: some View {
        NavigationStack {
            ClavixScreen(
                eyebrow: "Alerts",
                title: "Quiet hours",
                trailing: AnyView(sheetDismissButton)
            ) {
                SettingsSectionCard("DELIVERY") {
                    VStack(spacing: 0) {
                        SettingsToggleButtonRow(title: "Quiet hours", isOn: $quietHoursEnabled) {}

                        if quietHoursEnabled {
                            Divider()

                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Start")
                                        .font(ClavisTypography.bodyEmphasis)
                                        .foregroundColor(.clavixInk)
                                    Spacer()
                                    DatePicker("Start", selection: $quietHoursStart, displayedComponents: .hourAndMinute)
                                        .labelsHidden()
                                        .tint(.clavixAccent)
                                }

                                HStack {
                                    Text("End")
                                        .font(ClavisTypography.bodyEmphasis)
                                        .foregroundColor(.clavixInk)
                                    Spacer()
                                    DatePicker("End", selection: $quietHoursEnd, displayedComponents: .hourAndMinute)
                                        .labelsHidden()
                                        .tint(.clavixAccent)
                                }
                            }
                            .padding(16)
                        }
                    }
                }

                ClavisPrimaryButton(title: "Save quiet hours") {
                    Task {
                        viewModel.quietHoursEnabled = quietHoursEnabled
                        viewModel.quietHoursStart = quietHoursStart
                        viewModel.quietHoursEnd = quietHoursEnd
                        await viewModel.saveAlertSettings()
                        dismiss()
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                quietHoursEnabled = viewModel.quietHoursEnabled
                quietHoursStart = viewModel.quietHoursStart
                quietHoursEnd = viewModel.quietHoursEnd
            }
        }
    }

    private var sheetDismissButton: some View {
        Button("Close") { dismiss() }
            .font(ClavisTypography.clavixMono(10, weight: .semibold))
            .foregroundColor(.clavixAccent)
            .buttonStyle(.plain)
    }
}

private struct BrokerageSettingsDetailView: View {
    @ObservedObject var viewModel: BrokerageViewModel

    var body: some View {
        ClavixScreen(eyebrow: "Brokerage", title: "Connection", trailing: AnyView(SettingsDismissButton())) {
            if let message = viewModel.errorMessage {
                SettingsMessageCard(message: message, fill: .clavixBadSoft, foreground: .clavixBadInk)
            }
            if let message = viewModel.infoMessage {
                SettingsMessageCard(message: message, fill: .clavixAccentSoft, foreground: .clavixAccentInk)
            }

            SettingsSectionCard("BROKERAGE") {
                VStack(spacing: 0) {
                    SettingsValueRow(
                        "Status",
                        value: viewModel.isConnected ? "Live" : "Not connected",
                        valueColor: viewModel.isConnected ? .clavixGood : .clavixInk3
                    )
                    Divider()
                    SettingsValueRow(
                        "Auto-sync",
                        value: viewModel.autoSyncEnabled ? "On" : "Off",
                        valueColor: viewModel.autoSyncEnabled ? .clavixGood : .clavixInk3
                    )
                    Divider()
                    SettingsValueRow(
                        "Last synced",
                        value: viewModel.status?.lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
                    )
                    if viewModel.isConnected {
                        Divider()
                        SettingsToggleButtonRow(
                            title: "Automatic updates",
                            isOn: Binding(
                                get: { viewModel.autoSyncEnabled },
                                set: { _ in }
                            )
                        ) {
                            await viewModel.setAutoSyncEnabled(!viewModel.autoSyncEnabled)
                        }
                    }
                }
            }

            ClavixCard(fill: .clavixPaper) {
                VStack(alignment: .leading, spacing: 10) {
                    if viewModel.isConnected {
                        ClavisPrimaryButton(title: viewModel.isSyncing ? "Syncing holdings…" : "Sync holdings now") {
                            Task { await viewModel.syncNow(refreshRemote: true) }
                        }
                        Button(viewModel.isDisconnecting ? "Disconnecting…" : "Disconnect brokerage") {
                            Task { await viewModel.disconnect() }
                        }
                        .font(ClavisTypography.clavixMono(11, weight: .semibold))
                        .foregroundColor(.clavixBad)
                        .buttonStyle(.plain)
                    } else {
                        ClavisPrimaryButton(title: "Connect brokerage") {
                            Task { await viewModel.startConnect() }
                        }
                        Text("If brokerage access is unavailable, you can still add holdings manually.")
                            .font(ClavisTypography.clavixCaption)
                            .foregroundColor(.clavixInk3)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct ReferenceSettingsDetailView: View {
    var body: some View {
        ClavixScreen(eyebrow: "Reference", title: "Methodology", trailing: AnyView(SettingsDismissButton())) {
            SettingsSectionCard("REFERENCE") {
                VStack(spacing: 0) {
                    NavigationLink(destination: MethodologyView()) {
                        SettingsValueRow("Data sources & methodology", value: "Open")
                    }
                    .buttonStyle(.plain)
                    Divider()
                    NavigationLink(destination: ScoreExplanationView()) {
                        SettingsValueRow("Score explanation", value: "Open")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct ExportDataDetailView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ClavixScreen(eyebrow: "Privacy", title: "Export data", trailing: AnyView(SettingsDismissButton())) {
            Text("Download a copy of your positions, preferences, alerts, and report history.")
                .font(ClavisTypography.clavixSerif(18, weight: .regular))
                .foregroundColor(.clavixInk2)

            SettingsSectionCard("EXPORT INCLUDES") {
                VStack(spacing: 0) {
                    SettingsValueRow("Positions", value: "CSV")
                    Divider()
                    SettingsValueRow("Alerts", value: "JSON")
                    Divider()
                    SettingsValueRow("Reports", value: "JSON")
                }
            }

            if let message = viewModel.accountMessage {
                SettingsMessageCard(message: message, fill: .clavixAccentSoft, foreground: .clavixAccentInk)
            }

            ClavisPrimaryButton(title: viewModel.isExportingAccount ? "Preparing export…" : "Prepare export") {
                Task { await viewModel.exportAccount() }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct SupportLegalDetailView: View {
    var body: some View {
        ClavixScreen(eyebrow: "Reference", title: "Support & legal", trailing: AnyView(SettingsDismissButton())) {
            SettingsSectionCard("SUPPORT") {
                VStack(spacing: 0) {
                    Link(destination: URL(string: "mailto:support@getclavix.com")!) {
                        SettingsValueRow("Email", value: "support")
                    }
                    .buttonStyle(.plain)
                    Divider()
                    SettingsValueRow("Status", value: "Online", valueColor: .clavixGood)
                }
            }

            SettingsSectionCard("LEGAL") {
                VStack(spacing: 0) {
                    SettingsValueRow("Operator", value: "Andover Digital LLC")
                    Divider()
                    SettingsValueRow("App Store by", value: "Individual Developer Account")
                    Divider()
                    Link(destination: URL(string: "https://getclavix.com/terms")!) {
                        SettingsValueRow("Terms", value: "Open")
                    }
                    .buttonStyle(.plain)
                    Divider()
                    Link(destination: URL(string: "https://getclavix.com/privacy")!) {
                        SettingsValueRow("Privacy", value: "Open")
                    }
                    .buttonStyle(.plain)
                    Divider()
                    NavigationLink(destination: MethodologyView()) {
                        SettingsValueRow("Methodology", value: "Open")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct DeleteAccountDetailView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showDeleteConfirmation = false

    var body: some View {
        ClavixScreen(eyebrow: "Danger zone", title: "Delete account", trailing: AnyView(SettingsDismissButton())) {
            ClavixCard(fill: .clavixBadSoft) {
                Text("This permanently removes your account, positions, preferences, device tokens, and report history.")
                    .font(ClavisTypography.clavixCaption)
                    .foregroundColor(.clavixBadInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = viewModel.accountMessage {
                SettingsMessageCard(message: message, fill: .clavixAccentSoft, foreground: .clavixAccentInk)
            }

            ClavisPrimaryButton(title: viewModel.isDeletingAccount ? "Deleting account…" : "Delete account") {
                showDeleteConfirmation = true
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Delete your account?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    if await viewModel.deleteAccount() {
                        await authViewModel.signOut()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your data and account.")
        }
    }
}

struct SettingsUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ClavisTheme.sectionSpacing) {
                    ClavixCard(fill: .clavixPaper) {
                        VStack(alignment: .leading, spacing: ClavisTheme.mediumSpacing) {
                            Text("Upgrade to Pro")
                                .font(ClavisTypography.h2)
                                .foregroundColor(.clavixInk)
                            Text("Unlimited holdings & watchlist, verbose morning briefing, 90-day score history across all 5 dimensions, and advanced alerts.")
                                .font(ClavisTypography.body)
                                .foregroundColor(.clavixInk3)
                                .fixedSize(horizontal: false, vertical: true)
                            ClavisPrimaryButton(title: "Clavix Pro: coming soon", action: { dismiss() })
                        }
                    }
                }
                .padding(.horizontal, ClavisTheme.screenPadding)
                .padding(.vertical, ClavisTheme.sectionSpacing)
            }
            .background(Color.clavixPage.ignoresSafeArea())
            .navigationTitle("Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.clavixInk3)
                }
            }
        }
    }
}

struct ScoreExplanationView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClavisTheme.largeSpacing) {
                VStack(alignment: .leading, spacing: ClavisTheme.smallSpacing) {
                    Text("How Risk Scores Work")
                        .font(ClavisTypography.sectionTitle)
                        .foregroundColor(.clavixInk)

                    Text("Scores range from 0 to 100, where 100 represents minimum risk and 0 represents extreme risk.")
                        .font(ClavisTypography.body)
                        .foregroundColor(.clavixInk3)
                }

                VStack(alignment: .leading, spacing: ClavisTheme.mediumSpacing) {
                    ScoreBandRow(grade: "A+", range: "90–100", description: "Exceptional, minimum risk", color: .gradeCAAA)
                    ScoreBandRow(grade: "A", range: "85–89", description: "Excellent, very low risk", color: .gradeCAA)
                    ScoreBandRow(grade: "A-", range: "80–84", description: "Very strong, low risk", color: .gradeCA)
                    ScoreBandRow(grade: "B+", range: "75–79", description: "Strong, low risk", color: .gradeCA)
                    ScoreBandRow(grade: "B", range: "70–74", description: "Solid, moderate-low risk", color: .gradeCA)
                    ScoreBandRow(grade: "B-", range: "65–69", description: "Above average, moderate risk", color: .gradeCBBB)
                    ScoreBandRow(grade: "C+", range: "60–64", description: "Average, moderate risk", color: .gradeCBBB)
                    ScoreBandRow(grade: "C", range: "55–59", description: "Below average, elevated risk", color: .gradeCBB)
                    ScoreBandRow(grade: "C-", range: "50–54", description: "Watch, elevated risk", color: .gradeCBB)
                    ScoreBandRow(grade: "D+", range: "45–49", description: "Elevated risk, high risk", color: .gradeCCCC)
                    ScoreBandRow(grade: "D", range: "40–44", description: "High risk, very high risk", color: .gradeCCC)
                    ScoreBandRow(grade: "D-", range: "35–39", description: "Severe risk, extreme risk", color: .gradeCC)
                    ScoreBandRow(grade: "F", range: "0–34", description: "Distressed, critical risk", color: .gradeCF)
                }
            }
            .padding(.horizontal, ClavisTheme.screenPadding)
            .padding(.vertical, ClavisTheme.largeSpacing)
        }
        .background(Color.clavixPage.ignoresSafeArea())
        .navigationTitle("Score Explanation")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ScoreBandRow: View {
    let grade: String
    let range: String
    let description: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: ClavisTheme.mediumSpacing) {
            GradeBadge(grade: grade)
            VStack(alignment: .leading, spacing: 2) {
                Text(range)
                    .font(ClavisTypography.bodyEmphasis)
                    .foregroundColor(color)
                Text(description)
                    .font(ClavisTypography.footnote)
                    .foregroundColor(.clavixInk3)
            }
            Spacer()
        }
        .padding(ClavisTheme.cardPadding)
        .clavisSecondaryCardStyle(fill: .clavixPaper2)
    }
}

struct MethodologyView: View {
    @Environment(\.dismiss) private var dismiss

    /// When opened from the Morning Report we pass the live composite so the
    /// grade scale highlights the reader's current band. From Settings it stays
    /// nil and the page reads as a universal reference.
    var currentScore: Double? = nil

    // The grade ladder, in order best to worst. Band names and score ranges are
    // pulled from ClavisGradeStyle.gradeBandLabel so the scale shown here IS the
    // exact scale the app grades by (no second copy to drift out of sync).
    private let ladder = ["A+", "A", "A-", "B+", "B", "B-", "C+", "C", "C-", "D+", "D", "D-", "F"]

    private let dimensions: [(code: String, name: String, detail: String, source: String)] = [
        ("FIN", "Financial Health",
         "Balance-sheet and cash-flow strength: debt-to-equity, free-cash-flow margin, current ratio, and the direction of revenue and profitability.",
         "Company fundamentals"),
        ("NEWS", "News Signal",
         "The balance and freshness of coverage. Recent, higher-quality sources count for more: the last 24 hours is weighted three times as heavily as week-old news.",
         "Live news feed"),
        ("MAC", "Macro Exposure",
         "Sensitivity to broad forces: 10-year Treasury yields, the U.S. dollar, crude oil, the VIX, and the S&P 500.",
         "FRED + market data"),
        ("SEC", "Sector Exposure",
         "Vulnerability to the sector's own state: sector beta, momentum versus the S&P 500, breadth, and sector-specific news.",
         "Sector data"),
        ("VOL", "Volatility",
         "Price instability and its direction: 30 and 90-day realized volatility, drawdown from the trailing-year high, and beta to the market.",
         "Price history")
    ]

    private var currentBand: String? {
        guard let currentScore else { return nil }
        return PortfolioMath.grade(forScore: currentScore)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("How grading works")
                    .font(ClavisTypography.clavixSerif(28, weight: .medium))
                    .tracking(-0.5)
                    .foregroundColor(.clavixInk)
                    .padding(.top, 4)
                leadCard
                gradeScaleSection
                dimensionsSection
                compositeSection
                freshnessCard
            }
            .padding(.horizontal, ClavixLayout.pad)
            .padding(.top, 8)
            .padding(.bottom, ClavixLayout.bottomPad)
        }
        .background(Color.clavixPage.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            ClavixReportBar(onBack: { dismiss() })
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Lead

    private var leadCard: some View {
        ClavixCard(fill: .clavixPaper2) {
            Text("Every holding earns a score from 0 to 100. Higher means stronger and lower risk. That score becomes a letter grade, and your holdings roll up into one portfolio grade, weighted by how much you own of each.")
                .font(ClavisTypography.clavixSerif(17, weight: .regular))
                .foregroundColor(.clavixInk)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - I. Grade scale

    private var gradeScaleSection: some View {
        MethodologySection(numeral: "I", title: "The grade scale",
                           caption: "Thirteen steps from A+ to F. A higher score is a stronger, lower-risk position.") {
            VStack(spacing: 0) {
                ForEach(Array(ladder.enumerated()), id: \.element) { index, grade in
                    gradeScaleRow(grade)
                    if index < ladder.count - 1 {
                        Rectangle().fill(Color.clavixRule).frame(height: 1)
                    }
                }
            }
            .background(Color.clavixPaper)
            .overlay(RoundedRectangle(cornerRadius: ClavixLayout.cardRadius).stroke(Color.clavixRule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.cardRadius))
        }
    }

    private func gradeScaleRow(_ grade: String) -> some View {
        let color = ClavisGradeStyle.riskColor(for: grade)
        let isCurrent = grade == currentBand
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4, height: 24)
            Text(grade)
                .font(ClavisTypography.clavixMono(15, weight: .bold))
                .foregroundColor(color)
                .frame(width: 32, alignment: .leading)
            Text(bandName(grade))
                .font(ClavisTypography.inter(14, weight: isCurrent ? .bold : .medium))
                .foregroundColor(.clavixInk)
            Spacer(minLength: 8)
            if isCurrent {
                Text("YOU")
                    .font(ClavisTypography.clavixMono(8, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(.clavixPaper)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Text(bandRange(grade))
                .font(ClavisTypography.clavixMono(12, weight: .regular))
                .foregroundColor(.clavixInk3)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(isCurrent ? color.opacity(0.10) : Color.clear)
    }

    // MARK: - II. Dimensions

    private var dimensionsSection: some View {
        MethodologySection(numeral: "II", title: "The five dimensions",
                           caption: "A holding's score is the average of five inputs, each weighted equally at 20%.") {
            VStack(spacing: 10) {
                ForEach(dimensions, id: \.code) { dim in
                    dimensionRow(dim)
                }
            }
        }
    }

    private func dimensionRow(_ dim: (code: String, name: String, detail: String, source: String)) -> some View {
        ClavixCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(dim.code)
                        .font(ClavisTypography.clavixMono(10, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(.clavixAccentInk)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.clavixAccentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(dim.name)
                        .font(ClavisTypography.clavixSerif(17, weight: .medium))
                        .foregroundColor(.clavixInk)
                    Spacer(minLength: 8)
                    Text("20%")
                        .font(ClavisTypography.clavixMono(11, weight: .semibold))
                        .foregroundColor(.clavixInk3)
                }
                Text(dim.detail)
                    .font(ClavisTypography.inter(13, weight: .regular))
                    .foregroundColor(.clavixInk2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(dim.source.uppercased())
                    .font(ClavisTypography.clavixMono(9, weight: .regular))
                    .tracking(0.5)
                    .foregroundColor(.clavixInk4)
            }
        }
    }

    // MARK: - III. Composite

    private var compositeSection: some View {
        MethodologySection(numeral: "III", title: "From holdings to your grade") {
            ClavixCard {
                VStack(alignment: .leading, spacing: 14) {
                    compositeStep("1", "Score each holding",
                                  "The five dimensions are averaged into one 0 to 100 score, then mapped to a letter using the scale above.")
                    Rectangle().fill(Color.clavixRule).frame(height: 1)
                    compositeStep("2", "Weight by position size",
                                  "Each holding counts in proportion to its market value, so your largest positions move the needle most.")
                    Rectangle().fill(Color.clavixRule).frame(height: 1)
                    compositeStep("3", "Roll up to one grade",
                                  "The value-weighted average of every holding becomes your portfolio score and grade.")
                    Text("portfolio = Σ(value × score) ÷ Σ(value)")
                        .font(ClavisTypography.clavixMono(11, weight: .medium))
                        .foregroundColor(.clavixInk3)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.clavixPaper2)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private func compositeStep(_ number: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(ClavisTypography.clavixMono(13, weight: .bold))
                .foregroundColor(.clavixAccentInk)
                .frame(width: 16, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ClavisTypography.inter(14, weight: .semibold))
                    .foregroundColor(.clavixInk)
                Text(body)
                    .font(ClavisTypography.inter(13, weight: .regular))
                    .foregroundColor(.clavixInk2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Freshness

    private var freshnessCard: some View {
        ClavixCard(padding: 14, fill: .clavixPaper2) {
            VStack(alignment: .leading, spacing: 6) {
                ClavixEyebrow("Freshness")
                Text("Scores recompute every night on fresh data, usually within a few hours of the market close. Grades hold steady over weekends and holidays while markets are shut.")
                    .font(ClavisTypography.inter(12, weight: .regular))
                    .foregroundColor(.clavixInk3)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Helpers (single source: ClavisGradeStyle.gradeBandLabel)

    /// "Average (60-64)" -> "Average"
    private func bandName(_ grade: String) -> String {
        let label = ClavisGradeStyle.gradeBandLabel(for: grade)
        guard let open = label.firstIndex(of: "(") else { return label }
        return String(label[..<open]).trimmingCharacters(in: .whitespaces)
    }

    /// "Average (60-64)" -> "60-64"
    private func bandRange(_ grade: String) -> String {
        let label = ClavisGradeStyle.gradeBandLabel(for: grade)
        guard let open = label.firstIndex(of: "("), let close = label.firstIndex(of: ")") else { return "" }
        return String(label[label.index(after: open)..<close])
    }
}

/// Numeral + serif title + optional caption, the editorial section header used
/// down the methodology page.
private struct MethodologySection<Content: View>: View {
    let numeral: String
    let title: String
    var caption: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(numeral)
                    .font(ClavisTypography.clavixMono(12, weight: .bold))
                    .foregroundColor(.clavixInk4)
                Text(title)
                    .font(ClavisTypography.clavixSerif(22, weight: .medium))
                    .tracking(-0.3)
                    .foregroundColor(.clavixInk)
            }
            if let caption {
                Text(caption)
                    .font(ClavisTypography.clavixCaption)
                    .foregroundColor(.clavixInk3)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .padding(.top, 6)
    }
}
