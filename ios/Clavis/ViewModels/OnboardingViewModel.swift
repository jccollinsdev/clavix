import Foundation
import SwiftUI

enum OnboardingPage: Int, CaseIterable {
    case welcome = 0
    case addPortfolio = 1
}

// MARK: - Aha flow types

enum AhaPhase {
    case input
    case analyzing
    case reveal
}

struct AhaPortfolioEntry: Identifiable {
    let id = UUID()
    var query: String = ""
    var shares: String = ""
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
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var currentPage: OnboardingPage = .welcome
    @Published var isCompleting = false
    @Published var errorMessage: String?
    @Published private(set) var welcomeName: String?
    @Published private(set) var isPreparingAnalysis = false

    // Aha flow state
    @Published var entries: [AhaPortfolioEntry] = [AhaPortfolioEntry()]
    @Published var ahaPhase: AhaPhase = .input
    @Published var reveal: AhaReveal?

    private var resolveTasks: [UUID: Task<Void, Never>] = [:]
    private var revealTask: Task<Void, Never>?
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
            let shares = Double(entry.shares.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            return shares > 0 ? resolved : nil
        }
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
        entries[idx].shares = value
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

    func continueToAnalysis() async -> Bool {
        guard !isPreparingAnalysis else { return false }
        isPreparingAnalysis = true
        errorMessage = nil
        defer { isPreparingAnalysis = false }

        let activeEntries = entries.filter {
            !$0.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !$0.shares.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard !activeEntries.isEmpty else {
            errorMessage = "Add at least one ticker and share count to continue."
            return false
        }

        for entry in activeEntries {
            let ticker = entry.query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ticker.isEmpty else {
                errorMessage = "Enter a ticker for every holding."
                return false
            }

            let shares = Double(entry.shares.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            guard shares > 0 else {
                errorMessage = "Enter a share count greater than zero for \(ticker.uppercased())."
                return false
            }

            if entry.resolved == nil {
                resolveTasks[entry.id]?.cancel()
                await performResolve(id: entry.id, query: ticker)
            }
        }

        let unresolvedTicker = activeEntries.first { entry in
            entries.first(where: { $0.id == entry.id })?.resolved == nil
        }?.query
        if let unresolvedTicker {
            errorMessage = "We couldn't load \(unresolvedTicker.uppercased()). Check the ticker and try again."
            return false
        }

        runAnalysis()
        return true
    }

    func runAnalysis() {
        let results = enteredResults
        guard !results.isEmpty else { return }

        withAnimation(.easeInOut(duration: 0.35)) {
            ahaPhase = .analyzing
        }

        // Persist holdings in the background so the book is populated by the
        // time the user enters the app.
        #if DEBUG
        if !isDebugOnboardingEnabled {
            Task { await self.persistHoldings(results) }
        }
        #else
        Task { await self.persistHoldings(results) }
        #endif

        // Retain the task so the reveal survives the page transition into the
        // analyzing screen.
        revealTask?.cancel()
        revealTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(7.8))
            guard !Task.isCancelled, let self else { return }
            let built = OnboardingViewModel.buildReveal(results)
            self.reveal = built
            withAnimation(.easeInOut(duration: 0.4)) {
                self.ahaPhase = .reveal
            }
        }
    }

    private func persistHoldings(_ results: [TickerSearchResult]) async {
        // Capture entries snapshot before concurrent work begins (actor isolation).
        let snapEntries = entries
        // Fire all creates in parallel — sequential saves caused later tickers to
        // be missed when the user navigated to holdings before the loop finished.
        await withTaskGroup(of: Void.self) { group in
            for result in results {
                let sharesString = snapEntries.first { $0.resolved?.ticker == result.ticker }?.shares ?? ""
                guard let shares = Double(sharesString.trimmingCharacters(in: .whitespacesAndNewlines)),
                      shares > 0 else {
                    continue
                }
                group.addTask {
                    _ = try? await APIService.shared.createHolding(
                        ticker: result.ticker,
                        shares: shares,
                        purchasePrice: 0,
                        allowOutsideUniverse: true
                    )
                }
            }
        }
    }

    static func buildReveal(_ results: [TickerSearchResult]) -> AhaReveal? {
        guard !results.isEmpty else { return nil }

        let scores = results.compactMap { $0.resolvedSafetyScore }
        let avg = scores.isEmpty ? 50 : scores.reduce(0, +) / Double(scores.count)
        let grade = PortfolioMath.grade(forScore: avg)

        let dims: [(key: String, name: String, expl: String, get: (SharedRiskDimensions) -> Double?)] = [
            ("FIN",  "Financial Health", "balance-sheet strength and profitability", { $0.financialHealth }),
            ("NEWS", "News Sentiment",   "the tone of recent coverage",              { $0.newsSentiment }),
            ("MAC",  "Macro Exposure",   "sensitivity to interest rates and the broad market", { $0.macroExposure }),
            ("SEC",  "Sector Exposure",  "concentration in a single sector",         { $0.sectorExposure }),
            ("VOL",  "Volatility",       "how sharply these prices can swing",        { $0.volatility }),
        ]

        var findings: [AhaDimensionFinding] = []
        for d in dims {
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

        let sorted = results.sorted { ($0.resolvedSafetyScore ?? 999) < ($1.resolvedSafetyScore ?? 999) }
        let weakest = sorted.first
        let strongest = sorted.count > 1 ? sorted.last : nil

        return AhaReveal(
            grade: grade,
            score: avg,
            positionCount: results.count,
            blindSpot: blind,
            dimensions: findings,
            weakestTicker: weakest?.ticker,
            weakestGrade: weakest?.resolvedGrade,
            strongestTicker: strongest?.ticker,
            strongestGrade: strongest?.resolvedGrade
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
            "grade": "A",
            "safety_score": 78,
            "is_supported": true,
            "shared_analysis": [
                "ticker": ticker,
                "company_name": ticker == "AAPL" ? "Apple Inc." : "\(ticker) Holdings",
                "current_score": 78,
                "current_grade": "A",
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
