import Charts
import SwiftUI

struct PVTView: View {
    private enum TrendPeriod: String, CaseIterable, Identifiable {
        case day = "1日"
        case week = "1週間"
        case month = "1ヶ月"

        var id: Self { self }
    }

    private struct TrendPoint: Identifiable {
        let id: Date
        let date: Date
        let averageMilliseconds: Int
        let fastestMilliseconds: Int
        let lapseCount: Int
        let testCount: Int
    }

    private enum TestState {
        case introduction
        case waiting
        case stimulus
        case feedback
        case completed
    }

    @EnvironmentObject private var store: PVTStore
    @Environment(\.scenePhase) private var scenePhase

    let sleepSessionID: UUID?
    let onCompleted: ((PVTResult) -> Void)?
    let onSkip: (() -> Void)?

    @State private var testState: TestState = .introduction
    @State private var reactionTimes: [Int] = []
    @State private var falseStarts = 0
    @State private var feedbackText = ""
    @State private var completedResult: PVTResult?
    @State private var stimulusPresentedAt: ContinuousClock.Instant?
    @State private var pendingTask: Task<Void, Never>?
    @State private var countdownTask: Task<Void, Never>?
    @State private var elapsedSeconds = 0.0
    @State private var trendPeriod: TrendPeriod = .day

    private let testDurationSeconds = 90.0

    init(
        sleepSessionID: UUID? = nil,
        onCompleted: ((PVTResult) -> Void)? = nil,
        onSkip: (() -> Void)? = nil
    ) {
        self.sleepSessionID = sleepSessionID
        self.onCompleted = onCompleted
        self.onSkip = onSkip
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage = store.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    testSurface
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                } header: {
                    Text("反応速度テスト")
                } footer: {
                    Text("これは90秒の簡易PVTです。医療上の診断や運転可否の判断には使用できません。")
                }

                if testState == .introduction, let latest = store.results.first {
                    Section("前回の結果") {
                        resultRows(latest)
                        resultChart(latest)
                    }
                }

