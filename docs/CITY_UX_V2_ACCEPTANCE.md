# City buildings, crew dossiers and generated sprite animation

Active objective: make the city view work through buildings the player can inspect and order, with crew portraits/dossiers and image-generated sprites/animation. A card grid over the existing panorama does not satisfy this objective.

## Required product behavior

1. The default city view is a pan/zoom street scene composed of separate generated building sprites. Every interactive place corresponds to a currently exposed original destination; hidden sites are not enumerated. The street layout is illustrative and introduces no travel/pathfinding/territory rules.
2. Selecting a building opens a contextual inspector. Hover, focus, inspection, zoom, fitting the scene and closing details do not dispatch an engine command or mutate the campaign/RNG. Current location, unavailable orders and known restrictions remain legible.
3. The inspector gives an explicit action for the original destination: enter district/city or queue the selected squad's visit. The action preserves exact key, availability and current-frame identity. A stale inspector cannot order a different destination. The equivalent locations list remains accessible as a secondary view.
4. Crew portraits are rendered from generated production art in headquarters, the city squad context and explicitly identified central people rows. Clicking a portrait opens the actual person's dossier independently of the row's existing gameplay command. Identity remains stable across save/reload and renaming without consuming gameplay randomness.
5. Dossiers show actual identity, current order/location, skills/attributes, equipment and health/injuries, with readable scrolling and keyboard close. They fabricate no biography, demographics or simulation statistics. Any action is explicitly supplied by the original game context; inspection alone changes nothing.
6. Image generation supplies production building sprites, crew portraits and a visibly changing multi-frame character animation. The runtime uses the real generated animation frames; a moving static placeholder or repeated identical pose is insufficient. Crop rectangles/anchors may describe the untouched generated sheets.
7. Sprite animation stops/disables for reduced-motion preferences and offstage/disposal. Animation never moves the campaign clock, reveals a hidden location or represents an invented tactical unit.
8. The actual rendered product is inspected at desktop and compact sizes. Real browser input verifies building inspection followed by a queued original order and crew dossier open/close. Relevant tests, full analysis, source fidelity and packaged/save/offline checks are rerun for the changed runtime before final delivery.

## Work ownership

The integration lead coordinates implementation, original semantic metadata, headquarters integration, shared engine/browser checks and release evidence. `city_buildings` owns the city scene/planning module and city tests. `crew_dossiers` owns portrait/dossier modules, central person-row presentation and its tests. `city_sprite_art` owns built-in image generation, selected production sheets, crop/anchor contracts and provenance. All workers preserve concurrent changes and the original simulation.

## Verification record

Accepted runtime SHA-256: `63cac78e154023a26e8519c62b1237360fcf5219de7ddc02700415ea2fcc54f2`. The frozen pipeline `.local/reports/build-20261013-221335/` passes 174 tests with clean focused/full analysis. Earlier b0b6e3b3/97df1dc9 results are historical and are not substituted for the final evidence below.

| Requirement | Current authoritative evidence |
| --- | --- |
| 1 — actual generated buildings and streets | `CityScene` and actual final `29-city-building-streets.png` / `existing-campaign/05-district-buildings.png`. The generated building atlas is loaded and cropped individually. Real engine fixtures compare exposed IDs and exclude a hidden site. |
| 2 — inspection is local | City tests check original input, revision, order/date/funds and stale callbacks. Browser inspectors/dossiers/zoom/fit preserve actual visible date/funds/order. Dossier tests preserve complete JSON and RNG sequence. |
| 3 — explicit faithful orders | Actual district → site inspection → Queue squad visit → original departure/arrival/tactical/return passes the packaged driver. C/c, disabled and stale-choice regressions preserve identity/availability. The equivalent list is exercised. A clearly marked same-final-hash supplemental capture verifies Need Car/disabled order when that condition exists. |
| 4 — stable real crew portraits | HQ, central task row and city dossier flows pass. Two same-name real people resolve by distinct IDs; an untyped matching name exposes no dossier. Portrait ID survives rename/save reload without rolls. Five actual existing campaign members are captured in the final attachment. |
| 5 — factual dossiers and safe modal actions | Actual Overview/Skills/Campaign record captures, narrow/large-text tests and HQ pending-input/one-command tests. Captive availability and positive-ammo/unknown-type regressions correct factual status. No biography or game statistic is invented. |
| 6 — generated sprites and genuine animation | `CITY_SPRITE_ASSETS.md` and `assets/art-city-v2/atlas_metadata.json`: 16 building sprites, 16 adult portraits and eight distinct walk frames; original PNG hashes and all 40 source rectangles verified. Final `city-animation/` contains real browser raster samples and WebM; no static stand-in is accepted. |
| 7 — motion preferences and lifecycle | Final browser animation samples change visibly; reduced-motion samples have zero differences. Independent offstage reproduction and owner tests verify nested Offstage, TickerMode, resume and disposal. No animation module calls campaign simulation or RNG. |
| 8 — actual rendered and distributed behavior | Final packaged report `reports/browser/smoke-2026-10-13T22-19-06-594Z/report.json`: 81 checkpoints, zero skips/errors, real saves/restart/import/upgrade and server-stopped offline play. `existing-campaign/` contains final 1600×1000/1280×720 fitted scenes and actual 800×600 narrow building auto-reveal/dossier checks. Original source/data preservation passes independently. Final archive identities/integrity are written to `release/DELIVERY.json`. |

The independent assessment is `CITY_UX_V2_REVIEW.md`. Native Windows compilation is an additional deliverable; its final full GUI playthrough remains unverified because native computer control was stopped by the user. The primary accepted product is the packaged browser runtime. Portraits are a finite illustrative adult bank; children/nonhuman characters use appropriate fallback identities, while every dossier reports the actual character data.
