# Trailers from Plex, Jellyfin and Emby; first choice everywhere, the only source on Apple TV (owner 2026-10-15)

Owner: "for apple tv we can do plex/jellyfin then and emby trailer support". Today: iPhone/iPad/Mac play TMDB YouTube
trailers in a web view; Apple TV plays none (no WebKit on tvOS; AppleTVBillboardView "the Apple TV plays no trailer");
Vision Pro has WebKit but the old hero. Nothing reads server trailers (AppleMediaServerClient has no extras/trailer calls).
Start AFTER Stage B is committed (it edits AppleMediaServerLibrary*). Branch `server-trailers` in its own worktree.

## Do
1. Fetch trailer streams for a title the user's server knows:
   - Plex: `/library/metadata/<ratingKey>/extras` (type trailer; local + Plex Pass online trailers), stream URL with
     the server token, direct-play/transcode decision like normal playback.
   - Jellyfin + Emby: `Items/<id>/LocalTrailers` (and `RemoteTrailers` = YouTube, ignore on tvOS), stream via
     `Videos/<id>/stream` / HLS master with the user's token.
   - Match library titles to server items by the existing server ids; for Home/hero titles that are not in a server
     library, look them up by TMDB/IMDb id where the server supports it.
2. Trailer source chain per title: server trailer file → (iOS/Mac/Vision Pro only) YouTube embed. Apple TV: server
   only. Cache the resolved URL with the title (short TTL; tokens never written to logs or the trace).
3. Use it in: Apple TV hero (muted autoplay after the art settles, same reveal/settle policies as iOS), title page
   trailer button on every platform, Vision Pro hero, and the Top Shelf carousel `previewVideoURL` (coordinate with
   branch tv-disc-shelf: same field). Fit/crop: aspect-fill into the hero frame, no letterbox bars.
4. Tests: client parsing for each server (fixtures from real responses with ids/tokens scrubbed), chain choice per
   platform, tvOS never picks YouTube; E2E-tvOS hero shows a playing trailer with the fixture server's extras.
Gates: serial Swift suite, iOS/tvOS/visionOS/macOS builds, Release (no add-ons) builds, E2E-iOS + E2E-tvOS.
Check on OfficePlus/DevTV against the owner's Plex/Jellyfin. Report per AGENTS.md §7. No commits.
