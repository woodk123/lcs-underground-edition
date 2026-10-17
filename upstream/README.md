# Liberal Crime Squad: New Age — The Underground Edition

This is **The Underground Edition**, featuring an illustrated journal interface, crew dossiers and city planning over the retained New Age engine. See [the project README](../README.md) for local play, builds and verification.

Original New Age play link:

> <https://www.jonathansfox.com/lcs-new-age/>

Welcome to Liberal Crime Squad! The Conservatives have taken the Executive, Legislative, and Judicial branches of government. Over time, the Liberal laws of this nation will erode and turn the country into a BACKWOODS YET CORPORATE NIGHTMARE. To prevent this from happening, the Liberal Crime Squad was established. The mood of the country is shifting, and we need to turn things around. Go out on the streets and indoctrinate Conservative automatons.  That is, let them see their True Liberal Nature. Then arm them and send them forth to Stop Evil.

Liberal Crime Squad: New Age is a complete rewrite and port of Liberal Crime Squad from C++ to Dart, with the aim of making it run natively in modern web browsers. (It should also be possible to compile native builds.)

New Age is additionally intended to be a Radical Design Departure, a Liberal Playground where Ashley S. Fox can unleash new and inadvisable design ideas on the game.

## Contributing

Liberal Crime Squad: New Age — The Underground Edition welcomes the efforts of Liberal Freedom Fighters who wish to contribute to its development.

Clone [the Underground Edition repository](https://github.com/woodk123/lcs-underground-edition), then follow [Building and development](../docs/BUILDING.md) from its root directory, one level above this Flutter project. Use the Flutter version and revision pinned in `scripts/toolchain.json`; the shared release scripts also generate save serializers, run checks and prepare matching player/source packages.

For an editable checkout, follow [Development mode](../docs/BUILDING.md#development-mode) to resolve dependencies, generate serializers and launch Chrome without packaging a release. Regenerate serializers whenever saved model fields or JSON annotations change. Native Windows development also requires the [Windows build tools](../docs/WINDOWS_BUILD.md).

The gameplay loop is sequential and awaits console input. The illustrated journal uses structured screen/action metadata from that loop; use a full application restart after engine changes. See [Architecture](../docs/ARCHITECTURE.md) for the engine/interface boundary and [Testing](../docs/TESTING.md) for regression and browser checks.

Keep original New Age credits and licenses intact. The [project README](../README.md) links the current players, source and upstream project.
