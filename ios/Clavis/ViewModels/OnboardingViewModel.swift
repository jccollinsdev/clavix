import Foundation
import SwiftUI

enum OnboardingPage: Int, CaseIterable {
    case welcome = 0
    case addPortfolio = 1
}

// MARK: - Aha flow types

enum AhaPhase {
    case questions
    case reveal
}

// MARK: - Onboarding personalization (presentation only — never affects grade/score)

enum OnboardingPriority: String, CaseIterable, Identifiable {
    case financials, news, macro, sector, volatility
    var id: String { rawValue }
    /// Maps to the dimension keys used in `buildReveal`.
    var dimensionKey: String {
        switch self {
        case .financials: return "FIN"
        case .news:       return "NEWS"
        case .macro:      return "MAC"
        case .sector:     return "SEC"
        case .volatility: return "VOL"
        }
    }
    var label: String {
        switch self {
        case .financials: return "Financial health"
        case .news:       return "News & headlines"
        case .macro:      return "The economy"
        case .sector:     return "Sector concentration"
        case .volatility: return "Price swings"
        }
    }
}

enum OnboardingTimeline: String, CaseIterable, Identifiable {
    case short, medium, long
    var id: String { rawValue }
    var label: String {
        switch self {
        case .short:  return "Less than 1 year"
        case .medium: return "1 to 5 years"
        case .long:   return "More than 5 years"
        }
    }
}

enum OnboardingRiskTolerance: String, CaseIterable, Identifiable {
    case conservative, balanced, aggressive
    var id: String { rawValue }
    var label: String {
        switch self {
        case .conservative: return "Conservative"
        case .balanced:     return "Balanced"
        case .aggressive:   return "Aggressive"
        }
    }
}

/// How the user expresses the size of each holding during onboarding.
/// `shares` is the exact share count; `amount` is an estimated dollar value
/// that we convert to shares using the ticker's latest price at persist time.
enum OnboardingEntryMode {
    case shares
    case amount
}

struct AhaPortfolioEntry: Identifiable {
    let id = UUID()
    var query: String = ""
    var shares: String = ""
    var amount: String = ""
    var resolved: TickerSearchResult? = nil
    var isResolving: Bool = false
    var notFound: Bool = false
}

struct AhaDimensionFinding {
    let key: String
    let name: String
    let explanation: String
    let average: Double
    let weakCount: Int
    let total: Int
}

/// One holding's real score on a given metric (the components behind a portfolio average).
struct MetricContribution: Identifiable {
    let id = UUID()
    let ticker: String
    let value: Double
}

struct AhaReveal {
    let grade: String
    let score: Double
    let positionCount: Int
    let blindSpot: AhaDimensionFinding
    let dimensions: [AhaDimensionFinding]
    let weakestTicker: String?
    let weakestGrade: String?
    let strongestTicker: String?
    let strongestGrade: String?

    // Presentation-only personalization (does not affect grade/score).
    let focus: AhaDimensionFinding        // the dimension the radar emphasizes (user's concern)
    let focusIsConcern: Bool              // true when it came from the user's stated priority
    let strongest: AhaDimensionFinding?   // highest-average dimension
    let weakestCulpritTicker: String?     // holding lowest on the weakest metric
    let weakestCulpritValue: Double?
    let strongestLeaderTicker: String?    // holding highest on the strongest metric
    let strongestLeaderValue: Double?
    let weakestBreakdown: [MetricContribution]   // per-holding scores on the weakest metric
    let strongestBreakdown: [MetricContribution] // per-holding scores on the strongest metric
    let sourceCount: Int?                 // total real sources scanned across holdings
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var currentPage: OnboardingPage = .welcome
    @Published var isCompleting = false
    @Published var errorMessage: String?
    @Published private(set) var welcomeName: String?
    @Published private(set) var isPreparingAnalysis = false
    @Published private(set) var isPreparingHoldings = false

