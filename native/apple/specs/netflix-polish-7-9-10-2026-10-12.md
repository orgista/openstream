# Netflix polish 7, 9, 10: varied rows, right art, crisp art (2026-10-12)

Source: design/reference-apps/2026-10-11-netflix-artwork-suggestions.md "Polish list" ranks 7, 9, 10. Follows
1e91143 (ranks 1–4). Claude picked these under the keep-building rule. Read native/apple/AGENTS.md and the report.

7. AppleSimilarTitleRanker.swift ~194 / AppleCatalogShelfPolicy.swift ~61: diversify picks against titles already
   chosen (soft penalties for repeated primary genre / franchise / source); never touch Continue Watching or real
   Top 10 order; stable ties. Pure tests.
9. AppleArtworkResolver.swift ~34 / AppleCatalogArtworkPolicy.swift ~19: resolve a missing backdrop even when a
   poster exists (and vice versa) so landscape cards stop falling back to a poster-in-frame; explicit purpose
   (poster / resume / hero / logo). Keep source art first, keep the error fallback and metadata-off behaviour, cap
   requests.
10. AppleArtworkResolver.swift ~35 / AppleMetadataClient.swift ~567 / AppleMediaShelf.swift ~156: key the art cache
   by canonical title + kind + purpose + size, pick the TMDB size nearest the displayed pixels (scale-aware), and
   coalesce in-flight lookups for the same key. Never rewrite signed provider URLs.

Out: other ranks, badges, UI text, hero timing. Rules: as specs/todo-finish-2026-10-09.md "Rules", except **do not
commit** (the lead commits). Dev-Mini via scripts/mini.sh + buildlock.sh; full Swift suite green >= 3049 plus new
tests (touch edited files first); build tvOS and iOS; no heavy work in SwiftUI body. No uploads, no secrets, no git
stash/checkout/reset, don't touch native/google-tv. One OWNER-TODO.md Done line per item with evidence.
End with done / not done / next.
