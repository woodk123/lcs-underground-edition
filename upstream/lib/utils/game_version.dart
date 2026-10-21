/// Player-facing Underground Edition version; mirror in pubspec.yaml.
const String gameVersion = '0.2.4';

/// Upstream base for credits, independent of Underground release numbering.
const String upstreamVersion = '1.5.6';

/// Existing save header and migration lineage; never bump for a release alone.
const String saveCompatibilityVersion = '1.5.6';

/// Builders label their distribution; direct Flutter runs are development.
const String gameChannel = String.fromEnvironment(
  'LCS_CHANNEL',
  defaultValue: 'Development',
);

/// Release builders supply the source revision for every supported platform.
const String gameBuild = String.fromEnvironment(
  'LCS_BUILD',
  defaultValue: 'development',
);

const String gameVersionLabel =
    'Underground Edition $gameVersion · $gameChannel\n'
    'Based on New Age $upstreamVersion · Build $gameBuild';
