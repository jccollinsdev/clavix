import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var mode: AuthMode = .welcome
    @FocusState private var focusedField: Field?

    private enum AuthMode {
        case welcome
        case signIn
        case signUp
        case forgotPassword
    }

    enum Field: Hashable {
        case email
        case password
    }

    private var requiresPassword: Bool {
        switch mode {
        case .signIn, .signUp:
            return true
        case .welcome, .forgotPassword:
            return false
        }
    }

    private var isFormValid: Bool {
        let hasEmail = !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if requiresPassword {
            return hasEmail && !password.isEmpty
        }
        return hasEmail
    }

    private var authFieldText: Color { Color.white.opacity(0.96) }
    private var authFieldPrompt: Color { Color.white.opacity(0.52) }
    private var authFieldFill: Color { Color.white.opacity(0.07) }
    private var authFieldBorder: Color { Color.white.opacity(0.18) }
    private var authSecondaryText: Color { Color.white.opacity(0.72) }
    private var authTertiaryText: Color { Color.white.opacity(0.56) }
    private var authDividerTone: Color { Color.white.opacity(0.12) }
    private var authLinkTone: Color { Color.white.opacity(0.82) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                switch mode {
                case .welcome:
                    welcomeSurface
                case .signIn, .signUp, .forgotPassword:
                    formSurface
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .preferredColorScheme(.dark)
    }

    private var welcomeSurface: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 32)

                Text("Daily portfolio risk intelligence")
                    .font(ClavisTypography.mono(11))
                    .foregroundColor(.textSecondary)
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)

                Text("Portfolio risk,\nmeasured.")
                    .font(ClavisTypography.inter(34, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                Text("Every morning, Clavix scores your positions across five risk dimensions: macro, sector, financials, news, and volatility. The reasoning is always shown.")
                    .font(ClavisTypography.inter(15, weight: .regular))
                    .foregroundColor(authSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                WelcomeFeatureCarousel()
                    .padding(.bottom, 24)

                VStack(spacing: 10) {
                    AuthActionButton(
                        title: "Create account",
                        fill: .textPrimary,
                        foreground: .backgroundPrimary
                    ) {
                        mode = .signUp
                        focusedField = .email
                    }

                    AuthActionButton(
                        title: "Sign in",
                        fill: .surface,
                        foreground: .textPrimary,
                        bordered: true
                    ) {
                        mode = .signIn
                        focusedField = .email
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

                termsFooter
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            AuthStickyBar()
        }
    }

    private var formSurface: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Prominent back button
                    if mode != .forgotPassword {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { mode = .welcome }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Back")
                                    .font(ClavisTypography.inter(15, weight: .medium))
                            }
                            .foregroundColor(.textPrimary)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 20)
                        .padding(.bottom, 16)
                    }

                    Text(formTitle)
                        .font(ClavisTypography.inter(30, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .padding(.bottom, 8)

                    if let subtitle = formSubtitle {
                        Text(subtitle)
                            .font(ClavisTypography.inter(15, weight: .regular))
                            .foregroundColor(authSecondaryText)
                            .padding(.bottom, 28)
                    } else {
                        Spacer(minLength: 28)
                    }

                    // Error / status card
                    if let statusCard {
                        statusCard.padding(.bottom, 16)
                    }

                    // Email / password form
                    VStack(spacing: 12) {
                        AuthInputField(
                            title: "Email",
                            text: $email,
                            textColor: authFieldText,
                            promptColor: authFieldPrompt,
                            fillColor: authFieldFill,
                            borderTone: authFieldBorder,
                            focusedField: $focusedField,
                            field: .email,
                            submitLabel: requiresPassword ? .next : .go
                        ) {
                            if requiresPassword { focusedField = .password } else { submit() }
                        }

                        if requiresPassword {
                            VStack(alignment: .trailing, spacing: 10) {
                                SecureField(
                                    text: $password,
                                    prompt: Text("Password")
                                        .foregroundColor(authFieldPrompt)
                                ) {
                                    Text("")
                                }
                                    .font(ClavisTypography.inter(15, weight: .medium))
                                    .foregroundColor(authFieldText)
                                    .textContentType(mode == .signUp ? .newPassword : .password)
                                    .submitLabel(mode == .signUp ? .join : .go)
                                    .focused($focusedField, equals: .password)
                                    .onSubmit { submit() }
                                    .padding(.horizontal, 12)
                                    .frame(height: 48)
                                    .background(authFieldFill)
                                    .overlay(RoundedRectangle(cornerRadius: ClavixLayout.controlRadius).stroke(authFieldBorder, lineWidth: 1))
                                    .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.controlRadius, style: .continuous))

                                if mode == .signIn {
                                    Button("Forgot password?") {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            mode = .forgotPassword
                                            focusedField = .email
                                        }
                                    }
                                    .font(ClavisTypography.clavixCaption)
                                    .foregroundColor(authSecondaryText)
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        AuthActionButton(
                            title: submitTitle,
                            fill: .textPrimary,
                            foreground: .backgroundPrimary,
                            isLoading: authViewModel.isLoading,
                            isEnabled: isFormValid
                        ) { submit() }
                    }
                    .padding(.bottom, 20)

                    // "or" divider + social — sign in + sign up only
                    if mode == .signUp || mode == .signIn {
                        HStack(spacing: 12) {
                            Rectangle().fill(authDividerTone).frame(height: 1)
                            Text("or")
                                .font(ClavisTypography.clavixMono(10, weight: .regular))
                                .foregroundColor(authTertiaryText)
                                .fixedSize()
                            Rectangle().fill(authDividerTone).frame(height: 1)
                        }
                        .padding(.bottom, 16)

                        VStack(spacing: 10) {
                            SocialAuthButton(
                                logoView: AnyView(
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundColor(.backgroundPrimary)
                                ),
                                label: "Continue with Apple",
                                fill: .textPrimary,
                                foreground: .backgroundPrimary,
                                bordered: false
                            ) {
                                Task { await authViewModel.signInWithApple() }
                            }

                            SocialAuthButton(
                                logoView: AnyView(
                                    Text("G")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(Color(red: 0.26, green: 0.52, blue: 0.96))
                                ),
                                label: "Continue with Google",
                                fill: .surface,
                                foreground: .textPrimary,
                                bordered: true
                            ) {
                                Task { await authViewModel.signInWithGoogle() }
                            }
                        }
                        .padding(.bottom, 20)
                    }

                    secondaryActions
                        .padding(.bottom, 24)

                    termsFooter
                        .padding(.bottom, 40)
                }
                .padding(.horizontal, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            AuthStickyBar()
        }
    }

    private var formSubtitle: String? {
        switch mode {
        case .signUp: return "Start your 14-day trial, then $19.99/month."
        case .signIn: return "Welcome back."
        case .forgotPassword: return "Enter your email and we'll send a reset link."
        case .welcome: return nil
        }
    }

    @ViewBuilder
    private var secondaryActions: some View {
        switch mode {
        case .signIn:
            Button("Create account") {
                withAnimation(.easeInOut(duration: 0.15)) {
                    mode = .signUp
                    focusedField = .email
                }
            }
            .font(ClavisTypography.inter(14, weight: .semibold))
            .foregroundColor(authLinkTone)
            .buttonStyle(.plain)
        case .signUp:
            Button("Already have an account? Sign in") {
                withAnimation(.easeInOut(duration: 0.15)) {
                    mode = .signIn
                    focusedField = .email
                }
            }
            .font(ClavisTypography.inter(14, weight: .semibold))
            .foregroundColor(authLinkTone)
            .buttonStyle(.plain)
        case .forgotPassword:
            Button("Back to sign in") {
                withAnimation(.easeInOut(duration: 0.15)) {
                    mode = .signIn
                    focusedField = .email
                }
            }
            .font(ClavisTypography.inter(14, weight: .semibold))
            .foregroundColor(authLinkTone)
            .buttonStyle(.plain)
        case .welcome:
            EmptyView()
        }
    }

    private var formTitle: String {
        switch mode {
        case .signIn:
            return "Sign in"
        case .signUp:
            return "Create account"
        case .forgotPassword:
            return "Reset password"
        case .welcome:
            return ""
        }
    }

    private var submitTitle: String {
        switch mode {
        case .signUp:
            return "Continue"
        case .signIn:
            return "Sign in"
        case .forgotPassword:
            return "Send reset link"
        case .welcome:
            return ""
        }
    }

    private var formCaption: String? {
        switch mode {
        case .signUp:
            return "Your first report appears after your portfolio is added."
        case .signIn:
            return "Welcome back to Clavix."
        case .forgotPassword:
            return nil
        case .welcome:
            return nil
        }
    }

    private var statusCard: AnyView? {
        if let error = authViewModel.errorMessage?.sanitizedDisplayText, !error.isEmpty {
            return AnyView(AuthCard(fill: .badSoft) {
                Text(error)
                    .font(ClavisTypography.inter(14, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.94))
                    .fixedSize(horizontal: false, vertical: true)
            })
        } else if let status = authViewModel.statusMessage?.sanitizedDisplayText, !status.isEmpty {
            return AnyView(AuthCard(fill: .accentSoft) {
                Text(status)
                    .font(ClavisTypography.inter(14, weight: .regular))
                    .foregroundColor(.accentInk)
                    .fixedSize(horizontal: false, vertical: true)
            })
        }
        return nil
    }

    private var termsFooter: some View {
        VStack(spacing: 2) {
            Text("By continuing you agree to our")
            HStack(spacing: 4) {
                Link("Terms of Service", destination: URL(string: "https://getclavix.com/terms")!)
                    .foregroundColor(authLinkTone)
                Text("and")
                Link("Privacy Policy", destination: URL(string: "https://getclavix.com/privacy")!)
                    .foregroundColor(authLinkTone)
            }
        }
        .font(ClavisTypography.clavixMono(10, weight: .regular))
        .foregroundColor(authTertiaryText)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private func submit() {
        guard isFormValid, !authViewModel.isLoading else { return }
        Task {
            switch mode {
            case .signUp:
                await authViewModel.signUp(email: email, password: password)
            case .signIn:
                await authViewModel.signIn(email: email, password: password)
            case .forgotPassword:
                await authViewModel.resetPassword(email: email)
            case .welcome:
                return
            }
        }
    }
}

private struct WelcomeFeatureCarousel: View {
    private struct Slide: Identifiable {
        let id = UUID()
        let imageName: String
        let caption: String
        let subcaption: String
    }

    private let slides: [Slide] = [
        Slide(imageName: "screen_today_live",
              caption: "Your daily risk briefing",
              subcaption: "Five dimensions. One morning view."),
        Slide(imageName: "screen_holdings_live",
              caption: "Your whole portfolio, graded",
              subcaption: "Bond-style ratings for every position."),
        Slide(imageName: "screen_search_live",
              caption: "Screen any ticker",
              subcaption: "Drag the radar to filter by risk profile."),
        Slide(imageName: "screen_alerts_live",
              caption: "Know when risk shifts",
              subcaption: "Grade-change alerts before the open."),
    ]

    @State private var currentIndex = 0
    private let timer = Timer.publish(every: 3.5, on: .main, in: .common).autoconnect()

    private let cardSpacing: CGFloat = 16
    private let cardHeight: CGFloat = 260

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let cardWidth = geo.size.width * 0.55
                let centerOffset = (geo.size.width - cardWidth) / 2
                let advance = cardWidth + cardSpacing

                HStack(spacing: cardSpacing) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                        Image(slide.imageName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: cardWidth, height: cardHeight)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.border, lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.22), radius: 16, x: 0, y: 8)
                            .scaleEffect(index == currentIndex ? 1 : 0.93)
                            .opacity(index == currentIndex ? 1 : 0.55)
                            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: currentIndex)
                    }
                }
                .offset(x: centerOffset - CGFloat(currentIndex) * advance)
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: currentIndex)
            }
            .frame(height: cardHeight)
            .clipped()

            VStack(spacing: 3) {
                Text(slides[currentIndex].caption)
                    .font(ClavisTypography.inter(14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(slides[currentIndex].subcaption)
                    .font(ClavisTypography.inter(12, weight: .regular))
                    .foregroundColor(.textSecondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.2), value: currentIndex)

            HStack(spacing: 5) {
                ForEach(0..<slides.count, id: \.self) { i in
                    Circle()
                        .fill(i == currentIndex ? Color.textPrimary : Color.border)
                        .frame(width: i == currentIndex ? 6 : 4, height: i == currentIndex ? 6 : 4)
                        .animation(.easeInOut(duration: 0.2), value: currentIndex)
                }
            }
        }
        .onReceive(timer) { _ in
            currentIndex = (currentIndex + 1) % slides.count
        }
    }
}

