import 'package:material_ui/material_ui.dart';

import '../../alice_theme.dart';
import '../alice_icon.dart';

class TopBarPill extends StatelessWidget {
  const TopBarPill({
    super.key,
    this.icon,
    this.leading,
    required this.label,
    this.labelWidget,
    this.highlighted = false,
  }) : assert(icon != null || leading != null);

  final AliceIconDescriptor? icon;
  final Widget? leading;
  final String label;
  final Widget? labelWidget;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = AliceColorTokens.of(context);

    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: highlighted ? colors.accentSubtle : colors.raisedContainer,
        borderRadius: BorderRadius.circular(10),
        border: highlighted ? Border.all(color: colors.accentBorder) : null,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading ?? AliceIcon(icon!, size: 16),
            if (labelWidget != null || label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Flexible(
                child:
                    labelWidget ??
                    Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
