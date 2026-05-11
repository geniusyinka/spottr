import SwiftUI

enum Theme {
    static let bg          = Color(red: 0.039, green: 0.039, blue: 0.039)   // #0a0a0a
    static let bgElevated  = Color(red: 0.078, green: 0.078, blue: 0.078)   // #141414
    static let card        = Color(red: 0.110, green: 0.110, blue: 0.122)   // #1c1c1f
    static let border      = Color(red: 0.149, green: 0.149, blue: 0.161)   // #262629
    static let text        = Color(red: 0.961, green: 0.961, blue: 0.961)   // #f5f5f5
    static let textDim     = Color(red: 0.604, green: 0.604, blue: 0.604)   // #9a9a9a
    static let accent      = Color(red: 0.133, green: 0.827, blue: 0.655)   // #22d3a7
    static let accentDim   = Color(red: 0.059, green: 0.420, blue: 0.329)   // #0f6b54
    static let warn        = Color(red: 0.961, green: 0.620, blue: 0.043)   // #f59e0b
    static let bad         = Color(red: 0.937, green: 0.267, blue: 0.267)   // #ef4444
}

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 20
}