private struct SocialAuthButton: View {
    let logoView: AnyView
    let label: String
    let fill: Color
    let foreground: Color
    let bordered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                logoView
                    .frame(width: 44, alignment: .center)
                Spacer()
                Text(label)
                    .font(ClavisTypography.inter(15, weight: .semibold))
                    .foregroundColor(foreground)
                Spacer()
                Color.clear.frame(width: 44)
            }
            .frame(height: 50)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ClavixLayout.controlRadius, style: .continuous)
                    .stroke(bordered ? Color.border : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct AuthActionButton: View {
    let title: String
    let fill: Color
    let foreground: Color
    var bordered: Bool = false
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: ClavixLayout.controlRadius, style: .continuous)
                    .fill(backgroundFill)
                    .frame(height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: ClavixLayout.controlRadius, style: .continuous)
                            .stroke(borderColor, lineWidth: bordered || !isEnabled ? 1 : 0)
                    )

                if isLoading {
                    ProgressView()
                        .tint(foreground)
                } else {
                    Text(title)
                        .font(ClavisTypography.inter(15, weight: .semibold))
                        .foregroundColor(isEnabled ? foreground : Color.white.opacity(0.32))
                }
            }
            .opacity(isEnabled ? 1 : 0.7)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }

    private var backgroundFill: Color {
        if !isEnabled {
            return Color.white.opacity(0.04)
        }
        return fill
    }

    private var borderColor: Color {
        if bordered || !isEnabled {
            return Color.white.opacity(0.12)
        }
        return .clear
    }
}