    // Aha flow state
    @Published var entries: [AhaPortfolioEntry] = [AhaPortfolioEntry()]
    @Published var entryMode: OnboardingEntryMode = .shares
    @Published var ahaPhase: AhaPhase = .questions
    @Published var reveal: AhaReveal?

    // Personalization answers (presentation only)
    @Published var priorities: Set<OnboardingPriority> = []   // up to 3
    @Published var timeline: OnboardingTimeline?
    @Published var riskTolerance: OnboardingRiskTolerance?

    static let maxPriorities = 3

    var questionsComplete: Bool {
        !priorities.isEmpty && timeline != nil && riskTolerance != nil
    }

    func togglePriority(_ p: OnboardingPriority) {
        if priorities.contains(p) {
            priorities.remove(p)
        } else if priorities.count < Self.maxPriorities {
            priorities.insert(p)
        }
    }

    private var resolveTasks: [UUID: Task<Void, Never>] = [:]
    private var prepareTask: Task<Void, Never>?
    private var isFinishing = false
    private let api = APIService.shared

    // MARK: - Paging

    func loadWelcomeName() async {
        guard welcomeName == nil else { return }
        welcomeName = await SupabaseAuthService.shared.getSocialAccountFirstName()
    }

    func nextPage() {
        withAnimation(.easeInOut(duration: 0.2)) {
            let nextIndex = min(currentPage.rawValue + 1, OnboardingPage.allCases.count - 1)
            currentPage = OnboardingPage(rawValue: nextIndex) ?? .addPortfolio
        }
    }

    func previousPage() {
        withAnimation(.easeInOut(duration: 0.2)) {
            let previousIndex = max(currentPage.rawValue - 1, 0)
            currentPage = OnboardingPage(rawValue: previousIndex) ?? .welcome
        }
    }

    // MARK: - Aha flow: live grade

    var resolvedResults: [TickerSearchResult] {
        entries.compactMap { $0.resolved }
    }

    var liveScore: Double? {
        let scores = resolvedResults.compactMap { $0.resolvedSafetyScore }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    var liveGrade: String? {
        guard let score = liveScore else { return nil }
        return PortfolioMath.grade(forScore: score)
    }

    var canAnalyze: Bool {
        !resolvedResults.isEmpty
    }

    var canAnalyzeEnteredHoldings: Bool {
        !enteredResults.isEmpty
    }

    private var enteredResults: [TickerSearchResult] {
        entries.compactMap { entry in
            guard let resolved = entry.resolved else { return nil }
            return enteredQuantity(for: entry) > 0 ? resolved : nil
        }
    }

    /// The raw quantity the user typed for this entry in the active mode:
    /// a share count in `.shares` mode, a dollar amount in `.amount` mode.
    /// The reveal grade is equal-weighted, so this only gates "is it entered"
    /// for scoring; the precise share count is derived at persist time.
    func enteredQuantity(for entry: AhaPortfolioEntry) -> Double {
        switch entryMode {
        case .shares:
            return Double(entry.shares.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        case .amount:
            return Self.dollarValue(entry.amount)
        }
    }

    /// Tickers the user actually entered (resolved, shares > 0), in order.
    /// Drives the "reading your holdings" pass on the analyzing screen.
    var analyzedTickers: [String] {
        enteredResults.map { $0.ticker }
    }

    /// Resolved holdings (shares > 0) with full per-ticker analysis attached.
    /// Drives the streaming dossier on the analyzing screen.
    var analyzedResults: [TickerSearchResult] {
        enteredResults
    }

    func maxEntries(isFreeTier _: Bool) -> Int {
        20
    }

    func addEntry(isFreeTier: Bool) {
        guard entries.count < maxEntries(isFreeTier: isFreeTier) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            entries.append(AhaPortfolioEntry())
        }
    }

    func removeEntry(_ id: UUID) {
        guard entries.count > 1 else { return }
        resolveTasks[id]?.cancel()
        resolveTasks.removeValue(forKey: id)
        withAnimation(.easeInOut(duration: 0.2)) {
            entries.removeAll { $0.id == id }
        }
    }

    // MARK: - Aha flow: ticker resolution (debounced)

    func updateQuery(_ id: UUID, _ value: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        errorMessage = nil
        entries[idx].query = value
        entries[idx].resolved = nil
        entries[idx].notFound = false
        scheduleResolve(id)
    }

    func updateShares(_ id: UUID, _ value: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        errorMessage = nil
        // Whole shares only — strip every non-digit so decimals can't form.
        entries[idx].shares = String(value.filter(\.isNumber).prefix(9))
    }

    /// Live reads from the published source so TextField bindings reflect
    /// sanitized/formatted values immediately while the field is first responder
    /// (a value-type snapshot captured in the binding would lag a keystroke).
    func sharesText(for id: UUID) -> String {
        entries.first { $0.id == id }?.shares ?? ""
    }

    func amountText(for id: UUID) -> String {
        entries.first { $0.id == id }?.amount ?? ""
    }

    func updateAmount(_ id: UUID, _ value: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        errorMessage = nil
        entries[idx].amount = Self.formatDollarInput(value)
    }

    /// Sanitize raw keystrokes into a grouped whole-dollar string, e.g.
    /// "1000000" -> "1,000,000". Strips every non-digit (so a malformed entry
    /// like "300.00.0" can never form) and caps at 7 digits ($9,999,999), since
    /// no single holding in our ICP exceeds that.
    static func formatDollarInput(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        let capped = String(digits.prefix(7))
        guard let value = Int(capped), value > 0 else { return "" }
        return dollarGroupingFormatter.string(from: NSNumber(value: value)) ?? capped
    }

    /// Parse a grouped dollar string back to its numeric value.
    static func dollarValue(_ formatted: String) -> Double {
        Double(formatted.filter(\.isNumber)) ?? 0
    }

    private static let dollarGroupingFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSeparator = ","
        f.maximumFractionDigits = 0
        return f
    }()

