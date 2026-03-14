import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../rust_gen/state.dart';
import '../../panel_controller.dart';
import 'panel_tap_target.dart';
import 'pill.dart';

class TopBarTrayGroupModule extends StatelessWidget {
  const TopBarTrayGroupModule({
    super.key,
    required this.items,
    required this.onItemTap,
  });

  final List<TrayItemSnapshot> items;
  final ValueChanged<TrayItemSnapshot> onItemTap;

  @override
  Widget build(BuildContext context) {
    return TopBarPill(
      icon: Icons.apps_rounded,
      label: '',
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < items.length; index++) ...[
            _TrayIconButton(
              item: items[index],
              onTap: () => onItemTap(items[index]),
            ),
            if (index != items.length - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

class _TrayIconButton extends StatelessWidget {
  const _TrayIconButton({required this.item, required this.onTap});

  final TrayItemSnapshot item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: item.label,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          child: _TrayIcon(iconPngBytes: item.iconPngBytes),
        ),
      ),
    );
  }
}

class _TrayIcon extends StatelessWidget {
  const _TrayIcon({required this.iconPngBytes});

  final Uint8List? iconPngBytes;

  @override
  Widget build(BuildContext context) {
    if (iconPngBytes == null || iconPngBytes!.isEmpty) {
      return const Icon(Icons.apps_rounded, size: 16);
    }

    return Image.memory(
      iconPngBytes!,
      width: 16,
      height: 16,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        return const Icon(Icons.apps_rounded, size: 16);
      },
    );
  }
}

class TopBarTrayOverflowModule extends StatelessWidget {
  const TopBarTrayOverflowModule({
    super.key,
    required this.overflowCount,
    required this.highlighted,
    required this.onToggle,
  });

  final int overflowCount;
  final bool highlighted;
  final ValueChanged<PanelAnchor> onToggle;

  @override
  Widget build(BuildContext context) {
    return TopBarPanelTapTarget(
      alignment: PanelAlignment.right,
      onTap: onToggle,
      child: TopBarPill(
        icon: Icons.expand_more_rounded,
        label: '$overflowCount more',
        highlighted: highlighted,
      ),
    );
  }
}
