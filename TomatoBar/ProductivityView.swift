import SwiftUI

struct ProductivityView: View {
    @StateObject private var analyzer = ProductivityAnalyzer()
    @State private var selectedPeriod: ProductivityPeriod = .today

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $selectedPeriod) {
                ForEach(ProductivityPeriod.allCases, id: \.self) { period in
                    Text(localizedPeriod(period)).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: selectedPeriod) { newPeriod in
                analyzer.analyze(for: newPeriod)
            }

            VStack(spacing: 8) {
                StatRow(
                    label: NSLocalizedString("ProductivityView.work", comment: "Work"),
                    time: analyzer.stats.workTime
                )
                StatRow(
                    label: NSLocalizedString("ProductivityView.rest", comment: "Rest"),
                    time: analyzer.stats.restTime
                )
                StatRow(
                    label: NSLocalizedString("ProductivityView.idle", comment: "Idle"),
                    time: analyzer.stats.idleTime
                )
            }
        }
        .padding(12)
        .frame(width: 240)
        .onAppear {
            analyzer.analyze(for: selectedPeriod)
        }
    }

    private func localizedPeriod(_ period: ProductivityPeriod) -> String {
        switch period {
        case .today:
            return NSLocalizedString("ProductivityView.period.today", comment: "Today")
        case .week:
            return NSLocalizedString("ProductivityView.period.week", comment: "Week")
        case .month:
            return NSLocalizedString("ProductivityView.period.month", comment: "Month")
        case .year:
            return NSLocalizedString("ProductivityView.period.year", comment: "Year")
        case .allTime:
            return NSLocalizedString("ProductivityView.period.allTime", comment: "All")
        }
    }
}

private struct StatRow: View {
    let label: String
    let time: TimeInterval

    var body: some View {
        HStack {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(formatTime(time))
                .font(.system(.body).monospacedDigit())
                .foregroundColor(.secondary)
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = Int(interval) / 60 % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }
}
