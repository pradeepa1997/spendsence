import Testing
@testable import SpendCore

@Suite("MessageClassifier")
struct ClassifierTests {
    let classifier = MessageClassifier.standard

    private func classify(_ body: String) -> MessageClassification {
        classifier.classify(Normalizer.normalize(body))
    }

    @Test(arguments: [
        "Your OTP for transaction of LKR 12,500.00 at DARAZ is 482913. Do not share this code.",
        "123456 is your one time password for online banking login.",
        "Your one-time password is 4455",
        "Verification code: 908172. Use this to confirm your card registration.",
    ])
    func ignoresOTP(body: String) {
        #expect(classify(body) == .ignore("OTP"))
    }

    @Test func realDebitWithSecurityFooterIsNotIgnored() {
        let body = "LKR 3,200.00 debited from card ending 1234 at SPAR. Never share your OTP with anyone."
        #expect(classify(body) == .transaction)
    }

    @Test(arguments: [
        "Enjoy 20% off at ODEL with your BankA credit card this weekend!",
        "Spend LKR 10,000 and WIN a trip to Maldives! Promo valid till 30/11.",
        "Special offer: 0% installments on electronics.",
    ])
    func ignoresPromotions(body: String) {
        #expect(classify(body) == .ignore("Promotional"))
    }

    @Test(arguments: [
        "Your credit card statement is ready. Total due LKR 45,320.00. Minimum payment LKR 2,266.00.",
        "Reminder: payment due of LKR 8,500.00 on your card ending 4455 is due on 20/10/26.",
        "Min. due LKR 2,000 by due date 15/10/26.",
    ])
    func dueRemindersAreInformational(body: String) {
        #expect(classify(body) == .informational)
    }

    @Test(arguments: [
        "LKR 2,450.00 debited from card ending 1234 at KEELLS SUPER",
        "Txn of LKR 850.00 at PICKME FOOD using card **9012 approved.",
        "LKR 4,800.00 spent on your credit card ending 3321 at ARPICO.",
    ])
    func debitsAreTransactions(body: String) {
        #expect(classify(body) == .transaction)
        let verbs = classifier.verbText(Normalizer.normalize(body).text)
        #expect(classifier.transactionType(verbText: verbs) == .debit)
    }

    @Test(arguments: [
        "Your A/C xxxx5678 has been credited with LKR 150,000.00",
        "Salary of LKR 185,000.00 received to your A/C ending 5678",
        "Payment of LKR 5,000 received. Total due LKR 40,000.",
    ])
    func creditsAreTransactions(body: String) {
        #expect(classify(body) == .transaction)
        let verbs = classifier.verbText(Normalizer.normalize(body).text)
        #expect(classifier.transactionType(verbText: verbs) == .credit)
    }

    @Test func refundsAreDetected() {
        let verbs = classifier.verbText("Txn of LKR 1,200.00 at UBER using card **9012 reversed.")
        #expect(classifier.transactionType(verbText: verbs) == .refund)
    }

    @Test func amountWithoutVerbIsPassedToParsers() {
        #expect(classify("LKR 1,500.00 at SPAR card ending 7788") == .transaction)
    }

    @Test func noAmountAndNoVerbIsIgnored() {
        #expect(classify("Hi, your parcel has arrived.") == .ignore("Not a transaction"))
    }

    @Test func posIsWordBounded() {
        // "deposit" and "purpose" must not trigger the "pos" debit verb.
        #expect(!classifier.hasTransactionVerb(verbText: "the purpose of the deposit"))
        #expect(classifier.hasTransactionVerb(verbText: "pos purchase at x"))
    }
}
