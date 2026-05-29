import 'package:flutter/material.dart';

import '../../rust_gen/state.dart';

class TopBarWorkspaceModule extends StatelessWidget {
  const TopBarWorkspaceModule({
    super.key,
    required this.workspaces,
    required this.onWorkspaceTap,
  });

  final List<WorkspaceSnapshot> workspaces;
  final ValueChanged<String> onWorkspaceTap;

  @override
  Widget build(BuildContext context) {
    if (workspaces.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const ValueKey('top-bar-workspace-group-background'),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondary.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: workspaces
              .map(
                (workspace) => _TopBarWorkspaceChip(
                  workspace: workspace,
                  onTap: () => onWorkspaceTap(workspace.label),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _TopBarWorkspaceChip extends StatelessWidget {
  const _TopBarWorkspaceChip({required this.workspace, required this.onTap});

  final WorkspaceSnapshot workspace;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = workspace.isFocused
        ? theme.colorScheme.primary
        : workspace.isVisible
        ? theme.colorScheme.secondary
        : Colors.transparent;
    final foreground = workspace.isFocused
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minHeight: 28),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          /*border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
            ),*/
        ),
        child: Text(
          workspace.label,
          style: TextStyle(
            color: foreground,
            fontSize: 12,
            fontWeight: workspace.isFocused ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
