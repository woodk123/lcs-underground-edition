# Interface feedback — 15 October 2026

This update addresses Ashley S. Fox's review of the Underground Edition preview.
It changes presentation and portrait casting; activity rules and skill values
remain the original New Age simulation.

- Dossier skill levels sit next to their names. XP uses a short, subdued bar
  and smaller text rather than dominating the row.
- Order cards show timing, the estimate, relevant skills, costs and risks. The
  information button, labelled **Order mechanics**, opens the full calculation,
  requirements and explanation. It works with pointer and keyboard input;
  opening or closing it changes no assignment, time, funds or gameplay RNG.
- Removed repetitive campaign/specification captions, unnecessary map
  instructions and descriptions of cosmetic portrait borders. Kept useful
  availability, cost and risk information.
- Portrait casting chooses an age-suitable pool before considering unused
  faces. Clearly mismatched saved assignments are repaired once. Appropriate
  identities remain stable as characters age; the dossier shows their actual
  age. See [portrait age matching](PORTRAIT_LIBRARY.md#age-matching--15-october-2026-feedback-update).

## Verification

All **571 Flutter tests passed**, including checks for skill-label proximity,
subdued progress bars, mechanics disclosure at 800×600 with 150% text, unchanged
campaign/input/RNG after opening and dismissing details, and portrait
age/specialist/save-migration coverage. Full-project analysis reported no issues.
The release web build and offline resource manifest were regenerated.

The isolated Edge review passed **seven checkpoints**, with no page, console or
request errors. The deliberately mismatched age-68 saved face on a 22-year-old
was replaced with a young-adult face and remained identical after save/load.
The complete exported campaign was unchanged after dossiers, disclosures and
cancelled drafts. Screenshots of the [skill list](screenshots/character-dossier.png)
and [concise order card](screenshots/city-and-orders.png) are included in the README.
The reviewed browser runtime SHA-256 is
`7586a831286985702dfb9df26de7a6d7a2ecb610bb98cc60df0aaa8d57c6442a`.

The focused browser review is reproducible with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/launch.ps1 -Port 18879 -NoBrowser
node scripts/ashley_feedback_browser_review.mjs --url http://127.0.0.1:18879/
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/stop.ps1 -Port 18879
```

It imports a synthetic copy of the bundled Felix campaign into an isolated
browser context: a 22-year-old is deliberately given an age-68 saved portrait.
The review checks repair to the young-adult pool, skills and mechanics screens,
large-text layout, and exact exported-game equality after inspection and
cancelled drafts. It does not operate a player's browser profile or save.

The existing downloadable preview remains the frozen release described in
[BUILDING.md](BUILDING.md); these checkout changes are not a replacement for
that release's recorded binary identity or QA scope.