private struct AuthInputField: View {
    let title: String
    @Binding var text: String
    let textColor: Color
    let promptColor: Color
    let fillColor: Color
    let borderTone: Color
    var focusedField: FocusState<LoginView.Field?>.Binding
    let field: LoginView.Field
    let submitLabel: SubmitLabel
    let onSubmit: () -> Void

    var body: some View {
        TextField(
            text: $text,
            prompt: Text(title)
                .foregroundColor(promptColor)
        ) {
            Text("")
        }
            .font(ClavisTypography.inter(15, weight: .medium))
            .foregroundColor(textColor)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.emailAddress)
            .submitLabel(submitLabel)
            .focused(focusedField, equals: field)
            .onSubmit(onSubmit)
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: ClavixLayout.controlRadius)
                    .stroke(borderTone, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.controlRadius, style: .continuous))
    }
}

private struct AuthCard<Content: View>: View {
    var fill: Color = .surface
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)
            .overlay(
                RoundedRectangle(cornerRadius: ClavixLayout.cardRadius, style: .continuous)
                    .stroke(Color.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.cardRadius, style: .continuous))
    }
}

private struct AuthStickyBar: View {
    var body: some View {
        ZStack {
            HStack(spacing: 12) {
                ZStack {
                    Image("clavix_logo")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .foregroundColor(.textPrimary)
                    Image("clavix_logo")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .scaleEffect(1.18)
                        .foregroundColor(.textPrimary.opacity(0.3))
                }
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
                Spacer(minLength: 8)
            }

            Text("CLAVIX")
                .font(ClavisTypography.inter(17, weight: .bold))
                .tracking(1.2)
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color.backgroundPrimary.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.border)
                .frame(height: 1)
        }
    }
}
