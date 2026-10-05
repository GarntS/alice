import 'package:flutter/widgets.dart';
import 'panel_controller.dart';

class TrayResolvedAnchor {
  const TrayResolvedAnchor({
    required this.anchor,
    required this.screenPosition,
    required this.usableSize,
    required this.popupPosition,
  });
  final PanelAnchor anchor;
  final Offset screenPosition;
  final Size usableSize;
  final Offset popupPosition;

  factory TrayResolvedAnchor.fromMap(Map<String, dynamic> data) {
    final position = Offset(
      (data['x'] as num).toDouble(),
      (data['y'] as num).toDouble(),
    );
    return TrayResolvedAnchor(
      anchor: PanelAnchor(
        sourceViewId: data['sourceViewId'] as int,
        globalPosition: position,
        alignment: PanelAlignment.right,
      ),
      screenPosition: Offset(
        (data['screenX'] as num).toDouble(),
        (data['screenY'] as num).toDouble(),
      ),
      usableSize: Size(
        (data['width'] as num).toDouble(),
        (data['height'] as num).toDouble(),
      ),
      popupPosition: Offset(
        position.dx,
        position.dy - (data['barHeight'] as num).toDouble(),
      ),
    );
  }
}
