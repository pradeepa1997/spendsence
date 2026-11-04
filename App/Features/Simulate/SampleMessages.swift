import Foundation

struct SampleMessage: Identifiable {
    let title: String
    let sender: String?
    let body: String

    var id: String { title }
}

/// A few messages from the test corpus, for the Simulate tab's "Load sample" menu.
enum SampleMessages {
    static let all: [SampleMessage] = [
        SampleMessage(
            title: "Card purchase (template)",
            sender: "BANKA",
            body: "LKR 2,450.00 debited from card ending 1234 at KEELLS SUPER on 12/09/26. Avl Bal LKR 45,210.50"
        ),
        SampleMessage(
            title: "Account credit (template)",
            sender: "BANKB",
            body: "Your A/C xxxx5678 has been credited with LKR 150,000.00 on 10-09-2026. Bal: LKR 210,000.00"
        ),
        SampleMessage(
            title: "POS txn (template)",
            sender: "BANKC",
            body: "Txn of LKR 850.00 at PICKME FOOD using card **9012 approved. Ref 88213"
        ),
        SampleMessage(
            title: "Reversal → refund",
            sender: "BANKC",
            body: "Txn of LKR 1,200.00 at UBER TRIP using card **9012 reversed. Ref 66001"
        ),
        SampleMessage(
            title: "Generic spend (Rs.)",
            sender: "BANKD",
            body: "You have spent Rs.3,450.75 at CARGILLS FOOD CITY on your card ending 2211. Thank you."
        ),
        SampleMessage(
            title: "ATM withdrawal",
            sender: "BANKD",
            body: "Cash withdrawal of LKR 20,000 from ATM at HNB KANDY. A/C x4567 Avl Bal LKR 80,500.00"
        ),
        SampleMessage(
            title: "Low confidence (no verb)",
            sender: "BANKD",
            body: "LKR 1,500.00 at SPAR KIRULAPONE card ending 7788"
        ),
        SampleMessage(
            title: "OTP (ignored)",
            sender: "BANKA",
            body: "Your OTP for transaction of LKR 12,500.00 at DARAZ is 482913. Do not share this code with anyone."
        ),
        SampleMessage(
            title: "Statement (ignored)",
            sender: "BANKA",
            body: "Your credit card statement is ready. Total due LKR 45,320.00. Minimum payment LKR 2,266.00."
        ),
    ]
}
