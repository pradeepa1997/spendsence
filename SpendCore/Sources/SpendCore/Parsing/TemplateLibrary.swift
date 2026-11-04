import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pradeepa.spendsense", category: "TemplateLibrary")

/// A template with its regex compiled once.
public struct CompiledTemplate: Sendable {
    public let template: ParserTemplate
    let regex: CompiledRegex
    /// Named groups present in the pattern; only these are queried on a match.
    let groupNames: Set<String>
    let debitKeywords: CompiledRegex
    let creditKeywords: CompiledRegex
}

public struct TemplateLibrary: Sendable {
    public let templates: [CompiledTemplate]

    /// Templates from `Resources/templates.json`.
    public static let bundled = TemplateLibrary.loadBundled()
    public static let empty = TemplateLibrary(templates: [])

    private static let groupNamePattern = CompiledRegex(#"\(\?<([A-Za-z][A-Za-z0-9]*)>"#, caseInsensitive: false)

    /// Compiles every template. Invalid ones are logged and skipped, never fatal.
    public init(templates: [ParserTemplate]) {
        self.templates = templates.compactMap(Self.compile)
    }

    public init(jsonData: Data) throws {
        self.init(templates: try JSONDecoder().decode([ParserTemplate].self, from: jsonData))
    }

    /// Templates whose `senderHints` match the sender (case-insensitive substring, either way) first,
    /// then all remaining templates in file order.
    public func ordered(for sender: String?) -> [CompiledTemplate] {
        guard let sender = sender?.lowercased().trimmingCharacters(in: .whitespaces), !sender.isEmpty else {
            return templates
        }
        func matches(_ compiled: CompiledTemplate) -> Bool {
            compiled.template.senderHints.contains { hint in
                let hint = hint.lowercased()
                return !hint.isEmpty && (sender.contains(hint) || hint.contains(sender))
            }
        }
        return templates.filter(matches) + templates.filter { !matches($0) }
    }

    static func compile(_ template: ParserTemplate) -> CompiledTemplate? {
        let regex: CompiledRegex
        do {
            regex = try CompiledRegex(validating: template.pattern)
        } catch {
            logger.error("Skipping template \(template.id, privacy: .public): invalid pattern (\(error.localizedDescription, privacy: .public))")
            return nil
        }
        let names = Set(
            groupNamePattern.matches(in: template.pattern).compactMap {
                CompiledRegex.substring(of: template.pattern, range: $0.range(at: 1))
            }
        )
        guard names.contains("amount") else {
            logger.error("Skipping template \(template.id, privacy: .public): no (?<amount>…) group")
            return nil
        }
        return CompiledTemplate(
            template: template,
            regex: regex,
            groupNames: names,
            debitKeywords: .keywords(template.debitKeywords, wholeWord: true),
            creditKeywords: .keywords(template.creditKeywords, wholeWord: true)
        )
    }

    private static func loadBundled() -> TemplateLibrary {
        guard let url = Bundle.module.url(forResource: "templates", withExtension: "json") else {
            logger.error("templates.json missing from bundle")
            return .empty
        }
        do {
            return try TemplateLibrary(jsonData: Data(contentsOf: url))
        } catch {
            logger.error("Could not load templates.json: \(error.localizedDescription, privacy: .public)")
            return .empty
        }
    }
}
