import Foundation
import Testing
@testable import SpendCore

@Suite("AmountParser")
struct AmountParserTests {
    @Test(arguments: [
        ("1,250.00", "1250"),
        ("1250", "1250"),
        ("1,000,000.5", "1000000.5"),
        ("0.75", "0.75"),
        ("100,000,000", "100000000"),
        (" 2,450.00 ", "2450"),
    ])
    func parsesValidAmounts(input: String, expected: String) {
        #expect(AmountParser.parse(input) == Decimal(string: expected, locale: Locale(identifier: "en_US_POSIX")))
    }

    @Test(arguments: ["0", "0.00", "", "   ", "abc", "12abc", "1.2.3", "-5", ",", ".", "100,000,000.01"])
    func rejectsInvalidAmounts(input: String) {
        #expect(AmountParser.parse(input) == nil)
    }

    @Test func balanceAllowsZero() {
        #expect(AmountParser.parseBalance("0.00") == 0)
        #expect(AmountParser.parseBalance("250,000,000.00") == Decimal(250_000_000))
        #expect(AmountParser.parseBalance("x") == nil)
    }
}
