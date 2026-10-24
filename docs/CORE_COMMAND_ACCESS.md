# Headquarters command access

Audit: 24 October 2026, against the source commands in `basemode/base_mode.dart`.
The HQ commands menu retains every current source choice and its availability.
Contextual controls enter the same readers; they do not redefine game keys.

| Original command | Journal access |
|---|---|
| E — equipment; V — vehicles | Organisation's Equipment and Vehicles controls. Equipment also appears in People. |
| O — reorder squad | Reorder beside the squad roster. The first position determines who leads. |
| R — review assets / form squads | People, Bases, Ledger and Justice; Assign to squads and Assemble a new squad. HQ commands retains the complete original asset review. |
| A — daily tasks | Orders on the selected person; People → Bulk crew orders enters A → Z. |
| B — sleepers | Network; Bulk sleeper orders enters B → Z. |
| F — visit or fight/escape | Orders/map visit controls; contextual siege responses when under siege. |
| G — give up | The contextual siege response page, with the original surrender consequences and reader. |
| C — cancel departure | Queued visit card and footer cancellation control. |
| I — investment; P — flag/protest | Bases, including the selected base's original facilities, supplies and flag choice. |
| N — next squad; Z — next location | Direct squad selection and the Bases directory. Original cycling remains in HQ commands. |
| L — agenda; M — media | Agenda and Newspaper tabs. |
| W — advance / siege response | Contextual footer; required reports retain their own acknowledgements. |
| X — save and exit | Footer and Options. |
| S — movement slogan | Options shows the current slogan and opens its original editor. |

Bulk orders choose a task and then apply it immediately to each selected person.
Task and person lists scroll separately; selected costs, requirements and risks
stay visible above them, with full mechanics in a read-only Details dialog.
Opening or cancelling their menus assigns nothing. Squad reordering retains both
original selection steps and cancellation at either step. New navigation controls
respect unconfirmed drafts, required readers and stale callbacks. Explicitly
revisiting People restores its retained searchable directory after keyboard use.

`headquarters_command_access_test.dart` covers actual readers, cancellation,
revisiting, actor-only changes, campaign/RNG preservation and desktop/enlarged
layouts. `scripts/hq_command_browser_review.mjs` covers contextual pointer entry,
original keys, whole-campaign exports and actual browser bounds against an exact
JavaScript hash. Its extra sleeper is an explicitly prepared fixture.
