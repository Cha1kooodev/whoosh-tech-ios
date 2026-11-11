import Foundation
import SwiftUI
import UIKit
import CoreLocation

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
    let latitude: Double
    let longitude: Double
    var status: ScooterStatus
    var battery: Int
    var iotOfflineMinutes: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
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

// MARK: - Бесконечный мир самокатов

/// Самокаты не хранятся списком, а детерминированно генерируются по сетке
/// координат. Одна и та же клетка всегда даёт одни и те же самокаты,
/// поэтому при возврате на прежнее место картинка не меняется.
enum ScooterWorld {

    /// Размер клетки: ~278 м по широте и ~276 м по долготе (широта Москвы).
    static let latStep = 0.0025
    static let lonStep = 0.00444

    static let modelByPrefix: [String: String] = [
        "4": "Ninebot Max Plus (2022)",
        "5": "Ninebot Max Plus Cust",
        "6": "Ninebot SL90 (2024–2025)"
    ]

    static let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
    static let digits = Array("0123456789")

    // MARK: Прямоугольник на карте

    struct Box: Equatable {
        var minLat: Double
        var maxLat: Double
        var minLon: Double
        var maxLon: Double

        var centerLat: Double { (minLat + maxLat) / 2 }
        var centerLon: Double { (minLon + maxLon) / 2 }
        var spanLat: Double { maxLat - minLat }
        var spanLon: Double { maxLon - minLon }

        func contains(_ other: Box) -> Bool {
            other.minLat >= minLat && other.maxLat <= maxLat &&
            other.minLon >= minLon && other.maxLon <= maxLon
        }

        func expanded(_ factor: Double) -> Box {
            let dLat = spanLat * (factor - 1) / 2
            let dLon = spanLon * (factor - 1) / 2
            return Box(minLat: minLat - dLat, maxLat: maxLat + dLat,
                       minLon: minLon - dLon, maxLon: maxLon + dLon)
        }

        func limited(maxSpanLat: Double, maxSpanLon: Double) -> Box {
            var box = self
            if spanLat > maxSpanLat {
                let half = maxSpanLat / 2
                box.minLat = centerLat - half
                box.maxLat = centerLat + half
            }
            if spanLon > maxSpanLon {
                let half = maxSpanLon / 2
                box.minLon = centerLon - half
                box.maxLon = centerLon + half
            }
            return box
        }
    }

    // MARK: Генерация

    static func scooters(in box: Box, overrides: [String: ScooterStatus]) -> [Scooter] {
        let x0 = Int((box.minLon / lonStep).rounded(.down))
        let x1 = Int((box.maxLon / lonStep).rounded(.down))
        let y0 = Int((box.minLat / latStep).rounded(.down))
        let y1 = Int((box.maxLat / latStep).rounded(.down))
        guard x1 >= x0, y1 >= y0 else { return [] }

        var result: [Scooter] = []
        result.reserveCapacity(256)

        for cy in y0...y1 {
            for cx in x0...x1 {
                let cellHash = hash(cx, cy, 0)
                let density = Double(cellHash & 0xFFFF) / 65_535.0

                let count: Int
                if density < 0.12 { count = 0 }
                else if density < 0.55 { count = 1 }
                else if density < 0.85 { count = 2 }
                else { count = 3 }

                guard count > 0 else { continue }

                for slot in 0..<count {
                    result.append(makeScooter(cx: cx, cy: cy, slot: slot, overrides: overrides))
                }

                if result.count > 1200 { return result }
            }
        }

        return result
    }

    static func makeScooter(cx: Int, cy: Int, slot: Int,
                            overrides: [String: ScooterStatus]) -> Scooter {
        var rng = SeededGenerator(seed: hash(cx, cy, slot + 1))

        let lengthRoll = rng.next()
        let length = lengthRoll < 0.30 ? 4 : (lengthRoll < 0.70 ? 5 : 6)
        let code = makeCode(length: length, rng: &rng)
        let prefix = String(length)
        let full = "\(prefix)-\(code)"

        let statusRoll = rng.next()
        var status: ScooterStatus
        if statusRoll > 0.93 { status = .stolen }
        else if statusRoll > 0.85 { status = .lost }
        else if statusRoll > 0.58 { status = .low }
        else { status = .available }

        let battery = rng.int(6, 100)
        let iotMinutes = rng.int(35, 620)

        let fx = 0.12 + 0.76 * rng.next()
        let fy = 0.12 + 0.76 * rng.next()
        let lat = (Double(cy) + fy) * latStep
        let lon = (Double(cx) + fx) * lonStep

        if let saved = overrides[full] { status = saved }

        return Scooter(
            id: full,
            code: code,
            model: modelByPrefix[prefix] ?? "Ninebot Max Plus (2022)",
            latitude: lat,
            longitude: lon,
            status: status,
            battery: battery,
            iotOfflineMinutes: iotMinutes
        )
    }

    /// 4 знака — 2 буквы + 2 цифры
    /// 5 знаков — 3 буквы + 2 цифры
    /// 6 знаков — 3 буквы + 3 цифры
    static func makeCode(length: Int, rng: inout SeededGenerator) -> String {
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

    static func hash(_ a: Int, _ b: Int, _ c: Int) -> UInt64 {
        var x = UInt64(bitPattern: Int64(a)) &* 0x9E3779B97F4A7C15
        x ^= UInt64(bitPattern: Int64(b)) &* 0xC2B2AE3D27D4EB4F
        x ^= UInt64(bitPattern: Int64(c)) &* 0x165667B19E3779F9
        x ^= x >> 30
        x = x &* 0xBF58476D1CE4E5B9
        x ^= x >> 27
        x = x &* 0x94D049BB133111EB
        x ^= x >> 31
        return x
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
