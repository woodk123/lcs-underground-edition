# LCS: New Age — The Underground Edition

A work-in-progress fork of [Liberal Crime Squad: New Age](https://github.com/ashley-s-fox/lcs-new-age), with an interface inspired by the old organiser in **Gangsters: Organized Crime**. Paper and leather, painted portraits, crew dossiers, city maps and job cards—with the New Age game underneath.

## Why this exists

I contributed a few small features and bug fixes to LCS years ago. I've still got emails with Jonathan from 2009, which is slightly terrifying! Finding the Flutter version blew me away and got me tinkering again. It's lovely to see familiar names still keeping LCS going.

The game always reminded me a little of Gangsters: Organized Crime, so I started this vibe-coded fork to explore that style of interface. It's still very much a work in progress, and feedback is welcome.

## What's changed

- A paper-and-leather journal for managing your organisation, crew and orders.
- Painted portraits, crew dossiers, city maps and job cards explaining assignments.
- Characters keep their portraits across saves, with supported injuries and equipment reflected visually.
- Bug fixes along the way, including crafting consuming cloth when you couldn't afford the job, and fixes to save importing and recovery.

The interface and artwork are being developed with AI assistance; the paintings and portraits are AI-generated. The project builds on Ashley S. Fox's New Age and the work of the wider LCS community.

## Playing

There isn't a downloadable GitHub release yet. For now, [build from source](docs/BUILDING.md), then double-click **Play.cmd** in the project folder. On Windows, it starts a local server and opens the game at **http://127.0.0.1:8765/**. Python 3 is required.

If you already have a packaged build, extract the whole archive and run its **Play.cmd**.

**Keep the same browser profile and address to keep using your browser saves.** `localhost`, another port or another browser has separate save storage. Export important saves from the game before clearing browser data.

## More information

- [Building and development](docs/BUILDING.md)
- [Changes and bug fixes](docs/ORIGINAL_CODE_CHANGES.md)
- [Portrait library](docs/PORTRAIT_LIBRARY.md)
- [Gameplay fidelity and testing](docs/GAMEPLAY_FIDELITY.md)

## Credits and license

Based on [Liberal Crime Squad: New Age by Ashley S. Fox](https://github.com/ashley-s-fox/lcs-new-age), itself built on the original Liberal Crime Squad. Thanks to everyone who has kept the game alive over the years.

See [AUTHORS.md](AUTHORS.md) for the original credits. Distributed under the [GNU GPL v2](LICENSE).
