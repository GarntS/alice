import 'package:material_ui/material_ui.dart';

import '../panel_controller.dart';
import '../rust_gen/state.dart';
import '../tray_input_router.dart';

/// Capture the source view and anchor synchronously, before closing overflow.
class TrayItemTapTarget extends StatelessWidget {
  const TrayItemTapTarget({
    super.key,
    required this.item,
    required this.onActivate,
    this.onInput,
    required this.child,
  });
  final TrayItemSnapshot item;
  final VoidCallback onActivate;
  final TrayInputCallback? onInput;
  final Widget child;

  void _dispatch(BuildContext context, bool secondary) {
    final callback = onInput;
    if (callback == null) {
      if (!secondary) onActivate();
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    final point = box != null && box.hasSize
        ? box.localToGlobal(Offset(box.size.width, box.size.height))
        : Offset.zero;
    callback(
      item,
      PanelAnchor(
        globalPosition: point,
        alignment: PanelAlignment.right,
        sourceViewId: View.of(context).viewId,
      ),
      secondary,
    );
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapUp: (_) => _dispatch(context, false),
    onSecondaryTapUp: (_) => _dispatch(context, true),
    child: child,
  );
}
