import Foundation
import Testing
@testable import SpendCore

struct SMSFixture: Decodable, Sendable, CustomTestStringConvertible {
    struct Expectation: Decodable, Sendable {
        let outcome: String
        let amount: String?
        let currency: String?
        let type: String?
        let merchant: String?
        let last4: String?
        let balanceAfter: String?
    }

    let id: String
    let sender: String?
    let body: String
    let expect: Expectation

    var testDescription: String { id }

    static let loadResult: Result<[SMSFixture], any Error> = Result {
        guard let url = Bundle.module.url(forResource: "sms_samples", withExtension: "json", subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([SMSFixture].self, from: Data(contentsOf: url))
    }

    static var all: [SMSFixture] { (try? loadResult.get()) ?? [] }
}

@Suite("Pipeline fixture corpus")
struct PipelineFixtureTests {
    /// 2026-09-12T08:00:00Z — fixed so template dates in the corpus are plausible.
    static let receivedAt = Date(timeIntervalSince1970: 1_789_200_000)

    let pipeline = ParsingPipeline()

    @Test func corpusLoads() throws {
        let fixtures = try SMSFixture.loadResult.get()
        #expect(fixtures.count >= 20)
        #expect(Set(fixtures.map(\.id)).count == fixtures.count, "fixture ids must be unique")
    }

    @Test(arguments: SMSFixture.all)
    func fixture(_ fixture: SMSFixture) {
        let outcome = pipeline.run(body: fixture.body, sender: fixture.sender, receivedAt: Self.receivedAt)
        let id = fixture.id

        let outcomeName: String
        let parsed: ParsedTransaction?
        switch outcome {
        case .parsed(let p): outcomeName = "parsed"; parsed = p
        case .ignored: outcomeName = "ignored"; parsed = nil
        case .needsReview(let p, _): outcomeName = "needsReview"; parsed = p
        }
        #expect(outcomeName == fixture.expect.outcome, "[\(id)] got \(outcome)")

        let e = fixture.expect
        let expectsFields = [e.amount, e.currency, e.type, e.merchant, e.last4, e.balanceAfter].contains { $0 != nil }
        guard expectsFields else { return }
        guard let p = parsed else {
            Issue.record("[\(id)] expected a parsed transaction, got \(outcome)")
            return
        }
        if let amount = e.amount { #expect(p.amount == Self.decimal(amount), "[\(id)] amount") }
        if let currency = e.currency { #expect(p.currency == currency, "[\(id)] currency") }
        if let type = e.type { #expect(p.type.rawValue == type, "[\(id)] type") }
        if let merchant = e.merchant { #expect(p.merchant == merchant, "[\(id)] merchant") }
        if let last4 = e.last4 { #expect(p.last4 == last4, "[\(id)] last4") }
        if let balance = e.balanceAfter { #expect(p.balanceAfter == Self.decimal(balance), "[\(id)] balanceAfter") }
    }

    @Test func everyTemplateIsCoveredByAFixture() {
        let matched = Set(SMSFixture.all.compactMap { fixture -> String? in
            switch pipeline.run(body: fixture.body, sender: fixture.sender, receivedAt: Self.receivedAt) {
            case .parsed(let p): p.matchedTemplateID
            case .needsReview(let p, _): p?.matchedTemplateID
            case .ignored: nil
            }
        })
        for compiled in TemplateLibrary.bundled.templates {
            #expect(matched.contains(compiled.template.id), "template \(compiled.template.id) has no fixture")
        }
    }

    @Test func parsedOutcomesAlwaysHaveADate() {
        for fixture in SMSFixture.all {
            if case .parsed(let p) = pipeline.run(body: fixture.body, sender: fixture.sender, receivedAt: Self.receivedAt) {
                #expect(p.occurredAt != nil, "[\(fixture.id)]")
            }
        }
    }

    static func decimal(_ string: String) -> Decimal? {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
    }
}
