import Foundation

public enum GameDay {
    static func calendar(for client: ClientKind) -> Calendar {
        // Match maa-cli's server time zone, including the game-day reset.
        let offset = switch client {
        case .official, .bilibili, .txwy: 4
        case .yoStarJP, .yoStarKR: 5
        case .yoStarEN: -11
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: offset * 3600)!
        return calendar
    }

    public static func start(for client: ClientKind, at date: Date) -> Date {
        calendar(for: client).startOfDay(for: date)
    }

    public static func contains(_ date: Date, for client: ClientKind, at now: Date) -> Bool {
        calendar(for: client).isDate(date, inSameDayAs: now)
    }
}

extension ExecutionState {
    /// Rebase daily checkpoints while keeping attempts whose outcome still needs confirmation.
    public func forGameDays(of clients: [ClientConfiguration], at now: Date,
                            calendar: Calendar = .current) -> Self {
        var state = self
        let legacyDate = gameDayStarts == nil && dateKey == ExecutionStateStore.dateKey(for: updatedAt, calendar: calendar)
            ? updatedAt : nil
        var starts: [String: Date] = [:]
        var expiredClients: Set<Substring> = []
        for client in clients {
            let id = client.id.uuidString
            let current = GameDay.start(for: client.kind, at: now)
            let previous = gameDayStarts?[id] ?? legacyDate.map { GameDay.start(for: client.kind, at: $0) }
            starts[id] = current
            if previous != current { expiredClients.insert(Substring(id)) }
        }

        let keys = completedSteps.union(fightResults?.keys.map { $0 } ?? []).union(fightProgress?.keys.map { $0 } ?? [])
        for key in keys {
            let parts = key.split(separator: "/")
            guard parts.count == 4, expiredClients.contains(parts[1]) else { continue }
            state.completedSteps.remove(key)
            guard needsFightConfirmation(key) else {
                state.fightResults?.removeValue(forKey: key)
                state.fightProgress?.removeValue(forKey: key)
                continue
            }
            if var progress = fightProgress?[key] {
                if progress.regular?.status != .unconfirmed || progress.isRegularManuallyHandled {
                    progress.regular = nil
                    progress.regularManuallyHandledAt = nil
                }
                if progress.regular == nil, progress.annihilation?.status != .unconfirmed { progress.annihilation = nil }
                state.fightProgress?[key] = progress
            }
        }
        state.gameDayStarts = starts
        state.dateKey = ExecutionStateStore.dateKey(for: now, calendar: calendar)
        return state
    }
}
