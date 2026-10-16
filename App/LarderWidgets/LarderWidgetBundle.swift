import LarderDesign
import SwiftUI
import WidgetKit

@main
struct LarderWidgetBundle: WidgetBundle {
    init() {
        LarderFont.registerBundledFonts()
    }

    var body: some Widget {
        TodayWidget()
    }
}
