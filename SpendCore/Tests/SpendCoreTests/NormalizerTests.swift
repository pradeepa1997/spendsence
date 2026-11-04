import Testing
@testable import SpendCore

@Suite("Normalizer")
struct NormalizerTests {
    @Test(arguments: [
        ("Rs.1,250.00 debited", "LKR 1,250.00 debited"),
        ("Rs 500 paid", "LKR 500 paid"),
        ("rs. 75 spent", "LKR 75 spent"),
        ("RS.75 spent", "LKR 75 spent"),
        ("SLRs 100 spent", "LKR 100 spent"),
        ("LKR. 200 spent", "LKR 200 spent"),
        ("lkr 200 spent", "LKR 200 spent"),
        ("USD 45.99 at X", "USD 45.99 at X"),
    ])
    func unifiesCurrencyTokens(input: String, expected: String) {
        #expect(Normalizer.normalize(input).text == expected)
    }

    @Test func doesNotTouchWordsContainingRs() {
        #expect(Normalizer.normalize("Mrs Perera paid 2 hrs").text == "Mrs Perera paid 2 hrs")
    }

    @Test func keepsSentenceEndingPeriodAfterCurrency() {
        #expect(Normalizer.normalize("Amount shown in LKR.").text == "Amount shown in LKR.")
    }

    @Test(arguments: [
        ("LKR1,250.00 debited", "LKR 1,250.00 debited"),
        ("USD45.99 at X", "USD 45.99 at X"),
        ("Rs.990", "LKR 990"),
    ])
    func insertsSpaceBetweenCurrencyAndAmount(input: String, expected: String) {
        #expect(Normalizer.normalize(input).text == expected)
    }

    @Test func collapsesWhitespaceAndNewlines() {
        let result = Normalizer.normalize("  LKR  2,450.00\n\ndebited\tfrom   card \r\n")
        #expect(result.text == "LKR 2,450.00 debited from card")
    }

    @Test func keepsCommasAndOriginal() {
        let body = "LKR 1,000,000.00\npaid"
        let result = Normalizer.normalize(body)
        #expect(result.text == "LKR 1,000,000.00 paid")
        #expect(result.original == body)
        #expect(result.upper == "LKR 1,000,000.00 PAID")
    }
}
