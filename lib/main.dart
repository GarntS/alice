import 'package:flutter/widgets.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import 'app.dart';
import 'alice_platform.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // The Rust library is statically linked into the Flutter runner binary on
  // Linux desktop, so symbols live in the current process — use process() to
  // avoid a dlopen() attempt for a non-existent .so file.
  await RustLib.init(
    externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true),
  );
  runApp(AliceApp.fromArguments(args));
}
