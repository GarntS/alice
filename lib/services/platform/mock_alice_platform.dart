import '../../models/bar_snapshot.dart';
import 'alice_platform.dart';

class MockAlicePlatform implements AlicePlatform {
  @override
  BarSnapshot get snapshot => const BarSnapshot(
    activePanelId: null,
    workspaces: [
      WorkspaceSnapshot(label: '1', isFocused: true, isVisible: true),
      WorkspaceSnapshot(label: '2', isFocused: false, isVisible: false),
      WorkspaceSnapshot(label: '3', isFocused: false, isVisible: true),
      WorkspaceSnapshot(label: '4', isFocused: false, isVisible: false),
    ],
    media: MediaSnapshot(
      title: 'I Get Off',
      artist: 'Halestorm',
      positionLabel: '0:26',
      lengthLabel: '2:10',
      isPlaying: true,
    ),
    memoryUsagePercent: 72.4,
    cpuUsageCores: 2.4,
    network: NetworkSnapshot(kind: NetworkKind.wifi, label: 'copperfield'),
    clock: ClockSnapshot(
      timeZoneCode: 'EDT',
      dateLabel: '09 Mar',
      timeLabel: '13:37',
    ),
    trayItems: [
      TrayItemSnapshot(id: 'nm-applet', label: 'Network'),
      TrayItemSnapshot(id: 'discord', label: 'Discord'),
      TrayItemSnapshot(id: 'steam', label: 'Steam'),
      TrayItemSnapshot(id: 'syncthing', label: 'Syncthing'),
      TrayItemSnapshot(id: 'backup', label: 'Backups'),
      TrayItemSnapshot(id: 'vpn', label: 'VPN'),
    ],
  );
}
