import 'package:alicebar/alice_platform.dart';
import 'package:alicebar/rust_gen/api.dart' as rust_api;
import 'package:alicebar/rust_gen/config.dart' as rust_config;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps only non-secret CalDAV settings into Flutter config', () {
    const rust = rust_api.AliceUiConfig(
      themeMode: rust_config.ThemeMode.system,
      accentColor: '#4C956C',
      transparentTopBar: false,
      useDuotoneIcons: false,
      useAccentOnIcons: false,
      showNetworkLabel: true,
      maxVisibleTrayItems: 5,
      timeZones: [],
      powerCommands: rust_config.PowerCommandConfig(
        lock: 'lock',
        lockAndSuspend: 'suspend',
        restart: 'restart',
        poweroff: 'poweroff',
      ),
      panelTopGapPx: 8,
      caldav: rust_api.CalDavUiConfig(
        principalUrl: 'https://tasks.example.test/dav/principals/alice/',
        allowHttp: false,
        username: 'alice',
        collectionHrefs: [
          'https://tasks.example.test/dav/calendars/alice/work/',
        ],
        pollIntervalSecs: 60,
        caCertificatePath: '/etc/alice/ca.pem',
      ),
      notifications: rust_config.NotificationConfig(
        defaultTimeoutMs: 5000,
        showNotificationPopup: true,
        notificationDisplayTimeMs: 5000,
        expireCriticalNotifications: false,
      ),
      weather: rust_config.WeatherConfig(
        enable: false,
        forecastLanguage: 'en',
        forecastUnits: 'us',
        refreshInterval: 3600,
      ),
    );

    final mapped = AlicePlatform().mapConfigForTesting(rust);

    expect(mapped.useDuotoneIcons, isFalse);
    expect(mapped.useAccentOnIcons, isFalse);
    expect(mapped.caldav, isNotNull);
    expect(mapped.caldav!.username, 'alice');
    expect(mapped.caldav!.allowHttp, isFalse);
    expect(mapped.caldav!.pollIntervalSecs, 60);
    expect(mapped.caldav!.collectionHrefs, hasLength(1));
    expect(mapped.caldav!.caCertificatePath, '/etc/alice/ca.pem');
    // CalDavConfig intentionally has no token field in the Flutter contract.
    expect(mapped.caldav.toString(), isNot(contains('token')));
  });
}
