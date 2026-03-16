import 'package:flutter/material.dart';

class PanelShell extends StatelessWidget {
  const PanelShell({
    super.key,
    required this.title,
    required this.child,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.titleAlign = TextAlign.start,
  });

  final String? title;
  final Widget child;
  final CrossAxisAlignment crossAxisAlignment;
  final TextAlign titleAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleText = title?.trim() ?? '';
    final hasTitle = titleText.isNotEmpty;

    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasTitle) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              titleText,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
              textAlign: titleAlign,
            ),
          ),
          const SizedBox(height: 12),
        ],
        child,
      ],
    );
  }
}
