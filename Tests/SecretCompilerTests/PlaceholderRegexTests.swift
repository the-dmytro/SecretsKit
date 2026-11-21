#if os(macOS)
import XCTest
@testable import SecretCompiler

final class PlaceholderRegexTests: XCTestCase {
    func testNilFallsBackToDefaultPattern() throws {
        let regex = try placeholderRegex(from: nil)
        XCTAssertTrue(isPlaceholder("YOUR_API_KEY", regex: regex))
        XCTAssertTrue(isPlaceholder("__PLACEHOLDER__", regex: regex))
        XCTAssertFalse(isPlaceholder("a-real-value", regex: regex))
    }

    func testEmptyFallsBackToDefaultPattern() throws {
        let regex = try placeholderRegex(from: "")
        XCTAssertTrue(isPlaceholder("REPLACE_ME", regex: regex))
    }

    func testCustomRegexIsUsed() throws {
        let regex = try placeholderRegex(from: "^TEST_")
        XCTAssertTrue(isPlaceholder("TEST_VALUE", regex: regex))
        XCTAssertFalse(isPlaceholder("PROD_VALUE", regex: regex))
    }

    func testInvalidCustomRegexThrowsInsteadOfSilentlyFallingBack() {
        XCTAssertThrowsError(try placeholderRegex(from: "([invalid")) { error in
            guard case SecretCompilerError.invalidPlaceholderRegex(let pattern) = error else {
                return XCTFail("expected invalidPlaceholderRegex, got \(error)")
            }
            XCTAssertEqual(pattern, "([invalid")
        }
    }
}
#endif
