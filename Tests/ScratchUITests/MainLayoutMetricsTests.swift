import XCTest
@testable import ScratchUI

/// Règles de taille de la disposition côte à côte (story 4.1 CA 8 ; UX §4.5, §4.6 ; D-38).
final class MainLayoutMetricsTests: XCTestCase {
    // AC8 — UX §4.6 : table, colonne et plateau sur Mac.
    func testMacSizesFollowUX_D38() {
        let minimum = MainLayoutMetrics(width: 960, height: 600, idiom: .mac)
        XCTAssertEqual(minimum.mixerWidth, 240)
        XCTAssertEqual(minimum.columnWidth, 328)
        XCTAssertEqual(minimum.platter, 276)
        let standard = MainLayoutMetrics(width: 1200, height: 760, idiom: .mac)
        XCTAssertEqual(standard.columnWidth, 448)
        XCTAssertEqual(standard.platter, 396)
        XCTAssertEqual(MainLayoutMetrics(width: 3000, height: 2000, idiom: .mac).platter, 560, "P capped at 560")
        XCTAssertEqual(MainLayoutMetrics(width: 3000, height: 2000, idiom: .mac).mixerWidth, 320)
        XCTAssertEqual(minimum.headerHeight + minimum.waveformHeight + minimum.overviewHeight
                       + minimum.transportHeight + minimum.resistanceHeight + minimum.rowSpacings.reduce(0, +),
                       MainLayoutMetrics.macColumnChrome, "the column stack matches the height rule")
        XCTAssertEqual(transportWidth(minimum), minimum.columnWidth, "transport row spans the minimum column")
    }

    // AC8 — UX §4.5 : iPad paysage (hauteurs hors zones sûres).
    func testTabletLandscapeSizesFollowUX() {
        let ipad = MainLayoutMetrics(width: 1180, height: 776, idiom: .tablet)
        XCTAssertEqual(ipad.mixerWidth, 280)
        XCTAssertEqual(ipad.columnWidth, 414)
        XCTAssertEqual(ipad.platter, 362)
        XCTAssertEqual(transportWidth(ipad), 414)
        XCTAssertEqual(MainLayoutMetrics(width: 1024, height: 724, idiom: .tablet).platter, 284)
        XCTAssertEqual(MainLayoutMetrics(width: 1133, height: 700, idiom: .tablet).platter, 338)
        let pro = MainLayoutMetrics(width: 1376, height: 988, idiom: .tablet)
        XCTAssertEqual(pro.mixerWidth, 302.72, accuracy: 0.01)
        XCTAssertEqual(pro.platter, 448)
        XCTAssertEqual(ipad.headerHeight + ipad.waveformHeight + ipad.overviewHeight + ipad.transportHeight
                       + ipad.resistanceHeight + ipad.rowSpacings.reduce(0, +), MainLayoutMetrics.tabletColumnChrome)
    }

    private func transportWidth(_ metrics: MainLayoutMetrics) -> CGFloat {
        metrics.startStopWidth + 2 * metrics.speedSegmentWidth + metrics.setCueWidth + metrics.cueWidth
            + 3 * metrics.transportSpacing
    }
}
