import SwiftUI

/// Use the available page width, not the device family or screen size.
enum MediaCardLayout {
    static let spacing: CGFloat = 20

    static func columnCount(width: CGFloat, typeSize: DynamicTypeSize) -> Int {
        width >= 800 && !typeSize.isAccessibilitySize ? 2 : 1
    }

    static func columns(_ count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: count)
    }
}
