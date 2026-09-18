import Testing
import Foundation
@testable import OpenStreamApple

@Suite("AppleMediaServerLibraryStore Tests")
@MainActor
struct AppleMediaServerLibraryStoreTests {

    @Test("Reference parse round trips mediaID and rejects garbage")
    func testReferenceParse() {
        let sourceID = UUID()
        let itemID = "item:with:colons"
        let ref = AppleMediaServerItemReference(sourceID: sourceID, itemID: itemID)
        let mediaID = ref.mediaID
        #expect(mediaID == "ms:\(sourceID.uuidString.lowercased()):item:with:colons")
        
        let parsed = AppleMediaServerItemReference.parse(mediaID)
        #expect(parsed == ref)
        
        #expect(AppleMediaServerItemReference.parse("ms:invalid-uuid:item") == nil)
        #expect(AppleMediaServerItemReference.parse("ms:\(sourceID.uuidString.lowercased()):") == nil) // empty item ID
        #expect(AppleMediaServerItemReference.parse("invalid-prefix:\(sourceID.uuidString.lowercased()):item") == nil)
    }
    
    @Test("Store reload flows")
    func testStoreReload() async throws {
        let source1ID = UUID()
        let source2ID = UUID()
        let source3ID = UUID()
        
        let source1 = AppleSource(id: source1ID, kind: .mediaServer, name: "S1", url: URL(string: "https://fixture.example/emby/")!, isEnabled: true)
        let source2 = AppleSource(id: source2ID, kind: .mediaServer, name: "S2", url: URL(string: "https://fixture.example/emby/")!, isEnabled: true)
        let source3 = AppleSource(id: source3ID, kind: .mediaServer, name: "S3", url: URL(string: "https://fixture.example/emby/")!, isEnabled: false)
        
        let session1 = AppleMediaServerSession(kind: .emby, baseURL: source1.url, accessToken: "t1", userID: "u1")
        let session2 = AppleMediaServerSession(kind: .emby, baseURL: source2.url, accessToken: "t2", userID: "u2")
        
        let client = AppleMediaServerClient(loader: { req in
            let path = req.url!.path
            if req.url!.absoluteString.contains("t2") || path.contains("u2") {
                return (Data(), HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
            }
            
            let json: String
            if path.hasSuffix("Views") {
                json = """
                {
                    "Items": [
                        { "Id": "lib_movies", "Name": "Movies", "CollectionType": "movies" },
                        { "Id": "lib_tv", "Name": "TV Shows", "CollectionType": "tvshows" },
                        { "Id": "lib_music", "Name": "Music", "CollectionType": "other" }
                    ]
                }
                """
            } else if path.hasSuffix("Resume") {
                json = """
                {
                    "Items": [
                        { "Id": "item1", "Name": "Resume 1", "Type": "Movie" },
                        { "Id": "item1", "Name": "Resume 1", "Type": "Movie" }
                    ],
                    "TotalRecordCount": 2
                }
                """
            } else if path.hasSuffix("Items/Latest") {
                if req.url!.absoluteString.contains("ParentId=lib_movies") {
                    json = """
                    [
                        { "Id": "item2", "Name": "Movie 2", "Type": "Movie", "ImageTags": { "Primary": "tag1" }, "BackdropImageTags": ["bd1"] },
                        { "Id": "item3", "Name": "Movie 3", "Type": "Movie" }
                    ]
                    """
                } else {
                    json = "[]"
                }
            } else {
                json = "{}"
            }
            
            return (json.data(using: .utf8)!, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        
        let store = AppleMediaServerLibraryStore(client: client)
        
        await store.reload(sources: [source1, source2, source3]) { s in
            if s.id == source1.id { return session1 }
            if s.id == source2.id { return session2 }
            return nil
        }
        
        #expect(store.failures[source2ID] != nil)
        #expect(store.failures[source2ID] == "The server answered with an error (500).")
        #expect(store.failures[source1ID] == nil)
        #expect(store.failures[source3ID] == nil)
        
        #expect(store.shelves.count == 2)
        #expect(store.shelves[0].id == "ms:\(source1ID.uuidString.lowercased()):lib_movies:latest")
        #expect(store.shelves[0].title == "Latest in Movies")
        #expect(store.shelves[1].id == "ms:\(source1ID.uuidString.lowercased()):lib_tv:latest")
        #expect(store.shelves[1].title == "Latest in TV Shows")
        
        let items = store.shelves[0].items
        #expect(items.count == 2)
        #expect(items[0].posterURL?.absoluteString.contains("tag1") == true)
        #expect(items[1].posterURL == nil)
        
        #expect(store.continueWatching.count == 1)
        
        let ref = AppleMediaServerItemReference(sourceID: source1ID, itemID: "item2")
        #expect(store.item(for: ref) != nil)
        #expect(store.source(for: ref)?.id == source1ID)
        
        store.clear(sourceID: source1ID)
        #expect(store.shelves.isEmpty)
        #expect(store.continueWatching.isEmpty)
        #expect(store.item(for: ref) == nil)
        
        await store.reload(sources: [source1]) { _ in return session1 }
        #expect(store.shelves.count == 2)
    }

    @Test("Merged continue watching handles deduplication")
    func testMergedContinueWatching() {
        let local = [
            AppleCatalogItem(mediaID: "ms:123:item1", type: "movie", name: "L1"),
            AppleCatalogItem(mediaID: "ms:123:item2", type: "movie", name: "L2")
        ]
        
        let server = [
            AppleCatalogItem(mediaID: "ms:123:item2", type: "movie", name: "S2"),
            AppleCatalogItem(mediaID: "ms:123:item3", type: "movie", name: "S3")
        ]
        
        let merged = AppleMediaServerLibraryStore.mergedContinueWatching(local: local, server: server)
        
        #expect(merged.count == 3)
        #expect(merged[0].mediaID == "ms:123:item1")
        #expect(merged[1].mediaID == "ms:123:item2")
        #expect(merged[1].name == "L2") // Keeps local
        #expect(merged[2].mediaID == "ms:123:item3")
        #expect(merged[2].name == "S3")
    }
}
