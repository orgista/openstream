# Netflix polish 1–4: recommendation inputs (2026-10-12)

Source: design/reference-apps/2026-10-11-netflix-artwork-suggestions.md, "Polish list" ranks 1–4 and the
"Concrete on-device suggestion approach" steps 1–4. Owner: Netflix is the reference for the suggestion algorithm;
"our design is in a good place", so this is a polish of the existing rankers, not a new feed. Claude picked these four
under the keep-building rule.

Read native/apple/AGENTS.md and the report first. Scope (each with unit tests):
1. AppleDiscoverView.swift ~648/672: pass real normalized genres (item / already-enriched metadata, no fetches during
   body evaluation) into both the history and candidate inputs of the ranker; parse the release year from `item.year`
   or a leading 4-digit year instead of whole-string Int. Missing genres stay neutral.
2. Canonicalize/deduplicate titles before ranking and hero selection (AppleDiscoverView ~654/668/686,
   AppleHeroRotation.swift ~49): one stable representative per title (accessible source + best metadata), alternate
   sources kept for playback. Never merge distinct films by name alone; keep media kind + year/ids in the identity.
3. History from real progress/completed dates (AppleDiscoverView ~645/649, AppleRecommendationRanker ~21): completed
   and meaningful progress count, per-show cap so many episodes can't dominate, unknown timestamps kept without inventing.
4. AppleRecommendationRanker ~84/100: rating `.none` exactly neutral; explicit dislike still excludes; capped,
   comparable rating weights; likes transfer bounded genre affinity to related unseen titles.

Out: ranks 5–14, new rows, badges, artwork, any UI text (owner rule: no explainer text), hero timing/CW precedence.

Rules: same as specs/todo-finish-2026-10-09.md "Rules", except: **do not commit** — leave the diff; the lead reviews
and commits. Builds/tests only on Dev-Mini via scripts/mini.sh + buildlock.sh (Dev-Mini project files under
/Volumes/DevExt/dev/). Full Swift suite green, count >= 3027 plus your new tests (touch edited files first). No
uploads, no secrets, no git stash/checkout/reset, don't touch native/google-tv. Add one OWNER-TODO.md line under Done
per item with test evidence. End with done / not done / next.
