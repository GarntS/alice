import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../rust_gen/caldav/models.dart';
import '../alice_icon.dart';
import 'task_panel_model.dart';
import 'task_row.dart';

class TaskPanel extends StatefulWidget {
  const TaskPanel({
    super.key,
    required this.tasks,
    required this.syncState,
    required this.onRefresh,
    required this.onCompletion,
    this.now,
    this.scheduleDateRollover = true,
  });

  final List<NormalizedTask> tasks;
  final CalDavSyncState syncState;
  final Future<void> Function() onRefresh;
  final Future<void> Function(TaskResourceIdentity identity, bool completed)
  onCompletion;
  final DateTime Function()? now;
  final bool scheduleDateRollover;

  @override
  State<TaskPanel> createState() => TaskPanelState();
}

class TaskPanelState extends State<TaskPanel> {
  final Map<String, bool> _optimisticCompletion = {};
  final Set<String> _pending = {};
  bool _refreshPending = false;
  String? _actionError;
  Timer? _dateTimer;
  final ScrollController _taskScrollController = ScrollController();
  late DateTime _today;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _today = _dateOnly(_now);
    if (widget.scheduleDateRollover) _scheduleRollover();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestRefresh());
  }

  @override
  void didUpdateWidget(TaskPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final authoritative = {
      for (final task in widget.tasks)
        task.identity.resourceHref: task.status == TaskStatus.completed,
    };
    _optimisticCompletion.removeWhere(
      (href, completed) => authoritative[href] == completed,
    );
    _pending.removeWhere((href) => !authoritative.containsKey(href));
  }

  @override
  void dispose() {
    _dateTimer?.cancel();
    _taskScrollController.dispose();
    super.dispose();
  }

  @visibleForTesting
  void refreshLocalDate() {
    setState(() => _today = _dateOnly(_now));
  }

  void _scheduleRollover() {
    _dateTimer?.cancel();
    final now = _now;
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _dateTimer = Timer(tomorrow.difference(now), () {
      if (!mounted) return;
      refreshLocalDate();
      _scheduleRollover();
    });
  }

  Future<void> _requestRefresh() async {
    if (_refreshPending ||
        widget.syncState.freshness == CalDavFreshness.loading) {
      return;
    }
    setState(() => _refreshPending = true);
    try {
      await widget.onRefresh();
    } catch (error) {
      if (mounted) setState(() => _actionError = _safeActionError(error));
    } finally {
      if (mounted) setState(() => _refreshPending = false);
    }
  }

  Future<void> _toggle(NormalizedTask task, bool completed) async {
    final href = task.identity.resourceHref;
    if (_pending.contains(href)) return;
    setState(() {
      _pending.add(href);
      _optimisticCompletion[href] = completed;
      _actionError = null;
    });
    try {
      await widget.onCompletion(task.identity, completed);
      if (mounted) setState(() => _pending.remove(href));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pending.remove(href);
        _optimisticCompletion.remove(href);
        _actionError = _safeActionError(error);
      });
    }
  }

  List<NormalizedTask> get _effectiveTasks => widget.tasks
      .map((task) {
        final override = _optimisticCompletion[task.identity.resourceHref];
        if (override == null) return task;
        return NormalizedTask(
          identity: task.identity,
          uid: task.uid,
          title: task.title,
          collectionName: task.collectionName,
          dueDate: task.dueDate,
          completedAtUnixSecs: override
              ? _now.millisecondsSinceEpoch ~/ 1000
              : null,
          status: override ? TaskStatus.completed : TaskStatus.active,
          priority: task.priority,
        );
      })
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final effective = _effectiveTasks;
    final sections = buildTaskSections(effective, today: _today);
    final activeCount = effective
        .where((task) => task.status == TaskStatus.active)
        .length;
    final dueToday = effective.where((task) {
      return task.status == TaskStatus.active &&
          task.dueDate == _dateKey(_today);
    }).length;
    final overdue = effective.where((task) {
      final due = task.dueDate == null
          ? null
          : DateTime.tryParse(task.dueDate!);
      return task.status == TaskStatus.active &&
          due != null &&
          _dateOnly(due).isBefore(_today);
    }).length;
    final noCacheLoading =
        widget.syncState.freshness == CalDavFreshness.loading &&
        !widget.syncState.hasCachedData &&
        effective.isEmpty;
    final currentEmpty =
        widget.syncState.freshness == CalDavFreshness.current &&
        sections.isEmpty;

    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('task-panel'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Tasks',
                  key: const ValueKey('task-panel-title'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                    fontSize: 20,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('task-panel-refresh'),
                tooltip: 'Refresh tasks',
                color: theme.colorScheme.primary,
                onPressed:
                    _refreshPending ||
                        widget.syncState.freshness == CalDavFreshness.loading
                    ? null
                    : _requestRefresh,
                icon: _refreshPending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const AliceIcon(AliceIcons.refresh),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _TaskSummary(
          activeCount: activeCount,
          dueToday: dueToday,
          overdue: overdue,
        ),
        const SizedBox(height: 10),
        if (widget.syncState.freshness == CalDavFreshness.stale)
          const _StateBanner(
            key: ValueKey('task-panel-stale'),
            icon: AliceIcons.cloudSlash,
            message: 'Showing stale cached tasks',
          ),
        if (widget.syncState.freshness == CalDavFreshness.error)
          _StateBanner(
            key: const ValueKey('task-panel-sync-error'),
            icon: AliceIcons.warningCircle,
            message: widget.syncState.error ?? 'Task synchronization failed',
            error: true,
          ),
        if (_actionError != null)
          _StateBanner(
            key: const ValueKey('task-panel-action-error'),
            icon: AliceIcons.warningCircle,
            message: _actionError!,
            error: true,
          ),
        if (noCacheLoading)
          const _PanelPlaceholder(
            key: ValueKey('task-panel-loading'),
            icon: AliceIcons.sync,
            message: 'Loading tasks…',
            loading: true,
          )
        else if (currentEmpty)
          const _PanelPlaceholder(
            key: ValueKey('task-panel-empty'),
            icon: AliceIcons.checkCircle,
            message: 'No tasks to show',
          )
        else
          Flexible(
            child: Scrollbar(
              controller: _taskScrollController,
              child: ListView.builder(
                controller: _taskScrollController,
                key: const ValueKey('task-panel-list'),
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: sections.length,
                itemBuilder: (context, index) => _TaskSectionView(
                  section: sections[index],
                  today: _today,
                  pending: _pending,
                  onToggle: _toggle,
                ),
              ),
            ),
          ),
        if (widget.syncState.lastSuccessUnixSecs != null)
          _LastSyncFooter(timestamp: widget.syncState.lastSuccessUnixSecs!),
      ],
    );
  }
}

