//
//  AppearanceMode.swift
//  CoppiceHabitsThatRest
//
//  The user's theme override: follow the system, or pin warm ivory / deep
//  charcoal. Persisted with @AppStorage and applied once at the window root
//  so sheets inherit it too.
//

import SwiftUI

/// How CoppiceHabitsThatRest resolves light vs. dark.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// `nil` hands the decision back to the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    /// UserDefaults key shared by every `@AppStorage` binding for this setting.
    static let storageKey = "appearanceMode"
}
