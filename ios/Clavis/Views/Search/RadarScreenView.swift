import SwiftUI

// MARK: - Axes

/// The five product risk dimensions, in the same order the ticker-detail radar
/// draws them. Higher score = safer on every axis, so the screener metaphor is
/// "drag a point outward to demand a higher minimum on that dimension."
enum RadarAxis: String, CaseIterable, Identifiable {
    case financialHealth
    case newsSentiment
    case macroExposure
    case sectorExposure
    case volatility

    var id: String { rawValue }

    /// Short axis label drawn on the radar (matches TickerDetailView).
    var short: String {
        switch self {
        case .financialHealth: return "FIN"
        case .newsSentiment:   return "NEWS"
        case .macroExposure:   return "MAC"
        case .sectorExposure:  return "SEC"
        case .volatility:      return "VOL"
        }
    }

    var title: String {
        switch self {
        case .financialHealth: return "Financial Health"
        case .newsSentiment:   return "News Sentiment"
        case .macroExposure:   return "Macro Exposure"
        case .sectorExposure:  return "Sector Exposure"
        case .volatility:      return "Volatility"
        }
    }
}

extension UniverseScreenItem {
    func score(for axis: RadarAxis) -> Double? {
        switch axis {
        case .financialHealth: return financialHealth
        case .newsSentiment:   return newsSentiment
        case .macroExposure:   return macroExposure
        case .sectorExposure:  return sectorExposure
        case .volatility:      return volatility
        }
    }
}

// MARK: - View model

@MainActor
final class RadarScreenViewModel: ObservableObject {
    @Published var thresholds: [RadarAxis: Double]
    @Published private(set) var allItems: [UniverseScreenItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasLoaded = false

    init() {
        thresholds = Dictionary(uniqueKeysWithValues: RadarAxis.allCases.map { ($0, 0.0) })
    }

    var total: Int { allItems.count }

    var isFiltering: Bool { thresholds.values.contains { $0 > 0 } }

    /// Names matching every raised axis. A `nil` dimension is treated as
    /// "unknown" and excluded only when that axis's minimum is above zero —
    /// so leaving an axis at "Any" never penalises a name for missing data.
    var matches: [UniverseScreenItem] {
        guard !allItems.isEmpty else { return [] }
        let active = thresholds.filter { $0.value > 0 }
        guard !active.isEmpty else { return allItems }
        return allItems.filter { item in
            for (axis, minimum) in active {
                guard let score = item.score(for: axis), score >= minimum else { return false }
            }
            return true
        }
    }

    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        do {
            let items = try await APIService.shared.fetchUniverseScreen()
            allItems = items
            hasLoaded = true
        } catch {
            errorMessage = ClavisCopy.Errors.tickerSearch(error)
        }
        isLoading = false
    }

    func reset() {
        for axis in RadarAxis.allCases { thresholds[axis] = 0 }
    }

    func apply(_ preset: [RadarAxis: Double]) {
        for axis in RadarAxis.allCases { thresholds[axis] = preset[axis] ?? 0 }
    }
}

// MARK: - Section

struct RadarScreenSection: View {
    @StateObject private var vm = RadarScreenViewModel()

    private let maxRows = 40

    var body: some View {
        let matches = vm.matches
        let shown = Array(matches.prefix(maxRows))

        ClavixSection(eyebrow: "Screen the S&P 500", title: "Risk radar") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Drag each point outward to set a minimum on that dimension. Names matching your shape appear below.")
                    .font(ClavisTypography.clavixCaption)
                    .foregroundColor(.clavixInk3)
                    .fixedSize(horizontal: false, vertical: true)

                RadarFilterChart(thresholds: $vm.thresholds)
                    .frame(maxWidth: .infinity)

                presetRow

                matchSummary(matchCount: matches.count)

                if vm.isFiltering && (vm.thresholds[.newsSentiment] ?? 0) > 0 {
                    Text("News is scored for roughly 1 in 5 names. Raising the NEWS axis only keeps names with a scored news read.")
                        .font(ClavisTypography.clavixMono(10, weight: .regular))
                        .tracking(0.2)
                        .foregroundColor(.clavixInk3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                resultsArea(matches: matches, shown: shown)
            }
        }
        .task { await vm.loadIfNeeded() }
    }

