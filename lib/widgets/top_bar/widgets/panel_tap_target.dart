import 'package:flutter/material.dart';

import '../../../state/panel_controller.dart';

class TopBarPanelTapTarget extends StatefulWidget {
  const TopBarPanelTapTarget({
    super.key,
    required this.alignment,
    required this.onTap,
    required this.child,
  });

  final PanelAlignment alignment;
  final ValueChanged<PanelAnchor> onTap;
  final Widget child;

  @override
  State<TopBarPanelTapTarget> createState() => _TopBarPanelTapTargetState();
}

class _TopBarPanelTapTargetState extends State<TopBarPanelTapTarget> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        widget.onTap(_anchorFromWidget());
      },
      child: widget.child,
    );
  }

  PanelAnchor _anchorFromWidget() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return PanelAnchor(
        globalPosition: Offset.zero,
        alignment: widget.alignment,
      );
    }

    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;
    final anchorX = widget.alignment == PanelAlignment.right
        ? origin.dx + size.width
        : origin.dx + (size.width / 2);
    final anchorY = origin.dy + size.height;
    return PanelAnchor(
      globalPosition: Offset(anchorX, anchorY),
      alignment: widget.alignment,
    );
  }
}
