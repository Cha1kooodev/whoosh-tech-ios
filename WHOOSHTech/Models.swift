import Foundation
import SwiftUI
import UIKit

// MARK: - Статусы ТС

enum ScooterStatus: String, CaseIterable, Codable {
    case available
    case low
    case lost
    case stolen

    var title: String {
        switch self {
        case .available: return "В доступе"
        case .low:       return "Разряжен"
        case .lost:      return "LOST"
        case .stolen:    return "ТС украден"
        }
    }

    var color: Color {
        switch self {
        case .available: return Color(hex: 0x22C55E)
        case .low:       return Color(hex: 0xF59E0B)
        case .lost:      return Color(hex: 0xA78BFA)
        case .stolen:    return Color(hex: 0xEF4444)
        }
    }

    var uiColor: UIColor { UIColor(color) }
}

// MARK: - Самокат

struct Scooter: Identifiable, Equatable {
    let id: String          // полный номер с префиксом, например "6-PSB430"
    let code: String        // номер без префикса, например "PSB430"
    let model: String
    var status: ScooterStatus
    var battery: Int
    let offsetX: Double     // метры восточнее точки привязки
    let offsetY: Double     // метры севернее точки привязки
    var iotOfflineMinutes: Int
}

// MARK: - Детерминированный генератор

struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let x = state >> 33
        return Double(x) / Double(UInt64(1) << 31)
    }

    mutating func int(_ lower: Int, _ upper: Int) -> Int {
        guard upper > lower else { return lower }
        return lower + Int(next() * Double(upper - lower + 1))
    }
}

// MARK: - Каталог самокатов

enum ScooterCatalog {
    static let modelByPrefix: [String: String] = [
        "4": "Ninebot Max Plus (2022)",
        "5": "Ninebot Max Plus Cust",
        "6": "Ninebot SL90 (2024–2025)"
    ]

    static func make() -> [Scooter] {
        var rng = SeededGenerator(seed: 20261111)
        var list: [Scooter] = []

        func insert(_ full: String, dx: Double, dy: Double) {
            let prefix = String(full.prefix(1))
            let code = String(full.dropFirst(2))
            let roll = rng.next()
            let status: ScooterStatus
            if roll > 0.93 { status = .stolen }
            else if roll > 0.85 { status = .lost }
            else if roll > 0.58 { status = .low }
            else { status = .available }

            list.append(Scooter(
                id: full,
                code: code,
                model: modelByPrefix[prefix] ?? "Ninebot Max Plus (2022)",
                status: status,
                battery: rng.int(6, 100),
                offsetX: dx,
                offsetY: dy,
                iotOfflineMinutes: rng.int(35, 620)
            ))
        }

        insert("4-HL44", dx: -260, dy: 240)
        insert("5-AJO41", dx: 180, dy: -310)
        insert("6-PSB430", dx: -420, dy: -180)
        insert("6-KRT918", dx: 360, dy: 420)
        insert("4-QWE7", dx: 520, dy: -60)

        let lengths = [4, 4, 5, 5, 5, 6, 6, 6]
        var attempts = 0
        while list.count < 31 && attempts < 1000 {
            attempts += 1
            let len = lengths[rng.int(0, lengths.count - 1)]
            let code = randomCode(length: len, rng: &rng)
            let prefix = len == 4 ? "4" : (len == 5 ? "5" : "6")
            let full = "\(prefix)-\(code)"
            if list.contains(where: { $0.id == full }) { continue }
            insert(full, dx: Double(rng.int(-700, 700)), dy: Double(rng.int(-700, 700)))
        }

        return list
    }

    /// 4 знака — 2 буквы + 2 цифры
    /// 5 знаков — 3 буквы + 2 цифры
    /// 6 знаков — 3 буквы + 3 цифры
    static func randomCode(length: Int, rng: inout SeededGenerator) -> String {
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
        let digits = Array("0123456789")
        let letterCount = length == 4 ? 2 : 3
        var out = ""
        for _ in 0..<letterCount {
            out.append(letters[rng.int(0, letters.count - 1)])
        }
        for _ in 0..<(length - letterCount) {
            out.append(digits[rng.int(0, digits.count - 1)])
        }
        return out
    }

    static func ago(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) мин назад" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) ч назад" : "\(h) ч \(m) мин назад"
    }
}

// MARK: - Палитра

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    static let appBg = Color(hex: 0x0B0E13)
    static let panel = Color(hex: 0x12161F)
    static let panel2 = Color(hex: 0x171D28)
    static let line = Color(hex: 0x222A38)
    static let textPrimary = Color(hex: 0xE8EDF6)
    static let muted = Color(hex: 0x8B97AB)
    static let accent = Color(hex: 0xFFD400)
}
