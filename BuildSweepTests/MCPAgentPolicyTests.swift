import XCTest
@testable import BuildSweep

final class MCPAgentPolicyTests: XCTestCase {
    func testItemIdentifiersAreOpaqueAndStableWithinAScan() {
        var registry = MCPAgentItemRegistry()
        let generation = UUID()
        let internalPath = "/Users/example/Library/Developer/Xcode/DerivedData/Project-abc"

        let first = registry.opaqueID(for: internalPath, generation: generation)
        let repeated = registry.opaqueID(for: internalPath, generation: generation)

        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first, internalPath)
        XCTAssertEqual(registry.itemID(for: first, generation: generation), internalPath)
    }

    func testChangingScanGenerationInvalidatesPreviouslyIssuedIdentifiers() {
        var registry = MCPAgentItemRegistry()
        let firstGeneration = UUID()
        let token = registry.opaqueID(for: "/private/item", generation: firstGeneration)

        let nextGeneration = UUID()
        registry.beginGeneration(nextGeneration)

        XCTAssertNil(registry.itemID(for: token, generation: firstGeneration))
        XCTAssertNil(registry.itemID(for: token, generation: nextGeneration))
    }

    func testRequestedPageSizeIsBounded() {
        XCTAssertEqual(MCPAgentItemRegistry.boundedPageSize(nil), 25)
        XCTAssertEqual(MCPAgentItemRegistry.boundedPageSize(0), 1)
        XCTAssertEqual(MCPAgentItemRegistry.boundedPageSize(500), 50)
    }
}
