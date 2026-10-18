# Screenshot provenance

The 0.1.0 README images were captured on 18 October 2026 from the running game using the pinned Flutter SDK and the Release channel. Their web build's `main.dart.js` SHA-256 is `b5d568345ff6ee7e162a87a995ac5a1d080e7c0e093ec276f637eae6506778da` (gameplay source based on `513b032e`, with the prepared release changelog).

- `police-station-combat.png`: an actual combat result from `scripts/mission_browser_review.mjs --only tactical`. A disposable copy of the bundled Felix campaign clears old wanted charges, heat and orders; skills, equipment, funds, date and combat outcomes are not supplied. The screenshot shows a spinal injury sustained in the fight.
- `injury-dossier.png`: `scripts/injury_browser_review.mjs`, showing explicitly prepared gunshot wounds, bruises, blood loss and a collapsed lung. Inspection preserves the full campaign export exactly.

Current capture reports remain in ignored `reports/release-0.1.0-combat-pages/` and `reports/release-0.1.0-injuries-final/`. These are presentation captures; final distribution checks use the separately built, committed release packages.
