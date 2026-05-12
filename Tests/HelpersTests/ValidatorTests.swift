import XCTest
@testable import SwiftUtilsHelpers

final class ValidatorTests: XCTestCase {

    // MARK: - ValidationResult

    func testValidResult() {
        let result = ValidationResult.valid
        XCTAssertTrue(result.isValid)
        XCTAssertNil(result.failureReason)
    }

    func testInvalidResult() {
        let result = ValidationResult.invalid(reason: "bad")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.failureReason, "bad")
    }

    // MARK: - NonEmpty

    func testNonEmptyPassesWithContent() {
        let rule = ValidationRule<String>.nonEmpty()
        XCTAssertTrue(rule.validate("hello").isValid)
    }

    func testNonEmptyFailsOnEmpty() {
        let rule = ValidationRule<String>.nonEmpty()
        XCTAssertFalse(rule.validate("").isValid)
    }

    func testNonEmptyFailsOnWhitespaceOnly() {
        let rule = ValidationRule<String>.nonEmpty()
        XCTAssertFalse(rule.validate("   \n\t  ").isValid)
    }

    // MARK: - Min/Max Length

    func testMinLengthPasses() {
        let rule = ValidationRule<String>.minLength(3)
        XCTAssertTrue(rule.validate("abc").isValid)
        XCTAssertTrue(rule.validate("abcd").isValid)
    }

    func testMinLengthFails() {
        let rule = ValidationRule<String>.minLength(3)
        XCTAssertFalse(rule.validate("ab").isValid)
    }

    func testMaxLengthPasses() {
        let rule = ValidationRule<String>.maxLength(5)
        XCTAssertTrue(rule.validate("abc").isValid)
        XCTAssertTrue(rule.validate("abcde").isValid)
    }

    func testMaxLengthFails() {
        let rule = ValidationRule<String>.maxLength(5)
        XCTAssertFalse(rule.validate("abcdef").isValid)
    }

    // MARK: - Email

    func testEmailValid() {
        let rule = ValidationRule<String>.email()
        XCTAssertTrue(rule.validate("user@example.com").isValid)
        XCTAssertTrue(rule.validate("first.last+tag@domain.co.uk").isValid)
    }

    func testEmailInvalid() {
        let rule = ValidationRule<String>.email()
        XCTAssertFalse(rule.validate("not-an-email").isValid)
        XCTAssertFalse(rule.validate("missing@").isValid)
        XCTAssertFalse(rule.validate("@no-local.com").isValid)
    }

    // MARK: - URL

    func testURLValid() {
        let rule = ValidationRule<String>.url()
        XCTAssertTrue(rule.validate("https://example.com").isValid)
        XCTAssertTrue(rule.validate("http://sub.domain.org/path?q=1").isValid)
    }

    func testURLInvalid() {
        let rule = ValidationRule<String>.url()
        XCTAssertFalse(rule.validate("not a url").isValid)
        XCTAssertFalse(rule.validate("ftp://files.example.com").isValid)
    }

    // MARK: - Strong Password

    func testStrongPasswordPasses() {
        let rule = ValidationRule<String>.strongPassword()
        XCTAssertTrue(rule.validate("Abcdef1!").isValid)
        XCTAssertTrue(rule.validate("MyP4ssword").isValid)
    }

    func testStrongPasswordFailsTooShort() {
        let rule = ValidationRule<String>.strongPassword(minLength: 8)
        let result = rule.validate("Ab1")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.failureReason, "Password must be at least 8 characters")
    }

    func testStrongPasswordFailsMissingUppercase() {
        let rule = ValidationRule<String>.strongPassword()
        XCTAssertFalse(rule.validate("abcdefg1").isValid)
    }

    func testStrongPasswordFailsMissingDigit() {
        let rule = ValidationRule<String>.strongPassword()
        XCTAssertFalse(rule.validate("Abcdefgh").isValid)
    }

    // MARK: - Pattern

    func testPatternMatches() {
        let rule = ValidationRule<String>.pattern(#"^\d{3}-\d{4}$"#, message: "Invalid phone")
        XCTAssertTrue(rule.validate("555-1234").isValid)
    }

    func testPatternDoesNotMatch() {
        let rule = ValidationRule<String>.pattern(#"^\d{3}-\d{4}$"#, message: "Invalid phone")
        let result = rule.validate("abc")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.failureReason, "Invalid phone")
    }

    // MARK: - Comparable Rules

    func testMinimumPasses() {
        let rule = ValidationRule<Int>.minimum(10)
        XCTAssertTrue(rule.validate(10).isValid)
        XCTAssertTrue(rule.validate(100).isValid)
    }

    func testMinimumFails() {
        let rule = ValidationRule<Int>.minimum(10)
        XCTAssertFalse(rule.validate(9).isValid)
    }

    func testMaximumPasses() {
        let rule = ValidationRule<Int>.maximum(100)
        XCTAssertTrue(rule.validate(100).isValid)
    }

    func testMaximumFails() {
        let rule = ValidationRule<Int>.maximum(100)
        XCTAssertFalse(rule.validate(101).isValid)
    }

    func testRangePasses() {
        let rule = ValidationRule<Double>.range(1.0...10.0)
        XCTAssertTrue(rule.validate(5.0).isValid)
        XCTAssertTrue(rule.validate(1.0).isValid)
        XCTAssertTrue(rule.validate(10.0).isValid)
    }

    func testRangeFails() {
        let rule = ValidationRule<Double>.range(1.0...10.0)
        XCTAssertFalse(rule.validate(0.5).isValid)
        XCTAssertFalse(rule.validate(10.1).isValid)
    }

    // MARK: - Required (Optional)

    func testRequiredPassesWithValue() {
        let rule = ValidationRule<String?>.required()
        XCTAssertTrue(rule.validate("hello").isValid)
    }

    func testRequiredFailsWithNil() {
        let rule = ValidationRule<String?>.required()
        XCTAssertFalse(rule.validate(nil).isValid)
    }

    // MARK: - Custom Predicate

    func testCustomPredicatePasses() {
        let even = ValidationRule<Int>.predicate("Must be even") { $0 % 2 == 0 }
        XCTAssertTrue(even.validate(4).isValid)
    }

    func testCustomPredicateFails() {
        let even = ValidationRule<Int>.predicate("Must be even") { $0 % 2 == 0 }
        let result = even.validate(3)
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.failureReason, "Must be even")
    }

    // MARK: - Validator Composition

    func testValidatorAllPass() {
        var validator = Validator<String>()
        validator.add(.nonEmpty())
        validator.add(.minLength(3))
        validator.add(.email())

        XCTAssertTrue(validator.isValid("user@example.com"))
        XCTAssertEqual(validator.errors(for: "user@example.com"), [])
    }

    func testValidatorCollectsAllErrors() {
        var validator = Validator<String>()
        validator.add(.nonEmpty())
        validator.add(.minLength(5))
        validator.add(.email())

        let errors = validator.errors(for: "ab")
        // minLength and email should fail; nonEmpty should pass
        XCTAssertEqual(errors.count, 2)
    }

    func testValidatorFirstError() {
        var validator = Validator<String>()
        validator.add(.nonEmpty())
        validator.add(.minLength(5))

        let result = validator.firstError(for: "")
        XCTAssertEqual(result, .invalid(reason: "This field is required"))
    }

    func testValidatorFirstErrorReturnsValidWhenAllPass() {
        var validator = Validator<String>()
        validator.add(.nonEmpty())
        validator.add(.minLength(3))

        XCTAssertEqual(validator.firstError(for: "hello"), .valid)
    }

    func testValidatorChainingWithAdding() {
        let validator = Validator<String>()
            .adding(.nonEmpty())
            .adding(.minLength(3))
            .adding(.maxLength(50))

        XCTAssertTrue(validator.isValid("hello"))
        XCTAssertFalse(validator.isValid(""))
        XCTAssertFalse(validator.isValid("ab"))
    }
}
