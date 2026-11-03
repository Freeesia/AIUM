import WidgetKit
import SwiftUI

@main
struct AIUMWidgetBundle: WidgetBundle {
    var body: some Widget {
        AIUMSmallWidget()
        if #available(iOS 27.0, *) {
            AIUMShortcutLockScreenWidget()
        } else {
            AIUMLockScreenWidget()
        }
        AIUMMediumWidget()
    }
}
