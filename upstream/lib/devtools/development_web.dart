import 'package:lcs_new_age/devtools/development_web_stub.dart'
    if (dart.library.js_interop) 'package:lcs_new_age/devtools/development_web_js.dart'
    as platform;

void installDevelopmentBridge() => platform.installDevelopmentBridge();
