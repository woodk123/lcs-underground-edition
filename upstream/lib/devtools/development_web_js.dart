import 'dart:js_interop';

import 'package:lcs_new_age/devtools/development_bridge.dart';

@JS('globalThis.lcsDev')
external set _bridge(JSObject value);

@JS()
extension type _WebBridge._(JSObject _) implements JSObject {
  external factory _WebBridge({JSFunction request});
}

void installDevelopmentBridge() {
  if (!developmentToolsEnabled) return;
  _bridge = _WebBridge(
    request:
        ((JSString request) => developmentBridge
                .request(request.toDart)
                .then((value) => value.toJS)
                .toJS)
            .toJS,
  );
}