                if testState == .introduction {
                    comparisonSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollBounceBehavior(.basedOnSize)
            .scrollContentBackground(.hidden)
            .ambientScreenBackground()
            .navigationTitle("PVT")
            .navigationBarTitleDisplayMode(.large)
        }
        .onDisappear(perform: cancelAllTasks)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, testState != .completed, testState != .introduction {
                resetTest()
            }
        }
    }

    @ViewBuilder
    private var testSurface: some View {
        switch testState {
        case .introduction:
            VStack(spacing: 16) {
                MascotPromptView(
                    message: "光ったら、すぐにタップしてね",
                    detail: "90秒だけ、一緒に反応の速さを測ります。",
                    imageSize: 86
                )
                Text("暗い円が黄色に変わるまで待ち、変わった瞬間に押します。90秒間繰り返します。")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("テストを始める", action: startTest)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                skipButton
            }
            .frame(maxWidth: .infinity, minHeight: 330)

        case .waiting, .stimulus, .feedback:
            VStack(spacing: 18) {
                ProgressView(value: elapsedSeconds, total: testDurationSeconds)
                Text("残り \(remainingSeconds)秒・\(reactionTimes.count)回計測")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)

                Button(action: handleTap) {
                    Circle()
                        .fill(testState == .stimulus ? Color.yellow : Color.secondary.opacity(0.18))
                        .overlay {
                            if testState == .stimulus {
                                Text("TAP")
                                    .font(.title.bold())
                                    .foregroundStyle(.black)
                            }
                        }
                        .frame(width: 210, height: 210)
                        .shadow(
                            color: testState == .stimulus ? .yellow.opacity(0.45) : .clear,
                            radius: 22
                        )
                }
                .buttonStyle(.plain)
                .disabled(testState == .feedback)
                .accessibilityLabel(testState == .stimulus ? "今すぐタップ" : "合図を待ってください")

                Text(statusText)
                    .font(.headline)
                    .foregroundStyle(testState == .feedback ? Color.accentColor : .secondary)
                    .frame(minHeight: 28)

                skipButton
            }
            .frame(maxWidth: .infinity, minHeight: 390)

        case .completed:
            if let result = completedResult {
                VStack(spacing: 18) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(.green)
                    Text("テスト完了")
                        .font(.title2.bold())
                    resultRows(result)
                    resultChart(result)
                    if let onCompleted {
                        Button("次へ") {
                            onCompleted(result)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                    } else {
                        Button("もう一度", action: resetTest)
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 350)
            }
        }
    }

    private var statusText: String {
        switch testState {
        case .waiting: "黄色になるまで待ってください"
        case .stimulus: "今すぐタップ"
        case .feedback: feedbackText
        default: ""
        }
    }

    @ViewBuilder
    private var skipButton: some View {
        if let onSkip {
            Button("PVTをスキップ") {
                cancelAllTasks()
                onSkip()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
    }

    private func resultRows(_ result: PVTResult) -> some View {
        VStack(spacing: 12) {
            LabeledContent("平均反応時間", value: "\(result.averageMilliseconds) ms")
            LabeledContent("最速", value: "\(result.fastestMilliseconds) ms")
            LabeledContent("500ms以上", value: "\(result.lapseCount)回")
            LabeledContent("フライング", value: "\(result.falseStarts)回")
            LabeledContent("計測回数", value: "\(result.reactionTimesMilliseconds.count)回")
        }
        .monospacedDigit()
    }

    private func resultChart(_ result: PVTResult) -> some View {
        Chart {
            ForEach(Array(result.reactionTimesMilliseconds.enumerated()), id: \.offset) { index, value in
                LineMark(
                    x: .value("試行", index + 1),
                    y: .value("反応時間", value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.indigo)

                PointMark(
                    x: .value("試行", index + 1),
                    y: .value("反応時間", value)
                )
                .foregroundStyle(value >= 500 ? Color.orange : Color.indigo)
            }

            RuleMark(y: .value("遅延基準", 500))
                .foregroundStyle(.orange.opacity(0.65))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("500 ms")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
        }
        .chartXAxisLabel("試行")
        .chartYAxisLabel("ms")
        .chartYScale(domain: 0...max(750, result.reactionTimesMilliseconds.max() ?? 750))
        .frame(height: 210)
        .accessibilityLabel("反応時間の推移グラフ")
        .accessibilityValue(
            "\(result.reactionTimesMilliseconds.count)回、平均\(result.averageMilliseconds)ミリ秒"
        )
    }

    @ViewBuilder
    private var comparisonSection: some View {
        Section {
            Picker("表示期間", selection: $trendPeriod) {
                ForEach(TrendPeriod.allCases) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)

            if comparisonPoints.isEmpty {
                ContentUnavailableView {
                    Label("この期間の結果はありません", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("PVTを完了すると反応時間の変化を比較できます。")
                }
            } else {
                comparisonSummary
                comparisonChart
            }
        } header: {
            Text("結果の比較")
        } footer: {
            Text(
                trendPeriod == .day
                    ? "今日はテストごとの平均を表示します。"
                    : "複数回実施した日は、その日の平均を1点として表示します。"
            )
        }
    }

    private var comparisonSummary: some View {
        let results = comparisonResults
        let allReactionTimes = results.flatMap(\.reactionTimesMilliseconds)
        let average = allReactionTimes.isEmpty
            ? 0
            : allReactionTimes.reduce(0, +) / allReactionTimes.count
        let fastest = allReactionTimes.min() ?? 0
        let lapses = allReactionTimes.filter { $0 >= 500 }.count

        return VStack(spacing: 10) {
            LabeledContent("実施回数", value: "\(results.count)回")
            LabeledContent("期間平均", value: "\(average) ms")
            LabeledContent("期間最速", value: "\(fastest) ms")
            LabeledContent("500ms以上", value: "\(lapses)回")
        }
        .monospacedDigit()
    }

    private var comparisonChart: some View {
        Chart {
            ForEach(comparisonPoints) { point in
                LineMark(
                    x: .value("日時", point.date),
                    y: .value("平均反応時間", point.averageMilliseconds)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.indigo)

                PointMark(
                    x: .value("日時", point.date),
                    y: .value("平均反応時間", point.averageMilliseconds)
                )
                .foregroundStyle(point.averageMilliseconds >= 500 ? Color.orange : Color.indigo)
            }

            RuleMark(y: .value("遅延基準", 500))
                .foregroundStyle(.orange.opacity(0.65))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: trendPeriod == .day ? 4 : 6)) { value in
                AxisGridLine()
                AxisTick()
                if trendPeriod == .day {
                    AxisValueLabel(format: .dateTime.hour().minute())
                } else {
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
        }
        .chartYAxisLabel("平均 ms")
        .chartYScale(domain: 0...comparisonChartMaximum)
        .frame(height: 230)
        .accessibilityLabel("PVT結果の\(trendPeriod.rawValue)比較グラフ")
        .accessibilityValue("\(comparisonResults.count)回の結果")
    }

    private var comparisonResults: [PVTResult] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDate: Date
        switch trendPeriod {
        case .day:
            startDate = today
        case .week:
            startDate = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .month:
            startDate = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        }
        return store.results
            .filter { $0.completedAt >= startDate }
            .sorted { $0.completedAt < $1.completedAt }
    }

    private var comparisonPoints: [TrendPoint] {
        if trendPeriod == .day {
            return comparisonResults.map { result in
                TrendPoint(
                    id: result.completedAt,
                    date: result.completedAt,
                    averageMilliseconds: result.averageMilliseconds,
                    fastestMilliseconds: result.fastestMilliseconds,
                    lapseCount: result.lapseCount,
                    testCount: 1
                )
            }
        }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: comparisonResults) {
            calendar.startOfDay(for: $0.completedAt)
        }
        return grouped.map { day, results in
            let reactionTimes = results.flatMap(\.reactionTimesMilliseconds)
            return TrendPoint(
                id: day,
                date: day,
                averageMilliseconds: reactionTimes.isEmpty
                    ? 0
                    : reactionTimes.reduce(0, +) / reactionTimes.count,
                fastestMilliseconds: reactionTimes.min() ?? 0,
                lapseCount: reactionTimes.filter { $0 >= 500 }.count,
                testCount: results.count
            )
        }
        .sorted { $0.date < $1.date }
    }

    private var comparisonChartMaximum: Int {
        max(750, comparisonPoints.map(\.averageMilliseconds).max() ?? 750)
    }

    private var remainingSeconds: Int {
        max(0, Int(ceil(testDurationSeconds - elapsedSeconds)))
    }

    private func startTest() {
        reactionTimes = []
        falseStarts = 0
        completedResult = nil
        elapsedSeconds = 0
        startCountdown()
        scheduleStimulus()
    }

    private func startCountdown() {
        countdownTask?.cancel()
        let startedAt = ContinuousClock.now
        countdownTask = Task { @MainActor in
            while !Task.isCancelled {
                let duration = startedAt.duration(to: .now)
                let elapsed = Double(duration.components.seconds)
                    + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
                elapsedSeconds = min(testDurationSeconds, elapsed)
                if elapsed >= testDurationSeconds {
                    finishTest()
                    return
                }
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
            }
        }
    }

    private func scheduleStimulus() {
        cancelPendingTask()
        testState = .waiting
        stimulusPresentedAt = nil
        let delay = Int.random(in: 1_500...4_000)
        pendingTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled, testState == .waiting else { return }
            stimulusPresentedAt = ContinuousClock.now
            testState = .stimulus
            startResponseTimeout()
        }
    }

    private func startResponseTimeout() {
        pendingTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            guard !Task.isCancelled, testState == .stimulus else { return }
            reactionTimes.append(3_000)
            stimulusPresentedAt = nil
            showFeedback("反応なし", then: scheduleStimulus)
        }
    }

    private func handleTap() {
        switch testState {
        case .waiting:
            falseStarts += 1
            cancelPendingTask()
            showFeedback("少し早すぎました", then: scheduleStimulus)

        case .stimulus:
            guard let stimulusPresentedAt else { return }
            let elapsed = stimulusPresentedAt.duration(to: .now)
            let milliseconds = max(1, Int(elapsed.components.seconds * 1_000)
                + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))
            reactionTimes.append(milliseconds)
            self.stimulusPresentedAt = nil
            cancelPendingTask()
            showFeedback("\(milliseconds) ms", then: scheduleStimulus)

        default:
            break
        }
    }

    private func showFeedback(_ text: String, then next: @escaping @MainActor () -> Void) {
        feedbackText = text
        testState = .feedback
        pendingTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(650))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            next()
        }
    }

    private func finishTest() {
        cancelAllTasks()
        if reactionTimes.isEmpty {
            reactionTimes.append(3_000)
        }
        guard let result = store.save(
            reactionTimesMilliseconds: reactionTimes,
            falseStarts: falseStarts,
            sleepSessionID: sleepSessionID
        ) else { return }
        completedResult = result
        testState = .completed
    }

    private func resetTest() {
        cancelAllTasks()
        reactionTimes = []
        falseStarts = 0
        feedbackText = ""
        completedResult = nil
        stimulusPresentedAt = nil
        elapsedSeconds = 0
        testState = .introduction
    }

    private func cancelPendingTask() {
        pendingTask?.cancel()
        pendingTask = nil
    }

    private func cancelAllTasks() {
        cancelPendingTask()
        countdownTask?.cancel()
        countdownTask = nil
    }
}

#Preview {
    PVTView()
        .environmentObject(PVTStore())
}
