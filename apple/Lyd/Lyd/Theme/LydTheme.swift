import SwiftUI

/// Windows Lyd branding from `FlacPlayer/Skins/MainSkin.xaml` + `LydWebsite/Styles/style.css`.
enum LydTheme {
    /// `PrimaryPurple` — `#6a49d6`
    static let primary = Color(red: 106 / 255, green: 73 / 255, blue: 214 / 255)

    /// `SecondaryPurple` — `#5a38d6` (hover / pressed on Windows)
    static let secondary = Color(red: 90 / 255, green: 56 / 255, blue: 214 / 255)

    /// Windows chrome background `StandardGray` — `#1E1E1E`
    static let chrome = Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255)

    /// Windows `Foreground` — `#F4F4F5`
    static let onChrome = Color(red: 244 / 255, green: 244 / 255, blue: 245 / 255)
}

extension ShapeStyle where Self == Color {
    static var lydAccent: Color { LydTheme.primary }
}
