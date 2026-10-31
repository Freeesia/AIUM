#if os(macOS)
import Security
import XCTest

enum MacSigningTestSupport {
    static func requireProvisionedHost() throws {
        let task = try XCTUnwrap(SecTaskCreateFromSelf(nil))
        let applicationIdentifier = SecTaskCopyValueForEntitlement(
            task, "com.apple.application-identifier" as CFString, nil
        ) as? String
        try XCTSkipIf(
            applicationIdentifier == nil,
            "This integration test requires a provisioned Mac host with Keychain and App Group entitlements."
        )
    }
}
#endif
