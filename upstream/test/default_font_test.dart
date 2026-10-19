import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the web engine default family resolves to bundled Roboto fonts',
    () async {
      final manifest =
          jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
      final defaults = manifest.cast<Map<String, dynamic>>().singleWhere(
        (family) => family['family'] == 'Roboto',
      );
      final modern = manifest.cast<Map<String, dynamic>>().singleWhere(
        (family) => family['family'] == 'ModernSans',
      );
      expect(defaults['fonts'], modern['fonts']);
      for (final font in (defaults['fonts'] as List).cast<Map<String, dynamic>>()) {
        expect(
          (await rootBundle.load(font['asset'] as String)).lengthInBytes,
          greaterThan(1000),
        );
      }
    },
  );
}
