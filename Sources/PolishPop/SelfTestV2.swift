import Foundation

enum SelfTest {
    static func run() -> Bool {
        var failures: [String] = []

        let unicodeValue: JSONValue = .object([
            "id": .number(7),
            "text": .string("Hello 世界 👋"),
            "enabled": .bool(true)
        ])
        let roundTrip = try? JSONDecoder().decode(
            JSONValue.self,
            from: JSONEncoder().encode(unicodeValue)
        )
        check(roundTrip == unicodeValue, "JSONL value round trip", failures: &failures)

        let accountPayload: JSONValue = .object([
            "account": .object([
                "type": .string("chatgpt"),
                "email": .string("person@example.com"),
                "planType": .string("plus")
            ]),
            "requiresOpenaiAuth": .bool(true)
        ])
        let account = CodexAppServerClient.parseAccount(from: accountPayload)
        check(account?.planType == "plus", "ChatGPT account parser", failures: &failures)

        let apiAccountPayload: JSONValue = .object([
            "account": .object(["type": .string("apiKey")]),
            "requiresOpenaiAuth": .bool(true)
        ])
        check(
            CodexAppServerClient.parseAccount(from: apiAccountPayload) == nil,
            "API-key account rejection",
            failures: &failures
        )

        let structured = try? CodexAppServerClient.extractAnswer(from: #"{"answer":"Polished message"}"#)
        check(structured == "Polished message", "structured output parser", failures: &failures)

        let invalidPlain = try? CodexAppServerClient.extractAnswer(from: "Unstructured message")
        check(invalidPlain == nil, "unstructured output rejection", failures: &failures)

        check(
            CodexAppServerClient.baseInstructions.contains("Do not use tools"),
            "no-tools base instruction",
            failures: &failures
        )

        let developer = CodexAppServerClient.developerInstructions(for: .professional, purpose: .email)
        check(
            developer.contains("names, dates, amounts") && developer.contains("Never invent missing facts"),
            "business-facts preservation prompt",
            failures: &failures
        )

        if failures.isEmpty {
            print("PolishPop self-test: 7 checks passed")
            return true
        }

        for failure in failures {
            fputs("FAIL: \(failure)\n", stderr)
        }
        return false
    }

    private static func check(_ condition: Bool, _ name: String, failures: inout [String]) {
        if !condition { failures.append(name) }
    }
}
