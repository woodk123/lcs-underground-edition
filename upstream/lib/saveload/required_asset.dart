import 'package:flutter/services.dart';

/// Read required startup data again after a failed transfer, before parsing it.
/// Failed string futures must be evicted so the next read reaches the bundle.
Future<T> _readRequiredAsset<T>(
  AssetBundle bundle,
  String key,
  Future<T> Function() read,
) async {
  for (var attempt = 0; ; attempt++) {
    try {
      return await read();
    } on FormatException {
      rethrow;
    } catch (_) {
      bundle.evict(key);
      if (attempt == 2) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
    }
  }
}

Future<String> loadRequiredAssetString(String key, {AssetBundle? bundle}) {
  final assets = bundle ?? rootBundle;
  return _readRequiredAsset(assets, key, () => assets.loadString(key));
}

Future<ByteData> loadRequiredAssetBytes(String key, {AssetBundle? bundle}) {
  final assets = bundle ?? rootBundle;
  return _readRequiredAsset(assets, key, () => assets.load(key));
}
