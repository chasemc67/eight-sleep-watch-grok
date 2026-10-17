import Foundation

/// Heating-level arithmetic and the raw-level to Fahrenheit map published by
/// pyEight (`RAW_TO_FAHRENHEIT_MAP` in `pyeight/constants.py`, MIT). The table
/// is empirical: Eight Sleep's level is not linear in degrees.
enum LevelMath {
    static func applying(steps: Int, to level: Int) -> Int {
        let next = level + steps * AppConfig.levelStep
        return min(AppConfig.levelMaximum, max(AppConfig.levelMinimum, next))
    }

    static func levelText(_ level: Int) -> String {
        level > 0 ? "+\(level)" : "\(level)"
    }

    static func fahrenheit(for raw: Int) -> Double {
        let anchors = fahrenheitAnchors
        if raw <= anchors[0].0 { return anchors[0].1 }
        if raw >= anchors[anchors.count - 1].0 { return anchors[anchors.count - 1].1 }
        for index in 1..<anchors.count {
            let upper = anchors[index]
            if raw == upper.0 { return upper.1 }
            if upper.0 > raw {
                let lower = anchors[index - 1]
                let span = Double(upper.0 - lower.0)
                let ratio = Double(raw - lower.0) / span
                return lower.1 + ratio * (upper.1 - lower.1)
            }
        }
        return anchors[anchors.count - 1].1
    }

    static func fahrenheitText(for raw: Int) -> String {
        "\(Int(fahrenheit(for: raw).rounded()))°"
    }

    /// (raw level, degrees Fahrenheit), sorted ascending. From pyEight.
    static let fahrenheitAnchors: [(Int, Double)] = [
        (-100, 55), (-99, 56), (-97, 57), (-95, 58), (-94, 59),
        (-92, 60), (-90, 61), (-86, 62), (-81, 63), (-77, 64),
        (-72, 65), (-68, 66), (-63, 67), (-58, 68), (-54, 69),
        (-49, 70), (-44, 71), (-40, 72), (-35, 73), (-31, 74),
        (-26, 75), (-21, 76), (-18, 77), (-17, 77), (-12, 78),
        (-7, 79), (-3, 80), (1, 81), (4, 82), (7, 83),
        (10, 84), (14, 85), (16, 86), (17, 86), (20, 87),
        (23, 88), (26, 89), (29, 90), (32, 91), (35, 92),
        (38, 93), (41, 94), (44, 95), (48, 96), (51, 97),
        (54, 98), (57, 99), (60, 100), (63, 101), (66, 102),
        (69, 103), (72, 104), (75, 105), (78, 106), (80, 107),
        (81, 107), (85, 108), (88, 109), (92, 110), (100, 111)
    ]
}
