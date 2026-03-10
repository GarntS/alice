import 'package:flutter/services.dart' show rootBundle;

class DefaultConfigTemplate {
  static const _assetPath = 'assets/config/default_config.yaml';

  Future<String> load() {
    return rootBundle.loadString(_assetPath);
  }
}
