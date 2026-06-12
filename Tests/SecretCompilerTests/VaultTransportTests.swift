#if os(macOS)
import XCTest
@testable import SecretCompiler

final class VaultTransportTests: XCTestCase {
    func testHTTPSAllowed() {
        XCTAssertNoThrow(try validateVaultTransport(address: "https://vault.example.com", allowInsecureHTTP: false))
    }

    func testHTTPRejectedByDefault() {
        XCTAssertThrowsError(try validateVaultTransport(address: "http://vault.local:8200", allowInsecureHTTP: false)) { error in
            guard case SecretCompilerError.vaultInsecureTransport = error else {
                return XCTFail("expected vaultInsecureTransport, got \(error)")
            }
        }
    }

    func testHTTPAllowedWithExplicitFlag() {
        XCTAssertNoThrow(try validateVaultTransport(address: "http://vault.local:8200", allowInsecureHTTP: true))
    }

    func testUnsupportedSchemeRejectedEvenWithFlag() {
        XCTAssertThrowsError(try validateVaultTransport(address: "ftp://vault.local", allowInsecureHTTP: true))
    }

    func testMissingSchemeRejected() {
        XCTAssertThrowsError(try validateVaultTransport(address: "vault.example.com", allowInsecureHTTP: true))
    }
}
#endif
