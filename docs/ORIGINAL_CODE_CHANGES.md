# Original code changes and bug fixes

## Changes to the original code

The original Dart/Flutter engine, gameplay systems and authored content remain. Of 200 original Dart files, 171 are unchanged and 29 have reviewed changes.

- `main.dart` runs the original game loop inside the new interface.
- Console and input helpers expose exact commands, entity IDs and availability to clickable controls.
- Menu printers provide read-only data for squads, activities, creation, finances, politics and news.
- Scoped navigation allows switching management screens without accidentally cancelling queued orders. Original gameplay handlers still execute the actions.

## Bug fixes in the original game and save code

- **Crafting:** unaffordable clothing or flag jobs no longer consume recycled cloth. Successful crafting calculations remain unchanged.
- **Calendar:** advancing a day no longer risks repeated or skipped dates across daylight-saving changes.
- **Save failures:** unsuccessful saving stops day advancement or exit before campaign progress changes.
- **Imports:** invalid saves are rejected without overwriting or partially replacing the active campaign.
- **Legacy equipment:** older saves retain equipped clothing quality and protection during migration.
- **Randomness:** inspecting saves no longer consumes the active campaign’s random draws.
- **Statistics:** completed campaign totals are recorded once, avoiding repeated inclusion of active-save progress.

[Detailed source audit](GAMEPLAY_FIDELITY.md).

## Squad visit order presentation — 14 October 2026

The journal now offers Visit a location under Operations and Prepare visit on the left job card for an inspected building. Both use the original awaited planner and one Confirm order / safe Cancel row. Prepared/queued Squad cards show destination, members, existing travel-cost calculation, requirements, daily-task precedence and day-advance timing. No original gameplay source changed in this update. [Review and verification](SQUAD_VISIT_ORDERS.md).
