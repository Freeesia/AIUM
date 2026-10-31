import WidgetKit
import SwiftUI

@main
struct AIUMWidgetBundle: WidgetBundle {
    var body: some Widget {
        AIUMSmallWidget()
        #if os(iOS)
        AIUMLockScreenWidget()
        #endif
        AIUMMediumWidget()
    }
}
