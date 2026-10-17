import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/saveload/native_profile_io.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/saveload/storage/sembast_storage.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'test_support.dart';

void main() {
  late Directory root;
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    SharedPreferences.setMockInitialValues({'playerSetting': 'untouched'});
    root = await Directory.systemTemp.createTemp('lcs-profile-test-');
  });
  tearDown(() async {
    await configureNativeProfile([]);
    SharedPreferences.setMockInitialValues({});
    await root.delete(recursive: true);
  });

  test(
    'default launch keeps the platform preference store and save path',
    () async {
      final original = SharedPreferencesStorePlatform.instance;
      await configureNativeProfile([]);
      expect(nativeDataDirectory, isNull);
      expect(SharedPreferencesStorePlatform.instance, same(original));
      expect(
        (await SharedPreferences.getInstance()).getString('playerSetting'),
        'untouched',
      );
    },
  );

  test(
    'explicit profiles persist settings and saves without reading defaults',
    () async {
      final first = path.join(root.path, 'profile A');
      final second = path.join(root.path, 'profile B');
      await configureNativeProfile(['--data-directory=$first']);
      var preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('playerSetting'), isNull);
      await preferences.setDouble('fontSize', 23);
      await preferences.setStringList('history', ['a', 'b']);
      final save = SaveFile.fromJson(
        jsonDecode(await File('test/saves/felix_1_0.json').readAsString())
            as Map<String, dynamic>,
      );
      var storage = SembastStorage();
      await storage.init();
      await storage.saveGame(save);
      await storage.updateLastGameId(save.gameId);
      await storage.close();

      SharedPreferences.resetStatic();
      await configureNativeProfile(['--data-directory=$second']);
      preferences = await SharedPreferences.getInstance();
      expect(preferences.getKeys(), isEmpty);
      storage = SembastStorage();
      await storage.init();
      expect(await storage.listGameIds(), isEmpty);
      await storage.close();

      SharedPreferences.resetStatic();
      await configureNativeProfile(['--data-directory=$first']);
      preferences = await SharedPreferences.getInstance();
      expect(preferences.getDouble('fontSize'), 23);
      expect(preferences.getStringList('history'), ['a', 'b']);
      expect(preferences.getInt('lastGameId').toString(), save.gameId);
      storage = SembastStorage();
      await storage.init();
      expect((await storage.loadGame(save.gameId))!.toJson(), save.toJson());
      await storage.close();
      expect(File(path.join(first, 'lcs_new_age.db')).existsSync(), isTrue);
    },
  );

  test(
    'profile clear and remove persist and preserve unrelated prefixes',
    () async {
      final file = File(path.join(root.path, 'preferences.json'));
      var store = await ProfilePreferences.open(file);
      await store.setValue('String', 'other.keep', 'yes');
      await store.setValue('Int', 'flutter.one', 1);
      await store.setValue('Int', 'flutter.two', 2);
      await store.remove('flutter.one');
      store = await ProfilePreferences.open(file);
      expect(await store.getAll(), {'flutter.two': 2});
      await store.clear();
      store = await ProfilePreferences.open(file);
      expect(
        await store.getAllWithParameters(
          GetAllParameters(filter: PreferencesFilter(prefix: '')),
        ),
        {'other.keep': 'yes'},
      );
    },
  );

  test('relative or duplicate directories cannot redirect storage', () async {
    final original = SharedPreferencesStorePlatform.instance;
    await expectLater(
      configureNativeProfile(['--data-directory=relative']),
      throwsArgumentError,
    );
    await expectLater(
      configureNativeProfile([
        '--data-directory=${root.path}',
        '--data-directory=${root.path}',
      ]),
      throwsArgumentError,
    );
    expect(SharedPreferencesStorePlatform.instance, same(original));
  });
}
