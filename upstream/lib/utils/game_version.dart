/// Save compatibility version shared by the engine and title screens.
const String gameVersion = '1.5.6';

/// Release builders supply the source revision for every supported platform.
const String gameBuild = String.fromEnvironment(
  'LCS_BUILD',
  defaultValue: 'development',
);

const String gameVersionLabel = 'Version $gameVersion · Build $gameBuild';
