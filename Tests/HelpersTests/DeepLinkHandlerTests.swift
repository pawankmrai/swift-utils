import XCTest
@testable import SwiftUtils

final class DeepLinkHandlerTests: XCTestCase {
    
    var sut: DeepLinkHandler!
    
    override func setUp() {
        super.setUp()
        sut = DeepLinkHandler()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Basic Routing
    
    func testSimplePatternMatches() {
        var matched = false
        sut.register("home") { _ in matched = true }
        
        let url = URL(string: "myapp://home")!
        let result = sut.handle(url)
        
        XCTAssertTrue(matched)
        if case .matched(let pattern) = result {
            XCTAssertEqual(pattern, "home")
        } else {
            XCTFail("Expected matched result")
        }
    }
    
    func testMultiSegmentPatternMatches() {
        var matched = false
        sut.register("settings/notifications") { _ in matched = true }
        
        let url = URL(string: "myapp://settings/notifications")!
        sut.handle(url)
        
        XCTAssertTrue(matched)
    }
    
    func testNoMatchReturnsNoMatch() {
        sut.register("home") { _ in }
        
        let url = URL(string: "myapp://unknown")!
        let result = sut.handle(url)
        
        if case .noMatch = result {
            // Expected
        } else {
            XCTFail("Expected noMatch result")
        }
    }
    
    // MARK: - Path Parameters
    
    func testSinglePathParameter() {
        var capturedId: String?
        sut.register("product/:id") { context in
            capturedId = context.pathParameters["id"]
        }
        
        let url = URL(string: "myapp://product/42")!
        sut.handle(url)
        
        XCTAssertEqual(capturedId, "42")
    }
    
    func testMultiplePathParameters() {
        var capturedUserId: String?
        var capturedPostId: String?
        sut.register("user/:userId/posts/:postId") { context in
            capturedUserId = context.pathParameters["userId"]
            capturedPostId = context.pathParameters["postId"]
        }
        
        let url = URL(string: "myapp://user/abc/posts/123")!
        sut.handle(url)
        
        XCTAssertEqual(capturedUserId, "abc")
        XCTAssertEqual(capturedPostId, "123")
    }
    
    // MARK: - Query Parameters
    
    func testQueryParametersExtracted() {
        var capturedQuery: [String: String] = [:]
        sut.register("product/:id") { context in
            capturedQuery = context.queryParameters
        }
        
        let url = URL(string: "myapp://product/42?ref=push&campaign=summer")!
        sut.handle(url)
        
        XCTAssertEqual(capturedQuery["ref"], "push")
        XCTAssertEqual(capturedQuery["campaign"], "summer")
    }
    
    func testEmptyQueryParameterValue() {
        var capturedQuery: [String: String] = [:]
        sut.register("home") { context in
            capturedQuery = context.queryParameters
        }
        
        let url = URL(string: "myapp://home?flag")!
        sut.handle(url)
        
        XCTAssertEqual(capturedQuery["flag"], "")
    }
    
    // MARK: - Wildcards
    
    func testWildcardMatchesAnySegment() {
        var matched = false
        sut.register("feed/*/comments") { _ in matched = true }
        
        let url = URL(string: "myapp://feed/anything/comments")!
        sut.handle(url)
        
        XCTAssertTrue(matched)
    }
    
    // MARK: - Scheme Filtering
    
    func testAllowedSchemeAccepted() {
        sut = DeepLinkHandler(allowedSchemes: ["myapp"])
        var matched = false
        sut.register("home") { _ in matched = true }
        
        let url = URL(string: "myapp://home")!
        sut.handle(url)
        
        XCTAssertTrue(matched)
    }
    
    func testDisallowedSchemeRejected() {
        sut = DeepLinkHandler(allowedSchemes: ["myapp"])
        var matched = false
        sut.register("home") { _ in matched = true }
        
        let url = URL(string: "otherapp://home")!
        let result = sut.handle(url)
        
        XCTAssertFalse(matched)
        if case .noMatch = result {
            // Expected
        } else {
            XCTFail("Expected noMatch for disallowed scheme")
        }
    }
    
    // MARK: - Fallback
    
    func testFallbackCalledOnNoMatch() {
        var fallbackCalled = false
        sut.register("home") { _ in }
        sut.setFallback { _ in fallbackCalled = true }
        
        let url = URL(string: "myapp://unknown/path")!
        sut.handle(url)
        
        XCTAssertTrue(fallbackCalled)
    }
    
    // MARK: - canHandle
    
    func testCanHandleReturnsTrueForMatchingURL() {
        sut.register("product/:id") { _ in }
        
        let url = URL(string: "myapp://product/99")!
        XCTAssertTrue(sut.canHandle(url))
    }
    
    func testCanHandleReturnsFalseForNonMatchingURL() {
        sut.register("product/:id") { _ in }
        
        let url = URL(string: "myapp://unknown")!
        XCTAssertFalse(sut.canHandle(url))
    }
    
    // MARK: - Route Priority
    
    func testFirstRegisteredRouteWins() {
        var firstMatched = false
        var secondMatched = false
        
        sut.register("item/:id") { _ in firstMatched = true }
        sut.register("item/:name") { _ in secondMatched = true }
        
        let url = URL(string: "myapp://item/hello")!
        sut.handle(url)
        
        XCTAssertTrue(firstMatched)
        XCTAssertFalse(secondMatched)
    }
    
    // MARK: - Context Properties
    
    func testContextContainsOriginalURL() {
        var capturedURL: URL?
        sut.register("page") { context in
            capturedURL = context.url
        }
        
        let url = URL(string: "myapp://page?foo=bar")!
        sut.handle(url)
        
        XCTAssertEqual(capturedURL, url)
    }
    
    func testContextContainsScheme() {
        var capturedScheme: String?
        sut.register("page") { context in
            capturedScheme = context.scheme
        }
        
        let url = URL(string: "myapp://page")!
        sut.handle(url)
        
        XCTAssertEqual(capturedScheme, "myapp")
    }
    
    // MARK: - Registered Patterns
    
    func testRegisteredPatternsReturnsAllPatterns() {
        sut.register("home") { _ in }
        sut.register("product/:id") { _ in }
        sut.register("user/:uid/settings") { _ in }
        
        XCTAssertEqual(sut.registeredPatterns, ["home", "product/:id", "user/:uid/settings"])
    }
    
    // MARK: - Case Insensitivity
    
    func testLiteralMatchingIsCaseInsensitive() {
        var matched = false
        sut.register("Settings/Profile") { _ in matched = true }
        
        let url = URL(string: "myapp://settings/profile")!
        sut.handle(url)
        
        XCTAssertTrue(matched)
    }
}