    // MARK: Presets

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                presetChip("Reset", systemImage: "arrow.counterclockwise", isActive: !vm.isFiltering) {
                    vm.reset()
                }
                presetChip("Defensive", systemImage: "shield.lefthalf.filled") {
                    vm.apply([.macroExposure: 70, .volatility: 70, .financialHealth: 55])
                }
                presetChip("High quality", systemImage: "checkmark.seal") {
                    vm.apply([.financialHealth: 70, .sectorExposure: 60])
                }
                presetChip("Steady", systemImage: "waveform.path.ecg") {
                    vm.apply([.volatility: 75])
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func presetChip(_ title: String, systemImage: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
                Text(title).font(ClavisTypography.clavixMono(11, weight: .semibold))
            }
            .foregroundColor(isActive ? .clavixPaper : .clavixInk2)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(isActive ? Color.clavixInk : Color.clavixPaper)
            .overlay(
                RoundedRectangle(cornerRadius: ClavixLayout.controlRadius, style: .continuous)
                    .stroke(Color.clavixRule, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Summary

    private func matchSummary(matchCount: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if vm.hasLoaded {
                if vm.isFiltering {
                    Text("\(matchCount)")
                        .font(ClavisTypography.clavixMono(15, weight: .bold))
                        .foregroundColor(.clavixInk)
                    Text("of \(vm.total) match your shape")
                        .font(ClavisTypography.clavixCaption)
                        .foregroundColor(.clavixInk3)
                } else {
                    Text("\(vm.total)")
                        .font(ClavisTypography.clavixMono(15, weight: .bold))
                        .foregroundColor(.clavixInk)
                    Text("names tracked. Drag to narrow.")
                        .font(ClavisTypography.clavixCaption)
                        .foregroundColor(.clavixInk3)
                }
            } else if vm.isLoading {
                Text("Loading the tracked universe…")
                    .font(ClavisTypography.clavixCaption)
                    .foregroundColor(.clavixInk3)
            }
            Spacer()
        }
    }

    // MARK: Results

    @ViewBuilder
    private func resultsArea(matches: [UniverseScreenItem], shown: [UniverseScreenItem]) -> some View {
        if let errorMessage = vm.errorMessage {
            ClavixInlineNoticeCard(
                eyebrow: "Screener",
                title: "Couldn't load the universe",
                message: errorMessage,
                glyph: "wifi.exclamationmark",
                fill: .clavixBadSoft,
                foreground: .clavixBadInk,
                secondary: .clavixBadInk,
                buttonTitle: "Try again",
                action: { Task { await vm.reload() } }
            )
        } else if vm.isLoading && !vm.hasLoaded {
            ClavixInlineNoticeCard(
                eyebrow: "Screener",
                title: "Loading the tracked universe",
                message: "Pulling the latest grade and five-dimension read for every name.",
                glyph: "dot.radiowaves.left.and.right"
            )
        } else if vm.hasLoaded && matches.isEmpty {
            ClavixInlineNoticeCard(
                eyebrow: "No match",
                title: "No names match this shape",
                message: "Your minimums are stricter than any tracked name. Ease one of the axes back toward the centre.",
                glyph: "circle.dashed"
            )
        } else if vm.hasLoaded {
            ClavixCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: item.ticker) {
                            ScreenResultRow(item: item)
                        }
                        .buttonStyle(.plain)
                        if index < shown.count - 1 {
                            Rectangle().fill(Color.clavixRule).frame(height: 1)
                        }
                    }
                }
            }

            if matches.count > shown.count {
                Text("+ \(matches.count - shown.count) more. Tighten the radar to focus the list.")
                    .font(ClavisTypography.clavixMono(10, weight: .regular))
                    .tracking(0.2)
                    .foregroundColor(.clavixInk3)
                    .padding(.top, 2)
            }
        }
    }
}

// MARK: - Interactive radar

struct RadarFilterChart: View {
    @Binding var thresholds: [RadarAxis: Double]
    var size: CGFloat = 248

    private let axes = RadarAxis.allCases
    private let spaceName = "radarFilterSpace"
    /// Minimum drawn fraction so handles never collapse onto each other at the
    /// centre when their value is 0 — they stay individually grabbable.
    private let floorFraction: CGFloat = 0.10

    var body: some View {
        GeometryReader { geo in
            let frame = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: frame / 2, y: frame / 2)
            let radius = frame * 0.32
            let labelRadius = frame * 0.45
            let count = axes.count

            ZStack {
                // Concentric guide rings
                ForEach(1..<5, id: \.self) { ring in
                    let scale = CGFloat(ring) / 4.0
                    polygonPath(center: center, radius: radius * scale, count: count)
                        .stroke(Color.clavixRule, lineWidth: ring == 4 ? 1.5 : 1)
                }

                // Spokes + labels + per-axis value chips
                ForEach(Array(axes.enumerated()), id: \.element) { index, axis in
                    let outer = polygonPoint(center: center, radius: radius, index: index, count: count)
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: outer)
                    }
                    .stroke(Color.clavixRule, style: StrokeStyle(lineWidth: 0.75))

                    let labelPoint = polygonPoint(center: center, radius: labelRadius, index: index, count: count)
                    VStack(spacing: 1) {
                        Text(axis.short)
                            .font(ClavisTypography.clavixMono(10, weight: .bold))
                            .foregroundColor(.clavixInk3)
                        Text(valueLabel(for: axis))
                            .font(ClavisTypography.clavixMono(9, weight: .bold))
                            .foregroundColor((thresholds[axis] ?? 0) > 0 ? .clavixAccent : .clavixInk4)
                    }
                    .position(labelPoint)
                }

