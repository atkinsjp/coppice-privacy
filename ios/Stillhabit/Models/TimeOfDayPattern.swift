//
//  TimeOfDayPattern.swift
//  Stillhabit
//
//  A soft, four-part reading of when a habit tends to happen.
//  Observational language only — never a target, never a judgement.
//

import Foundation

/// The part of the day a completion falls into.
/// Morning 5–11, Afternoon 12–16, Evening 17–20, Night 21–4.
enum TimeOfDayPattern: String, CaseIterable, Hashable, Sendable {
    case morning
    case afternoon
    case evening
    case night

    /// Buckets an hour-of-day (0...23) into its part of the day.
    init(hour: Int) {
        switch hour {
        case 5...11: self = .morning
        case 12...16: self = .afternoon
        case 17...20: self = .evening
        default: self = .night
        }
    }

    /// Capitalized name used in copy, e.g. "Morning".
    var displayName: String {
        switch self {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        case .night: return "Night"
        }
    }

    /// Lowercase name for use mid-sentence, e.g. "…in the morning."
    var inlineName: String { displayName.lowercased() }

    /// A quiet SF Symbol matching the light of that hour.
    var symbolName: String {
        switch self {
        case .morning: return "sun.haze.fill"
        case .afternoon: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }

    /// Natural order through the day, used to break tallying ties.
    var order: Int {
        switch self {
        case .morning: return 0
        case .afternoon: return 1
        case .evening: return 2
        case .night: return 3
        }
    }
}
