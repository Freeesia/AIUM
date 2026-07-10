import Foundation

enum ScreenshotLaunchConfiguration {
    static var showSettings: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-AIUMShowSettings")
        #else
        false
        #endif
    }
}