                // Current threshold shape
                thresholdPath(center: center, radius: radius, count: count)
                    .fill(Color.clavixAccentSoft.opacity(0.45))
                thresholdPath(center: center, radius: radius, count: count)
                    .stroke(Color.clavixAccent, style: StrokeStyle(lineWidth: 2))

                // Draggable handles
                ForEach(Array(axes.enumerated()), id: \.element) { index, axis in
                    let fraction = drawnFraction(for: thresholds[axis] ?? 0)
                    let point = polygonPoint(center: center, radius: radius * fraction, index: index, count: count)
                    handle
                        .position(point)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named(spaceName))
                                .onChanged { value in
                                    thresholds[axis] = projectedValue(
                                        location: value.location,
                                        center: center,
                                        index: index,
                                        count: count,
                                        radius: radius
                                    )
                                }
                        )
                }
            }
            .frame(width: frame, height: frame)
            .frame(maxWidth: .infinity)
            .coordinateSpace(name: spaceName)
        }
        .frame(width: size, height: size)
    }

    private var handle: some View {
        ZStack {
            Circle().fill(Color.clavixPaper).frame(width: 18, height: 18)
            Circle().stroke(Color.clavixAccent, lineWidth: 2.5).frame(width: 18, height: 18)
            Circle().fill(Color.clavixAccent).frame(width: 7, height: 7)
        }
        .frame(width: 36, height: 36)          // enlarged hit target
        .contentShape(Circle())
    }

    private func valueLabel(for axis: RadarAxis) -> String {
        let value = thresholds[axis] ?? 0
        return value > 0 ? "≥\(Int(value))" : "Any"
    }

    private func drawnFraction(for value: Double) -> CGFloat {
        max(CGFloat(value / 100.0), floorFraction)
    }

    private func thresholdPath(center: CGPoint, radius: CGFloat, count: Int) -> Path {
        Path { path in
            for (index, axis) in axes.enumerated() {
                let fraction = drawnFraction(for: thresholds[axis] ?? 0)
                let point = polygonPoint(center: center, radius: radius * fraction, index: index, count: count)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
    }

    private func polygonPath(center: CGPoint, radius: CGFloat, count: Int) -> Path {
        Path { path in
            for index in 0..<count {
                let point = polygonPoint(center: center, radius: radius, index: index, count: count)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
    }

    private func polygonPoint(center: CGPoint, radius: CGFloat, index: Int, count: Int) -> CGPoint {
        let angle = (-CGFloat.pi / 2) + (CGFloat(index) * (2 * .pi / CGFloat(count)))
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }

    /// Project a drag location onto its axis, clamp to [0, radius], convert to a
    /// 0–100 minimum and snap to the nearest 5.
    private func projectedValue(location: CGPoint, center: CGPoint, index: Int, count: Int, radius: CGFloat) -> Double {
        let angle = (-CGFloat.pi / 2) + (CGFloat(index) * (2 * .pi / CGFloat(count)))
        let dir = CGPoint(x: cos(angle), y: sin(angle))
        let rel = CGPoint(x: location.x - center.x, y: location.y - center.y)
        let projection = rel.x * dir.x + rel.y * dir.y
        let clamped = min(max(projection, 0), radius)
        let raw = Double(clamped / radius) * 100.0
        return (raw / 5).rounded() * 5
    }
}

// MARK: - Result row

private struct ScreenResultRow: View {
    let item: UniverseScreenItem

    private var grade: String { item.grade ?? "—" }
    private var compositeText: String { "\(Int(item.compositeScore.rounded()))" }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(item.ticker)
                        .font(ClavisTypography.clavixMono(13, weight: .bold))
                        .tracking(0.3)
                        .foregroundColor(.clavixInk)
                    Text(item.companyName)
                        .font(ClavisTypography.inter(12, weight: .regular))
                        .foregroundColor(.clavixInk3)
                        .lineLimit(1)
                }
                if let sector = item.sector, !sector.isEmpty {
                    Text(sector.uppercased())
                        .font(ClavisTypography.clavixMono(8, weight: .bold))
                        .tracking(0.4)
                        .foregroundColor(.clavixInk4)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(compositeText)
                    .font(ClavisTypography.clavixMono(13, weight: .semibold))
                    .foregroundColor(.clavixInk)
                Text("SCORE")
                    .font(ClavisTypography.clavixMono(8, weight: .bold))
                    .tracking(0.4)
                    .foregroundColor(.clavixInk4)
            }
            .frame(width: 52, alignment: .trailing)
            ClavixGradeBadge(grade, size: 18)
            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundColor(.clavixInk4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
