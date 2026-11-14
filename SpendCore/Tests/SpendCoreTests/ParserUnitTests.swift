import Foundation
import Testing
@testable import SpendCore

@Suite("Templates, generic parser, merchant cleaning")
struct ParserUnitTests {
    @Test func bundledTemplatesLoad() {
        let ids = TemplateLibrary.bundled.templates.map(\.template.id)
        #expect(ids == [
            "hnb_card_alert", "hnb_account", "dfcc_card", "dfcc_account", "ndb_card",
            "seylan_account", "seylan_card", "peoples_account",
            "generic_card_purchase", "generic_account_credit", "generic_pos_txn",
        ])
    }

    @Test func monthNamesParseInAnyCase() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let received = Date(timeIntervalSince1970: 1_794_700_000) // 2026-11-14T~23:46Z
        let upper = DateParsing.parse("14/NOV/2026 17:46", format: "dd/MMM/yyyy HH:mm", receivedAt: received, timeZone: utc)
        let title = DateParsing.parse("14/Nov/2026 17:46", format: "dd/MMM/yyyy HH:mm", receivedAt: received, timeZone: utc)
        #expect(upper == title)
        #expect(upper != received)
    }

    @Test func twelveHourTimesParse() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let received = Date(timeIntervalSince1970: 1_794_700_000)
        let pm = DateParsing.parse("09/11/2026 06:24:54 PM", format: "dd/MM/yyyy hh:mm:ss a", receivedAt: received, timeZone: utc)
        let expected = try #require(ISO8601DateFormatter().date(from: "2026-11-09T18:24:54Z"))
        #expect(pm == expected)
    }

    @Test func cardDescriptorsAreTidied() {
        #expect(MerchantCleaner.clean("CIBMART PILIYANDALA PILIYANDALA WPLK") == "Cibmart Piliyandala")
        #expect(MerchantCleaner.clean("DARAZ LK") == "Daraz LK")
        #expect(MerchantCleaner.clean("FRESH MILK") == "Fresh Milk")
    }

    @Test func shortAccountEndingsAreKept() {
        #expect(TemplateParser.lastFourDigits("95") == "95")
        #expect(TemplateParser.lastFourDigits("1234567") == "4567")
        #expect(TemplateParser.lastFourDigits("5") == nil)
    }

    @Test func invalidTemplatesAreSkippedNotFatal() {
        let library = TemplateLibrary(templates: [
            ParserTemplate(id: "broken", bankName: "X", senderHints: [], pattern: "(?<amount>[", debitKeywords: [], creditKeywords: []),
            ParserTemplate(id: "no_amount", bankName: "X", senderHints: [], pattern: "LKR (\\d+)", debitKeywords: [], creditKeywords: []),
            ParserTemplate(id: "ok", bankName: "X", senderHints: [], pattern: "LKR (?<amount>\\d+)", debitKeywords: [], creditKeywords: []),
        ])
        #expect(library.templates.map(\.template.id) == ["ok"])
    }

    @Test func senderHintsOrderTemplates() {
        let ordered = TemplateLibrary.bundled.ordered(for: "BankC").map(\.template.id)
        #expect(ordered.first == "generic_pos_txn")
        #expect(ordered.count == TemplateLibrary.bundled.templates.count)
        let hnbFirst: [String] = TemplateLibrary.bundled.ordered(for: "HNB").prefix(2).map(\.template.id)
        #expect(hnbFirst == ["hnb_card_alert", "hnb_account"])
    }

    @Test(arguments: [
        ("KEELLS SUPER", "Keells Super"),
        ("KFC MAJESTIC CITY", "KFC Majestic City"),
        ("  abans   plc. ", "Abans Plc"),
        ("NETFLIX.COM", "Netflix.com"),
        ("HNB KANDY,", "HNB Kandy"),
    ])
    func cleansMerchants(raw: String, expected: String) {
        #expect(MerchantCleaner.clean(raw) == expected)
    }

    @Test(arguments: ["", "  ", "12345", "**** 9012", "."])
    func rejectsNonMerchants(raw: String) {
        #expect(MerchantCleaner.clean(raw) == nil)
    }

    @Test func genericSkipsBalanceAmounts() {
        let found = GenericParser.findAmount(in: "Avl Bal LKR 45,000.00. LKR 2,000.00 debited")
        #expect(found?.amount == 2000)
    }

    @Test func genericMerchantSkipsOwnAccount() {
        #expect(GenericParser.findMerchant(in: "LKR 500 credited to your A/C ending 1234 at CDM COLOMBO.") == "CDM Colombo")
    }

    @Test func dateOnlyFormatsKeepReceivedTimeOfDay() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let received = Date(timeIntervalSince1970: 1_789_200_000) // 2026-09-12T08:00:00Z
        let parsed = DateParsing.parse("12/09/26", format: "dd/MM/yy", receivedAt: received, timeZone: utc)
        #expect(parsed == received)
        let yesterday = DateParsing.parse("11/09/26", format: "dd/MM/yy", receivedAt: received, timeZone: utc)
        #expect(yesterday == received.addingTimeInterval(-86_400))
    }

    @Test func implausibleDatesFallBackToReceivedAt() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let received = Date(timeIntervalSince1970: 1_789_200_000)
        #expect(DateParsing.parse("30/12/26", format: "dd/MM/yy", receivedAt: received, timeZone: utc) == received)
        #expect(DateParsing.parse("garbage", format: "dd/MM/yy", receivedAt: received, timeZone: utc) == received)
    }
}