    func setEntryMode(_ mode: OnboardingEntryMode) {
        guard entryMode != mode else { return }
        errorMessage = nil
        withAnimation(.easeInOut(duration: 0.18)) {
            entryMode = mode
        }
    }

    private func scheduleResolve(_ id: UUID) {
        resolveTasks[id]?.cancel()
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        let raw = entries[idx].query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count >= 1 else {
            entries[idx].isResolving = false
            return
        }
        entries[idx].isResolving = true
        resolveTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.performResolve(id: id, query: raw)
        }
    }

    private func performResolve(id: UUID, query: String) async {
        do {
            let results = try await api.searchTickers(query: query, limit: 6)
            guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
            guard !Task.isCancelled else { return }
            let exact = results.first { $0.ticker.caseInsensitiveCompare(query) == .orderedSame }
            let match = exact ?? results.first
            entries[idx].isResolving = false
            if let match, match.resolvedSafetyScore != nil {
                entries[idx].resolved = match
                entries[idx].notFound = false
            } else {
                entries[idx].resolved = nil
                entries[idx].notFound = true
            }
        } catch {
            guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[idx].isResolving = false
            #if DEBUG
            if isDebugOnboardingEnabled,
               let fixture = debugTickerFixture(query: query) {
                entries[idx].resolved = fixture
                entries[idx].notFound = false
                return
            }
            #endif
        }
    }

    // MARK: - Aha flow: analyze + reveal

    /// Validate the entered holdings synchronously, advance to the questions
    /// immediately, and resolve/score the tickers in the background while the
    /// user answers, so there is no wait between the two screens.
    func continueToAnalysis() -> Bool {
        errorMessage = nil

        let activeEntries = entries.filter {
            !$0.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !$0.shares.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !$0.amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard !activeEntries.isEmpty else {
            errorMessage = entryMode == .amount
                ? "Add at least one ticker and dollar amount to continue."
                : "Add at least one ticker and share count to continue."
            return false
        }

        for entry in activeEntries {
            let ticker = entry.query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ticker.isEmpty else {
                errorMessage = "Enter a ticker for every holding."
                return false
            }
            guard enteredQuantity(for: entry) > 0 else {
                errorMessage = entryMode == .amount
                    ? "Enter a dollar amount greater than zero for \(ticker.uppercased())."
                    : "Enter a share count greater than zero for \(ticker.uppercased())."
                return false
            }
            if entry.notFound {
                errorMessage = "\(ticker.uppercased()) is currently unsupported. Try a different ticker."
                return false
            }
        }

        enterQuestions()
        startPreparingHoldings(activeEntries)
        return true
    }

    /// Advance to the quick personalization questions.
    func enterQuestions() {
        withAnimation(.easeInOut(duration: 0.35)) {
            ahaPhase = .questions
        }
    }

    /// Resolve any not-yet-resolved holdings in the background so the score is
    /// ready by the time the user finishes the questions.
    private func startPreparingHoldings(_ activeEntries: [AhaPortfolioEntry]) {
        prepareTask?.cancel()
        isPreparingHoldings = true
        prepareTask = Task { [weak self] in
            guard let self else { return }
            for entry in activeEntries {
                if Task.isCancelled { break }
                let ticker = entry.query.trimmingCharacters(in: .whitespacesAndNewlines)
                if self.entries.first(where: { $0.id == entry.id })?.resolved == nil {
                    self.resolveTasks[entry.id]?.cancel()
                    await self.performResolve(id: entry.id, query: ticker)
                }
            }
            self.isPreparingHoldings = false
        }
    }

    /// Called when the user taps through the questions. Waits for any in-flight
    /// background resolution, surfaces an unsupported ticker, else runs the analysis.
    func finishQuestions() {
        guard ahaPhase == .questions, !isFinishing else { return }
        isFinishing = true
        Task { [weak self] in
            guard let self else { return }
            await self.prepareTask?.value
            if let unresolved = self.entries.first(where: {
                !$0.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.resolved == nil
            }) {
                self.errorMessage = "\(unresolved.query.uppercased()) is currently unsupported. Try a different ticker."
                self.isFinishing = false
                return
            }
            self.errorMessage = nil
            self.isFinishing = false
            self.runAnalysis()
        }
    }

    func runAnalysis() {
        let results = enteredResults
        guard !results.isEmpty else { return }

        // Build the reveal, leading with the area(s) the user cares about
        // (presentation only — grade/score math is untouched), then go straight
        // to the reveal. No interstitial animation.
        reveal = OnboardingViewModel.buildReveal(results, priorities: priorities, timeline: timeline)
        persistAnswers()

        // Persist holdings in the background so the book is populated by the
        // time the user enters the app.
        #if DEBUG
        if !isDebugOnboardingEnabled {
            Task { await self.persistHoldings(results) }
        }
        #else
        Task { await self.persistHoldings(results) }
        #endif

        withAnimation(.easeInOut(duration: 0.4)) {
            ahaPhase = .reveal
        }
    }

    private func persistHoldings(_ results: [TickerSearchResult]) async {
        // Capture entries + mode snapshot before concurrent work begins (actor isolation).
        let snapEntries = entries
        let mode = entryMode
        // Fire all creates in parallel — sequential saves caused later tickers to
        // be missed when the user navigated to holdings before the loop finished.
        await withTaskGroup(of: Void.self) { group in
            for result in results {
                guard let entry = snapEntries.first(where: { $0.resolved?.ticker == result.ticker }) else {
                    continue
                }

                // Resolve a (shares, purchasePrice) pair from whichever mode the
                // user used. In amount mode we convert the dollar estimate to a
                // fractional share count at the latest price and record that price
                // as the cost basis so the position opens at break-even.
                let shares: Double
                let purchasePrice: Double
                switch mode {
                case .shares:
                    let raw = Double(entry.shares.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                    guard raw > 0 else { continue }
                    shares = raw
                    purchasePrice = 0
                case .amount:
                    let dollars = OnboardingViewModel.dollarValue(entry.amount)
                    guard dollars > 0, let price = result.resolvedPrice, price > 0 else { continue }
                    shares = dollars / price
                    purchasePrice = price
                }

                group.addTask {
                    _ = try? await APIService.shared.createHolding(
                        ticker: result.ticker,
                        shares: shares,
                        purchasePrice: purchasePrice,
                        allowOutsideUniverse: true
                    )
                }
            }
        }
    }

    private func persistAnswers() {
        let d = UserDefaults.standard
        d.set(priorities.map(\.rawValue), forKey: "clavix.onboarding.priorities")
        d.set(timeline?.rawValue, forKey: "clavix.onboarding.timeline")
        d.set(riskTolerance?.rawValue, forKey: "clavix.onboarding.riskTolerance")
    }

    static func buildReveal(_ results: [TickerSearchResult],
                            priorities: Set<OnboardingPriority> = [],
                            timeline _: OnboardingTimeline? = nil) -> AhaReveal? {
        guard !results.isEmpty else { return nil }

        let scores = results.compactMap { $0.resolvedSafetyScore }
        let avg = scores.isEmpty ? 50 : scores.reduce(0, +) / Double(scores.count)
        let grade = PortfolioMath.grade(forScore: avg)

        let dims: [(key: String, name: String, expl: String, get: (SharedRiskDimensions) -> Double?)] = [
            ("FIN",  "Financial Health",   "balance-sheet strength and profitability",   { $0.financialHealth }),
            ("NEWS", "News Sentiment",     "the tone of recent coverage",                { $0.newsSentiment }),
            ("MAC",  "Macro Resilience",   "how well it holds up against rates and the broad market", { $0.macroExposure }),
            ("SEC",  "Sector Resilience",  "how diversified it is across sectors",       { $0.sectorExposure }),
            ("VOL",  "Price Stability",    "how steady the price tends to be",           { $0.volatility }),
        ]

        var findings: [AhaDimensionFinding] = []
        var getters: [String: (SharedRiskDimensions) -> Double?] = [:]
        for d in dims {
            getters[d.key] = d.get
            let vals = results.compactMap { r -> Double? in
                guard let dims = r.sharedAnalysis?.riskDimensions else { return nil }
                return d.get(dims)
            }
            guard !vals.isEmpty else { continue }
            let a = vals.reduce(0, +) / Double(vals.count)
            let weak = vals.filter { $0 < 50 }.count
            findings.append(AhaDimensionFinding(
                key: d.key, name: d.name, explanation: d.expl,
                average: a, weakCount: weak, total: vals.count
            ))
        }

        guard let blind = findings.min(by: { $0.average < $1.average }) else { return nil }

        // Presentation-only focus: among the user's stated concerns, lead with the
        // one that scores lowest (the most worth flagging); otherwise the weakest
        // dimension overall.
        let concernKeys = Set(priorities.map { $0.dimensionKey })
        let concernFindings = findings.filter { concernKeys.contains($0.key) }
        let focus = concernFindings.min(by: { $0.average < $1.average }) ?? blind
        let focusIsConcern = !concernFindings.isEmpty

        // Strongest dimension (distinct from the weakest when possible).
        let strongestDim = findings.filter { $0.key != blind.key }.max(by: { $0.average < $1.average })
            ?? findings.max(by: { $0.average < $1.average })

        // Per-holding breakdown of a single metric (the real components of its average).
        func breakdown(forKey key: String) -> [MetricContribution] {
            guard let getter = getters[key] else { return [] }
            return results.compactMap { r -> MetricContribution? in
                guard let rd = r.sharedAnalysis?.riskDimensions, let v = getter(rd) else { return nil }
                return MetricContribution(ticker: r.ticker, value: v)
            }
        }
        // Weakest worst-first, strongest best-first.
        let weakestBreakdown = breakdown(forKey: blind.key).sorted { $0.value < $1.value }
        let strongestBreakdown = strongestDim.map { breakdown(forKey: $0.key).sorted { $0.value > $1.value } } ?? []
        let weakestEx = weakestBreakdown.first.map { ($0.ticker, $0.value) }
        let strongestEx = strongestBreakdown.first.map { ($0.ticker, $0.value) }

        let sorted = results.sorted { ($0.resolvedSafetyScore ?? 999) < ($1.resolvedSafetyScore ?? 999) }
        let weakestStock = sorted.first
        let strongestStock = sorted.count > 1 ? sorted.last : nil

        let totalSources = results.compactMap { $0.sharedAnalysis?.sourceCount }.reduce(0, +)

        return AhaReveal(
            grade: grade,
            score: avg,
            positionCount: results.count,
            blindSpot: blind,
            dimensions: findings,
            weakestTicker: weakestStock?.ticker,
            weakestGrade: weakestStock?.resolvedGrade,
            strongestTicker: strongestStock?.ticker,
            strongestGrade: strongestStock?.resolvedGrade,
            focus: focus,
            focusIsConcern: focusIsConcern,
            strongest: strongestDim,
            weakestCulpritTicker: weakestEx?.0,
            weakestCulpritValue: weakestEx?.1,
            strongestLeaderTicker: strongestEx?.0,
            strongestLeaderValue: strongestEx?.1,
            weakestBreakdown: weakestBreakdown,
            strongestBreakdown: strongestBreakdown,
            sourceCount: totalSources > 0 ? totalSources : nil
        )
    }

    #if DEBUG
    private var isDebugOnboardingEnabled: Bool {
        ProcessInfo.processInfo.environment["CLAVIX_DEBUG_ONBOARDING"] == "1"
    }

    private func debugTickerFixture(query: String) -> TickerSearchResult? {
        let ticker = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !ticker.isEmpty else { return nil }
        let payload: [String: Any] = [
            "ticker": ticker,
            "company_name": ticker == "AAPL" ? "Apple Inc." : "\(ticker) Holdings",
            "grade": "B+",
            "safety_score": 78,
            "is_supported": true,
            "shared_analysis": [
                "ticker": ticker,
                "company_name": ticker == "AAPL" ? "Apple Inc." : "\(ticker) Holdings",
                "current_score": 78,
                "current_grade": "B+",
                "freshness": ["status": "current"],
                "risk_dimensions": [
                    "financial_health": 84,
                    "news_sentiment": 72,
                    "macro_exposure": 69,
                    "sector_exposure": 63,
                    "volatility": 76
                ]
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return try? JSONDecoder().decode(TickerSearchResult.self, from: data)
    }
    #endif

    // MARK: - Completion

    func completeOnboarding(completion: @escaping () -> Void) {
        guard !isCompleting else { return }
        isCompleting = true
        errorMessage = nil

        Task {
            do {
                print("[Onboarding] Starting acknowledgeOnboarding")
                print("[Onboarding] Auth token present: \(await SupabaseAuthService.shared.getAccessToken() != nil)")
                try await api.acknowledgeOnboarding()
                print("[Onboarding] acknowledgeOnboarding succeeded")
                // Reset checklist so it re-appears after a fresh onboarding.
                for key in ["clavix.checklist.openedBreakdown", "clavix.checklist.viewedToday",
                            "clavix.checklist.trackedName", "clavix.checklist.dismissed"] {
                    UserDefaults.standard.removeObject(forKey: key)
                }
                completion()
            } catch let error as APIError {
                print("[Onboarding] APIError: \(error.localizedDescription)")
                switch error {
                case .unauthorized:
                    errorMessage = "Session expired. Please sign in again."
                case .serverError(let code):
                    errorMessage = "Server error (\(code)). Please try again."
                case .networkError:
                    errorMessage = "No connection. Please check your internet and try again."
                default:
                    errorMessage = "Couldn't complete setup. Please check your connection and try again."
                }
                isCompleting = false
            } catch {
                print("[Onboarding] Unexpected error: \(error.localizedDescription)")
                errorMessage = "Couldn't complete setup. Please check your connection and try again."
                isCompleting = false
            }
        }
    }
}
