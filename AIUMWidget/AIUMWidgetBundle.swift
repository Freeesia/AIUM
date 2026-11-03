import WidgetKit
import SwiftUI

@main
struct AIUMWidgetBundle: WidgetBundle {
    var body: some Widget {
        AIUMSmallWidget()
        lockScreenWidget
        AIUMMediumWidget()
    }

    // Widget.body requires one concrete configuration type. Select complete
    // widgets here and use the builder's availability wrapper for a common type.
    private var lockScreenWidget: some Widget {
        if #available(iOS 27.0, *) {
            return WidgetBundleBuilder.buildOptional(
                WidgetBundleBuilder.buildLimitedAvailability(AIUMShortcutLockScreenWidget())
            )
        } else {
            return WidgetBundleBuilder.buildOptional(
                WidgetBundleBuilder.buildLimitedAvailability(AIUMLockScreenWidget())
            )
        }
    }
}
