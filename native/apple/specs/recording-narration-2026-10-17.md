# Owner's narrated iPhone recording (2026-10-15 22:54, iOS 18): every spoken item (transcript found 2026-10-17)
The lead reviewed this recording without its audio on 10-16 and missed the narration. Transcript:
design/qa/owner-recording-2026-10-15-transcript.srt (times = video time). Video: /Users/macstudio/Downloads/
RPReplay_Final1792123442.mp4 (extract frames AT the timestamps with ffmpeg -ss T -frames:v 1 to see each screen).
Owner's words are the spec. Verify every item on the iOS 18.6 sim 7530ECB2 (owner setup, add-ons build) with
screenshots before/after. Add each to design/qa/iphone-feedback-checklist.md.

## Job A — Live (branch live-narration)
- 0:30 "I don't know what this is here, open … I also don't even know where pay-per-view is, maybe premium?" → make
  Pay-Per-View findable (category naming/order), explain/remove the unclear item.
- 1:00 "there's also no metadata in these, only in the All" → programme info in every category, not just All.
- 1:41 "the Watching pills … kind of like AI sloppy" → remove the WATCHING pill; show the playing channel the stock
  way (e.g. playing indicator / selection), no coloured label text.
- 5:08 "This channel … things take you forever" → channel start/Channel Health speed; measure and fix.
- 5:10 / 6:36 IPTV "0 channels · Zero KB · Cancel" box "I never asked for it" → never show an import card for a
  background refresh; only a first import the user started, and never with 0/Zero KB text.
- 7:20 "the bar right there gets stuck … looks weird" → find the stuck bar (Live/guide/Channel Health progress) at
  7:20 in the video; fix.
## Job B — Library, Settings, Discover (branch settings-narration)
- 1:48 "this gets cut off, can't see the full poster" (frame at 1:48) → posters fully visible.
- 2:47 "there's not enough categories in library, it just says movies" → Library categories like the reference apps
  (Movies, Shows, Recently Added, genres/collections as available).
- 2:59 "I shouldn't be able to tap recently added here … I didn't ask for this" → Recently Added is not a tappable
  header/list page.
- 3:34 "I could only add still one folder … I need two folders, which is movies and TV" → multi-folder share must work
  from the share's settings (7abd843 added it; find why the owner couldn't); verify adding TV to ServerPlus.
- 3:55–4:20 "setup from another iPhone could just say transfer … one transfer, then … transfer to, or transfer from";
  "everywhere you go, it says send setup to another device"; "open camera, point at another device … remove that" →
  one "Transfer" entry (to/from) in one place; remove the camera alert.
- 4:28 "the API key there" (Settings › Metadata TMDB/OMDB fields) → hide raw API key fields by default (Advanced) or
  remove if a built-in key exists.
- 5:40 "these shouldn't be default, these top tens. That should be the add-ons" → Top 10 rows OFF by default (opt-in or
  add-on provided).
- 6:26 "This button could use word 2, the test connection" → clearer Test Connection button (likely shorter/primary).
Rules: native/apple/AGENTS.md owner UI rules (no explainer text, stock Apple look, no coloured label text, system
tab bar). code-anti-slop. Scoped gates + iOS 18.6 and 27 E2E for touched screens. No commits.