class _TaskSectionView extends StatelessWidget {
  const _TaskSectionView({
    required this.section,
    required this.today,
    required this.pending,
    required this.onToggle,
  });

  final TaskSection section;
  final DateTime today;
  final Set<String> pending;
  final Future<void> Function(NormalizedTask task, bool completed) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: ValueKey('task-section-${section.kind.name}-${section.date}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          key: ValueKey(
            'task-section-label-${section.kind.name}-${section.date}',
          ),
          padding: const EdgeInsets.fromLTRB(2, 9, 2, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _TaskSectionTitle(section: section, today: today),
              ),
              Text(
                '${section.tasks.length} ${section.tasks.length == 1 ? 'task' : 'tasks'}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
        for (final task in section.tasks)
          CalDavTaskRow(
            task: task,
            completed: task.status == TaskStatus.completed,
            pending: pending.contains(task.identity.resourceHref),
            onChanged: (completed) => onToggle(task, completed),
          ),
      ],
    );
  }
}

class _TaskSectionTitle extends StatelessWidget {
  const _TaskSectionTitle({required this.section, required this.today});

  final TaskSection section;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.titleSmall?.copyWith(
      color: theme.colorScheme.onSurface,
      fontSize: 15,
      fontWeight: FontWeight.w700,
      height: 1,
    );
    final date = section.date;
    if (date == null ||
        section.kind == TaskSectionKind.undated ||
        section.kind == TaskSectionKind.completedToday) {
      return Text(taskSectionHeader(section, today), style: baseStyle);
    }

    final prefix = section.kind == TaskSectionKind.today
        ? 'Today - ${date.day} '
        : '${date.day} ';
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: prefix),
          TextSpan(
            text: taskMonthName(date.month),
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (date.year != today.year) TextSpan(text: ' ${date.year}'),
        ],
      ),
      style: baseStyle?.copyWith(color: theme.colorScheme.onSurface),
    );
  }
}

class _TaskSummary extends StatelessWidget {
  const _TaskSummary({
    required this.activeCount,
    required this.dueToday,
    required this.overdue,
  });

  final int activeCount;
  final int dueToday;
  final int overdue;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      key: const ValueKey('task-panel-summary'),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _TaskMetric(
                icon: AliceIcons.listChecks,
                value: activeCount,
                label: 'Active',
                color: colors.primary,
              ),
            ),
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _TaskMetric(
                icon: AliceIcons.calendar,
                value: dueToday,
                label: 'Today',
                color: colors.onSurface,
              ),
            ),
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _TaskMetric(
                icon: AliceIcons.warningCircle,
                value: overdue,
                label: 'Overdue',
                color: colors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskMetric extends StatelessWidget {
  const _TaskMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final AliceIconDescriptor icon;
  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AliceIcon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$value',
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
              TextSpan(
                text: ' $label',
                style: TextStyle(color: color, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          key: ValueKey('task-summary-${label.toLowerCase()}'),
          style: theme.textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _PanelPlaceholder extends StatelessWidget {
  const _PanelPlaceholder({
    super.key,
    required this.icon,
    required this.message,
    this.loading = false,
  });

  final AliceIconDescriptor icon;
  final String message;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            AliceIcon(icon, color: theme.colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _LastSyncFooter extends StatelessWidget {
  const _LastSyncFooter({required this.timestamp});

  final int timestamp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('task-panel-last-success'),
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AliceIcon(
            AliceIcons.cloudCheck,
            size: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              'Last successful sync: ${_formatLastSuccess(timestamp)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StateBanner extends StatelessWidget {
  const _StateBanner({
    super.key,
    required this.icon,
    required this.message,
    this.error = false,
  });

  final AliceIconDescriptor icon;
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.tertiary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 3, 4, 9),
      child: Row(
        children: [
          AliceIcon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _formatLastSuccess(int seconds) {
  final value = DateTime.fromMillisecondsSinceEpoch(
    seconds * 1000,
    isUtc: true,
  ).toLocal();
  return '${value.day}/${value.month}/${value.year} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

String _safeActionError(Object error) {
  final message = error.toString().replaceAll(
    RegExp(r'authorization:\s*[^\n]+', caseSensitive: false),
    'Authorization: [REDACTED]',
  );
  return message.length <= 240 ? message : '${message.substring(0, 240)}…';
}
