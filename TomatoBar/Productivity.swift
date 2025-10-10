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
    var completedTomatoes: Int = 0
    var failedTomatoes: Int = 0
    var completedDashes: Int = 0
    var workTime: TimeInterval = 0
    var restTime: TimeInterval = 0

    var totalTomatoes: Int {
        completedTomatoes + failedTomatoes
    }
}

class ProductivityAnalyzer: ObservableObject {
    @Published var stats: ProductivityStats = ProductivityStats()

    func analyze(for period: ProductivityPeriod) {
        let tomatoEvents = loadTomatoEvents()
        let transitions = loadTransitions()
        let filteredTomatoEvents = filterEvents(tomatoEvents, for: period)
        let filteredTransitions = filterTransitions(transitions, for: period)
        stats = calculateStats(from: filteredTomatoEvents, transitions: filteredTransitions)
    }

    private struct LogEventData: Decodable {
        let type: String
        let timestamp: TimeInterval
        let goal: String?
        let toState: String?
    }

    private func loadTomatoEvents() -> [(timestamp: Date, type: String)] {
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
        var events: [(timestamp: Date, type: String)] = []

        for line in logData.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let event = try? decoder.decode(LogEventData.self, from: data),
                  (event.type == "tomatoCompleted" || event.type == "tomatoFailed" || event.type == "dashCompleted") else {
                continue
            }

            events.append((Date(timeIntervalSince1970: event.timestamp), event.type))
        }

        return events
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
                  let event = try? decoder.decode(LogEventData.self, from: data),
                  event.type == "transition",
                  let toState = event.toState else {
                continue
            }

            transitions.append((Date(timeIntervalSince1970: event.timestamp), toState))
        }

        return transitions
    }

    private func filterEvents(_ events: [(timestamp: Date, type: String)], for period: ProductivityPeriod) -> [(timestamp: Date, type: String)] {
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
            return events
        }

        return events.filter { $0.timestamp >= startDate }
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

    private func calculateStats(from events: [(timestamp: Date, type: String)], transitions: [(timestamp: Date, toState: String)]) -> ProductivityStats {
        var stats = ProductivityStats()

        for event in events {
            switch event.type {
            case "tomatoCompleted":
                stats.completedTomatoes += 1
            case "tomatoFailed":
                stats.failedTomatoes += 1
            case "dashCompleted":
                stats.completedDashes += 1
            default:
                break
            }
        }

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
                    break
                }
            }

            currentState = transition.toState
            stateStartTime = transition.timestamp
        }

        let duration = Date().timeIntervalSince(stateStartTime)
        if duration > 0 && stateStartTime != Date.distantPast {
            switch currentState {
            case "work":
                stats.workTime += duration
            case "rest":
                stats.restTime += duration
            default:
                break
            }
        }

        return stats
    }
}
