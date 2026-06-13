#if os(macOS)
import XCTest
@testable import SecretCompiler

final class VaultPathTests: XCTestCase {
    func testVaultRequestPathRejectsUnsafeSegments() {
        let unsafePaths = [
            "team/app?debug=1",
            "team/app#fragment",
            "team//app",
            "team/\u{0007}app"
        ]

        for path in unsafePaths {
            XCTAssertThrowsError(try buildVaultRequestPath(mount: "secret", path: path, kvVersion: 2), "path: \(path)")
        }
    }

    func testVaultURLUsesValidatedPercentEncodedSegments() throws {
        let requestPath = try buildVaultRequestPath(mount: "secret mount", path: "team api/key", kvVersion: 2)
        XCTAssertEqual(requestPath, "secret%20mount/data/team%20api/key")

        let url = try buildVaultURL(address: "https://vault.example.com", requestPath: requestPath)
        XCTAssertEqual(url.absoluteString, "https://vault.example.com/v1/secret%20mount/data/team%20api/key")
    }
}
#endif
