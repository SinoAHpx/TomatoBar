import Foundation
import SwiftUI

enum ProductivityPeriod: String, CaseIterable {
    case today = "Today"
    case week = "This Week"
    case month = "This Month"
    case year = "This Year"
    case allTime = "All Time"
}

struct ProductivityStats {
    var workTime: TimeInterval = 0
    var restTime: TimeInterval = 0
    var idleTime: TimeInterval = 0

    var totalTime: TimeInterval {
        workTime + restTime + idleTime
    }
}

class ProductivityAnalyzer: ObservableObject {
    @Published var stats: ProductivityStats = ProductivityStats()

    func analyze(for period: ProductivityPeriod) {
        let transitions = loadTransitions()
        let filteredTransitions = filterTransitions(transitions, for: period)
        stats = calculateStats(from: filteredTransitions)
    }

    private struct TransitionData: Decodable {
        let type: String
        let timestamp: TimeInterval
        let toState: String
    }

    private func loadTransitions() -> [(timestamp: Date, toState: String)] {
        let fileManager = FileManager.default
        let logPath = fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("TomatoBar.log")
            .path

        guard fileManager.fileExists(atPath: logPath),
              let logData = try? String(contentsOfFile: logPath) else {
            return []
        }

        let decoder = JSONDecoder()
        var transitions: [(timestamp: Date, toState: String)] = []

        for line in logData.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let transition = try? decoder.decode(TransitionData.self, from: data),
                  transition.type == "transition" else {
                continue
            }

            transitions.append((Date(timeIntervalSince1970: transition.timestamp), transition.toState))
        }

        return transitions
    }

    private func filterTransitions(_ transitions: [(timestamp: Date, toState: String)], for period: ProductivityPeriod) -> [(timestamp: Date, toState: String)] {
        let now = Date()
        let calendar = Calendar.current

        let startDate: Date
        switch period {
        case .today:
            startDate = calendar.startOfDay(for: now)
        case .week:
            startDate = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        case .month:
            startDate = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        case .year:
            startDate = calendar.date(from: calendar.dateComponents([.year], from: now))!
        case .allTime:
            return transitions
        }

        return transitions.filter { $0.timestamp >= startDate }
    }

    private func calculateStats(from transitions: [(timestamp: Date, toState: String)]) -> ProductivityStats {
        var stats = ProductivityStats()
        var currentState = "idle"
        var stateStartTime = Date.distantPast

        for transition in transitions {
            let duration = transition.timestamp.timeIntervalSince(stateStartTime)

            if duration > 0 && stateStartTime != Date.distantPast {
                switch currentState {
                case "work":
                    stats.workTime += duration
                case "rest":
                    stats.restTime += duration
                default:
                    stats.idleTime += duration
                }
            }

            currentState = transition.toState
            stateStartTime = transition.timestamp
        }

        // Add time from last transition to now
        let duration = Date().timeIntervalSince(stateStartTime)
        if duration > 0 && stateStartTime != Date.distantPast {
            switch currentState {
            case "work":
                stats.workTime += duration
            case "rest":
                stats.restTime += duration
            default:
                stats.idleTime += duration
            }
        }

        return stats
    }
}
