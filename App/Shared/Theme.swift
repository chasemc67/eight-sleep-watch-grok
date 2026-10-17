import SwiftUI

enum Theme {
    static let background = Color(red: 0.05, green: 0.07, blue: 0.09)
    static let card = Color(red: 0.12, green: 0.15, blue: 0.18)
    static let cool = Color(red: 0.36, green: 0.64, blue: 0.98)
    static let warm = Color(red: 0.98, green: 0.58, blue: 0.30)

    static func levelColor(_ level: Int?) -> Color {
        guard let level else { return .white }
        if level > 0 { return warm }
        if level < 0 { return cool }
        return .white
    }
}
