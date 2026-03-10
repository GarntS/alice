class BarSnapshot {
  const BarSnapshot({
    required this.activePanelId,
    required this.workspaces,
    required this.media,
    required this.memoryUsagePercent,
    required this.cpuUsageCores,
    required this.network,
    required this.clock,
    required this.trayItems,
  });

  final String? activePanelId;
  final List<WorkspaceSnapshot> workspaces;
  final MediaSnapshot? media;
  final double memoryUsagePercent;
  final double cpuUsageCores;
  final NetworkSnapshot network;
  final ClockSnapshot clock;
  final List<TrayItemSnapshot> trayItems;
}

class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    required this.label,
    required this.isFocused,
    required this.isVisible,
  });

  final String label;
  final bool isFocused;
  final bool isVisible;
}

class MediaSnapshot {
  const MediaSnapshot({
    required this.title,
    required this.artist,
    required this.positionLabel,
    required this.lengthLabel,
    required this.isPlaying,
  });

  final String title;
  final String artist;
  final String positionLabel;
  final String lengthLabel;
  final bool isPlaying;
}

class NetworkSnapshot {
  const NetworkSnapshot({required this.kind, required this.label});

  final NetworkKind kind;
  final String label;
}

enum NetworkKind { wifi, wired, disconnected }

class ClockSnapshot {
  const ClockSnapshot({
    required this.timeZoneCode,
    required this.dateLabel,
    required this.timeLabel,
  });

  final String timeZoneCode;
  final String dateLabel;
  final String timeLabel;
}

class TrayItemSnapshot {
  const TrayItemSnapshot({required this.id, required this.label});

  final String id;
  final String label;
}
