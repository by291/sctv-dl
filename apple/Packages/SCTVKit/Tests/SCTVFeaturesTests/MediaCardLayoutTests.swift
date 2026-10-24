import SwiftUI
import Testing

@testable import SCTVFeatures

struct MediaCardLayoutTests {
    @Test func sharesTheSameBreakpointAcrossWindowWidths() {
        #expect(MediaCardLayout.columnCount(width: 744, typeSize: .large) == 1)
        #expect(MediaCardLayout.columnCount(width: 799, typeSize: .large) == 1)
        #expect(MediaCardLayout.columnCount(width: 800, typeSize: .large) == 2)
        #expect(MediaCardLayout.columnCount(width: 1366, typeSize: .large) == 2)
        #expect(MediaCardLayout.columnCount(width: 3000, typeSize: .large) == 2)
    }

    @Test func accessibilityTextKeepsAReadableSingleColumn() {
        for size in [DynamicTypeSize.accessibility1, .accessibility3, .accessibility5] {
            #expect(MediaCardLayout.columnCount(width: 1366, typeSize: size) == 1)
        }
    }
}
