import Foundation

@main struct AliasGeneratorTests {
    static func main() {
        print("Running AliasGeneratorTests...")

        // 1. Gmail dot & plus aliases
        let gmail = "testuser@gmail.com"
        let aliases = AliasGenerator.generate(email: gmail, count: 15, options: AliasRuleOptions(useDots: true, usePlus: true, useGooglemailDomain: true))
        assert(!aliases.isEmpty, "Should generate aliases")
        assert(aliases.allSatisfy { $0.contains("@gmail.com") || $0.contains("@googlemail.com") }, "Domain must be valid")
        // Check dot insertion
        assert(aliases.contains { $0.contains(".") && $0.split(separator: "@")[0].contains(".") }, "Should contain dot trick")

        // 2. Generic email plus addressing
        let outlook = "alice@outlook.com"
        let outAliases = AliasGenerator.generate(email: outlook, count: 5, options: AliasRuleOptions(plusTag: "shop"))
        assert(!outAliases.isEmpty, "Should generate Outlook plus aliases")
        assert(outAliases.contains { $0.contains("+shop") }, "Should contain plus tag")

        // 3. makeServiceAlias
        let serviceAlias1 = AliasGenerator.makeServiceAlias(email: "john@example.com", service: "github.com")
        assert(serviceAlias1 == "john+github@example.com", "Service alias should format correctly, got \(serviceAlias1)")

        let serviceAlias2 = AliasGenerator.makeServiceAlias(email: "john+old@gmail.com", service: "https://v2ex.com/t/123")
        assert(serviceAlias2 == "john+v2ex@gmail.com", "Service alias should strip old tag and URL prefix, got \(serviceAlias2)")

        print("AliasGeneratorTests passed successfully!")
    }
}
