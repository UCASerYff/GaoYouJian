import Foundation

@main struct CodeExtractorTests {
    static func main() {
        print("Running CodeExtractorTests...")

        // 1. 6-digit code
        let r1 = CodeExtractor.extract(subject: "验证码: 482910", body: "")
        assert(!r1.isEmpty, "Should find 6-digit code")
        assert(r1[0].value == "482910", "Code value should match")
        assert(r1[0].type == .numeric, "Type should be numeric")

        // 2. 4-digit code
        let r2 = CodeExtractor.extract(subject: "Your code is 7391", body: "")
        assert(r2.contains { $0.value == "7391" }, "Should extract 4-digit code")

        // 3. 8-digit code
        let r3 = CodeExtractor.extract(subject: "OTP: 12345678", body: "")
        assert(r3.contains { $0.value == "12345678" }, "Should extract 8-digit code")

        // 4. Year filter
        let r4 = CodeExtractor.extract(subject: "Copyright 2024 All Rights Reserved", body: "")
        assert(r4.isEmpty, "Years should be filtered out")

        // 5. Phone filter
        let r5 = CodeExtractor.extract(subject: "", body: "Tel: 123456")
        assert(r5.isEmpty, "Phone context should be filtered out")

        // 6. Money filter
        let r6 = CodeExtractor.extract(subject: "", body: "Total amount: $123456")
        assert(r6.isEmpty, "Money context should be filtered out")

        // 7. Zip code filter
        let r7 = CodeExtractor.extract(subject: "", body: "Postal zip code: 90210")
        assert(r7.isEmpty, "Zip code should be filtered out")

        // 8. Alphanumeric code
        let r8 = CodeExtractor.extract(subject: "安全动态码", body: "您的动态码为: 8K2F9")
        assert(r8.contains { $0.value == "8K2F9" && $0.type == .alphanumeric }, "Should extract alphanumeric code")

        // 9. Links in HTML
        let html = "<div>请点击 <a href=\"https://auth.example.com/verify?token=xyz987\">激活账号</a></div>"
        let r9 = CodeExtractor.extract(subject: "请确认邮箱", body: "", html: html)
        assert(r9.contains { $0.type == .link && $0.value.contains("verify") }, "Should extract verification link")

        // 10. Unsubscribe link filter
        let unsubHtml = "<div><a href=\"https://mail.example.com/unsubscribe?token=123\">Unsubscribe</a></div>"
        let r10 = CodeExtractor.extract(subject: "Weekly Newsletter", body: "", html: unsubHtml)
        assert(r10.filter { $0.type == .link }.isEmpty, "Unsubscribe links should be excluded")

        // 11. primaryCode priority
        let mixed = CodeExtractor.primaryCode(subject: "您的验证码为 829103", body: "或者点击链接 https://example.com/confirm")
        assert(mixed?.value == "829103", "Primary code should prefer numeric/alphanumeric code over link")

        print("CodeExtractorTests passed successfully!")
    }
}
