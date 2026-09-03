import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../rust_gen/state.dart';
import '../alice_icon.dart';
import 'panel_shell.dart';

class TrayPanel extends StatelessWidget {
  const TrayPanel({
    super.key,
    required this.trayItems,
    required this.maxVisibleTrayItems,
    required this.onTrayAction,
  });

  final List<TrayItemSnapshot> trayItems;
  final int maxVisibleTrayItems;
  final Future<void> Function(TrayItemSnapshot) onTrayAction;

  @override
  Widget build(BuildContext context) {
    final overflow = trayItems.skip(
      maxVisibleTrayItems > 0 ? maxVisibleTrayItems - 1 : 0,
    );
    final items = overflow.toList();
    return PanelShell(
      title: 'Tray Overflow',
      child: items.isEmpty
          ? const Text('No overflow tray items.')
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: items
                    .map(
                      (item) => InkWell(
                        onTap: () => onTrayAction(item),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.secondary.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              _TrayItemIcon(iconPngBytes: item.iconPngBytes),
                              const SizedBox(width: 8),
                              Expanded(child: Text(item.label)),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
    );
  }
}

class _TrayItemIcon extends StatelessWidget {
  const _TrayItemIcon({required this.iconPngBytes});

  final Uint8List? iconPngBytes;

  @override
  Widget build(BuildContext context) {
    if (iconPngBytes == null || iconPngBytes!.isEmpty) {
      return const AliceIcon(AliceIcons.dotsNine, size: 18);
    }

    return Image.memory(
      iconPngBytes!,
      width: 18,
      height: 18,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return const AliceIcon(AliceIcons.dotsNine, size: 18);
      },
    );
  }
}
