import XCTest
@testable import SwiftUtilsNetworking

final class JSONValueTests: XCTestCase {

    private let sample = Data("""
    {
      "id": 42,
      "name": "Pawan",
      "active": true,
      "score": 9.5,
      "nickname": null,
      "tags": ["ios", "swift"],
      "addresses": [{ "city": "Bengaluru" }, { "city": "Pune" }]
    }
    """.utf8)

    // MARK: - Decoding

    func testDecodesAllValueKinds() throws {
        let json = try JSONValue(data: sample)
        XCTAssertEqual(json["id"], .number(42))
        XCTAssertEqual(json["name"], .string("Pawan"))
        XCTAssertEqual(json["active"], .bool(true))
        XCTAssertEqual(json["score"], .number(9.5))
        XCTAssertEqual(json["nickname"], .null)
        XCTAssertEqual(json["tags"], ["ios", "swift"])
    }

    func testBooleansAreNotDecodedAsNumbers() throws {
        let json = try JSONValue(data: Data("[true, 1, 0, false]".utf8))
        XCTAssertEqual(json, [true, 1, 0, false])
    }

    func testDecodesTopLevelFragments() throws {
        XCTAssertEqual(try JSONValue(data: Data("\"hi\"".utf8)), "hi")
        XCTAssertEqual(try JSONValue(data: Data("3".utf8)), 3)
        XCTAssertEqual(try JSONValue(data: Data("null".utf8)), .null)
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try JSONValue(data: Data("{oops".utf8)))
    }

    // MARK: - Accessors

    func testTypedAccessors() throws {
        let json = try JSONValue(data: sample)
        XCTAssertEqual(json["id"]?.intValue, 42)
        XCTAssertNil(json["score"]?.intValue)
        XCTAssertEqual(json["score"]?.doubleValue, 9.5)
        XCTAssertEqual(json["name"]?.stringValue, "Pawan")
        XCTAssertEqual(json["active"]?.boolValue, true)
        XCTAssertEqual(json["tags"]?.arrayValue?.count, 2)
        XCTAssertEqual(json.objectValue?.count, 7)
        XCTAssertTrue(json["nickname"]?.isNull ?? false)
        XCTAssertNil(json["name"]?.doubleValue)
    }

    func testIndexSubscriptBounds() {
        let json: JSONValue = [1, 2]
        XCTAssertEqual(json[1], 2)
        XCTAssertNil(json[2])
        XCTAssertNil(json[-1])
        XCTAssertNil(JSONValue.string("x")[0])
    }

    func testPathSubscript() throws {
        let json = try JSONValue(data: sample)
        XCTAssertEqual(json[path: "addresses.1.city"], "Pune")
        XCTAssertEqual(json[path: "tags.0"], "ios")
        XCTAssertEqual(json[path: "name"], "Pawan")
        XCTAssertNil(json[path: "addresses.5.city"])
        XCTAssertNil(json[path: "missing.deep.key"])
    }

    func testPathTreatsNumericKeyOnObjectAsKey() {
        let json: JSONValue = ["2024": ["total": 10]]
        XCTAssertEqual(json[path: "2024.total"], 10)
    }

    // MARK: - Round-tripping

    func testEncodeDecodeRoundTrip() throws {
        let original = try JSONValue(data: sample)
        let reparsed = try JSONValue(data: original.data())
        XCTAssertEqual(original, reparsed)
    }

    func testDescriptionIsSortedCompactJSON() {
        let json: JSONValue = ["b": 1, "a": [true, nil], "url": "https://x.io/a"]
        XCTAssertEqual(json.description, #"{"a":[true,null],"b":1,"url":"https://x.io/a"}"#)
    }

    func testCodableModelBridging() throws {
        struct User: Codable, Equatable { let id: Int; let name: String }
        let user = User(id: 7, name: "Ana")
        let json = try JSONValue(encoding: user)
        XCTAssertEqual(json, ["id": 7, "name": "Ana"])
        XCTAssertEqual(try json.decode(User.self), user)
    }

    func testEmbeddedInStronglyTypedModel() throws {
        struct Event: Decodable { let name: String; let properties: JSONValue }
        let data = Data(#"{"name":"purchase","properties":{"amount":19.99,"items":["a"]}}"#.utf8)
        let event = try JSONDecoder().decode(Event.self, from: data)
        XCTAssertEqual(event.properties["amount"]?.doubleValue, 19.99)
        XCTAssertEqual(event.properties[path: "items.0"], "a")
    }

    // MARK: - Merging

    func testDeepMerge() {
        let base: JSONValue = ["theme": ["color": "blue", "size": 12], "flags": ["a"]]
        let overlay: JSONValue = ["theme": ["size": 14], "flags": ["b"], "new": true]
        let merged = base.merging(overlay)
        XCTAssertEqual(merged, ["theme": ["color": "blue", "size": 14], "flags": ["b"], "new": true])
    }

    func testMergeNonObjectReplaces() {
        XCTAssertEqual(JSONValue.number(1).merging("x"), "x")
    }
}
