import Foundation
import Testing
@testable import OpenStreamApple

@Suite struct AppleHomeDesignPolicyTests {
    @Test func trailersStayOutOfSystemPlayback() {
        let preview = ApplePlaybackSessionPolicy.trailer
        #expect(preview.audioCategory == .ambient)
        #expect(!preview.publishesNowPlaying)
        #expect(!preview.registersRemoteCommands)
        #expect(ApplePlaybackSessionPolicy.playback.audioCategory == .playback)
        #expect(ApplePlaybackSessionPolicy.playback.publishesNowPlaying)
        #expect(ApplePlaybackSessionPolicy.playback.registersRemoteCommands)
        #expect(!preview.webMediaSessionSuppressionScript.isEmpty)
        #expect(ApplePlaybackSessionPolicy.playback.webMediaSessionSuppressionScript.isEmpty)
    }

    @Test func manifestCatalogIdentityPreservesSameNamesAndTop10() throws {
        let data = Data(#"""
        {"id":"fixture.aiometadata","name":"AIOMetadata","resources":["catalog"],
         "catalogs":[
           {"id":"popular","type":"movie","name":"Popular Movies"},
           {"id":"popular","type":"series","name":"Popular Movies"},
           {"id":"disney","type":"movie","name":"Top 10 Disney+"}
         ]}
        """#.utf8)
        let manifest = try JSONDecoder().decode(AppleStremioManifest.self, from: data)
        let source = AppleSource(kind: .stremio, name: manifest.name,
            url: try #require(URL(string: "https://fixture.example/manifest.json")),
            resources: manifest.resources, catalogs: manifest.catalogs)
        let sections = AppleCatalogDiscoveryPolicy.catalogs(for: source).map { catalog in
            AppleCatalogSection(source: source, catalog: catalog, items: [
                AppleCatalogItem(mediaID: "fixture-title", type: catalog.type, name: "Fixture")
            ])
        }
        let visible = AppleCatalogShelfPolicy.visibleSections(sections + sections, activeSourceIDs: [source.id])
        #expect(visible.count == 3)
        #expect(Set(visible.map(\.id)).count == 3)
        #expect(visible.map { AppleCatalogShelfPolicy.title(for: $0.catalog) }
            == ["Popular Movies", "Popular Movies", "Top 10 Disney+"])
        #expect(visible.map { AppleCatalogShelfPolicy.style(for: $0.catalog) }
            == [.poster, .poster, .ranked])
        #expect(AppleCatalogShelfPolicy.visibleSections(sections, activeSourceIDs: []).isEmpty)
    }

    @Test func featuredCatalogsUseLandscapeCardsWithoutRenaming() {
        let catalog = AppleStremioCatalog(type: "movie", id: "featured", name: "Featured Movies")
        #expect(AppleCatalogShelfPolicy.style(for: catalog) == .featured)
        #expect(AppleCatalogShelfPolicy.title(for: catalog) == "Featured Movies")
    }
}
