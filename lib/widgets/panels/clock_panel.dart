import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../alice_config.dart';
import '../../rust_gen/api.dart' show fetchCalendarEvents;
import '../../rust_gen/state.dart';
import 'panel_shell.dart';

Color _onAccent(Color accent) =>
    ThemeData.estimateBrightnessForColor(accent) == Brightness.light
    ? Colors.black
    : Colors.white;

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const _weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

// ---------------------------------------------------------------------------
// ClockPanel — stateful so it tracks the selected calendar date + events
// ---------------------------------------------------------------------------

class ClockPanel extends StatefulWidget {
  const ClockPanel({super.key, required this.config, required this.snapshot});

  final AliceConfig config;
  final ClockSnapshot snapshot;

  @override
  State<ClockPanel> createState() => _ClockPanelState();
}

class _ClockPanelState extends State<ClockPanel> {
  late DateTime _selectedDate;
  CalendarFetchResult? _fetchResult;
  bool _loading = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _fetchEvents(_selectedDate);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchEvents(DateTime date) async {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    setState(() => _loading = true);
    final result = await fetchCalendarEvents(date: dateStr);
    if (!mounted) return;
    setState(() {
      _fetchResult = result;
      _loading = false;
    });
    _updatePollTimer(result, date);
  }

  void _updatePollTimer(CalendarFetchResult result, DateTime date) {
    if (result.status == 'polling' || result.status == 'needs_auth') {
      _pollTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
        _fetchEvents(date);
      });
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _onDateSelected(DateTime date) {
    setState(() => _selectedDate = date);
    _fetchEvents(date);
  }

  @override
  Widget build(BuildContext context) {
    final nowUtc = DateTime.now().toUtc();
    final localTimeZoneLabel =
        widget.config.localTimeZoneLabel ?? widget.snapshot.timeZoneCode;
    return PanelShell(
      title: 'World Clock',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ClockRow(
            label: localTimeZoneLabel,
            dateLabel: widget.snapshot.dateLabel,
            timeLabel: widget.snapshot.timeLabel,
            highlighted: true,
          ),
          const SizedBox(height: 8),
          ...widget.config.timeZones.map((zone) {
            final zoned = nowUtc.add(Duration(hours: zone.offsetHours));
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ClockRow(
                label: zone.label,
                dateLabel:
                    '${zoned.day.toString().padLeft(2, '0')} ${_shortMonthName(zoned.month)}',
                timeLabel:
                    '${zoned.hour.toString().padLeft(2, '0')}:${zoned.minute.toString().padLeft(2, '0')}',
              ),
            );
          }),
          const SizedBox(height: 16),
          AliceCalendar(
            selectedDate: _selectedDate,
            onDateSelected: _onDateSelected,
          ),
          const SizedBox(height: 16),
          _EventsSection(result: _fetchResult, loading: _loading),
        ],
      ),
    );
  }

  String _shortMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }
}

// ---------------------------------------------------------------------------
// Clock rows
// ---------------------------------------------------------------------------

class _ClockRow extends StatelessWidget {
  const _ClockRow({
    required this.label,
    required this.dateLabel,
    required this.timeLabel,
    this.highlighted = false,
  });

  final String label;
  final String dateLabel;
  final String timeLabel;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: highlighted
          ? BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
          Text(dateLabel),
          const SizedBox(width: 12),
          Text(timeLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AliceCalendar
// ---------------------------------------------------------------------------

class AliceCalendar extends StatefulWidget {
  const AliceCalendar({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;

  @override
  State<AliceCalendar> createState() => _AliceCalendarState();
}

class _AliceCalendarState extends State<AliceCalendar> {
  late DateTime _displayedMonth;

  @override
  void initState() {
    super.initState();
    _displayedMonth = DateTime(
      widget.selectedDate.year,
      widget.selectedDate.month,
    );
  }

  void _prevMonth() => setState(() {
    _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month - 1);
  });

  void _nextMonth() => setState(() {
    _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1);
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final year = _displayedMonth.year;
    final month = _displayedMonth.month;

    final firstDay = DateTime(year, month, 1);
    final leadingBlanks = (firstDay.weekday - 1) % 7;
    final daysInMonth = DateTime(year, month + 1, 0).day;

    final cells = <DateTime>[];
    for (var i = leadingBlanks; i > 0; i--) {
      cells.add(DateTime(year, month, 1 - i));
    }
    for (var d = 1; d <= daysInMonth; d++) {
      cells.add(DateTime(year, month, d));
    }
    while (cells.length < 42) {
      final last = cells.last;
      cells.add(last.add(const Duration(days: 1)));
    }

    final rows = List.generate(6, (r) => cells.sublist(r * 7, r * 7 + 7));
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.4);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${_monthNames[month - 1]} ',
                        style: TextStyle(color: theme.colorScheme.primary),
                      ),
                      TextSpan(text: '$year'),
                    ],
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
              ),
            ),
            InkWell(
              onTap: _prevMonth,
              borderRadius: BorderRadius.circular(8),
              child: const SizedBox(
                width: 28,
                height: 28,
                child: Icon(Icons.chevron_left_rounded, size: 18),
              ),
            ),
            InkWell(
              onTap: _nextMonth,
              borderRadius: BorderRadius.circular(8),
              child: const SizedBox(
                width: 28,
                height: 28,
                child: Icon(Icons.chevron_right_rounded, size: 18),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: _weekdayLabels
              .map(
                (label) => Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 4),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: rows
              .map(
                (week) => Row(
                  children: week
                      .map(
                        (date) => _DayCell(
                          date: date,
                          isCurrentMonth: date.month == month,
                          isSelected:
                              date.year == widget.selectedDate.year &&
                              date.month == widget.selectedDate.month &&
                              date.day == widget.selectedDate.day,
                          onTap: widget.onDateSelected,
                        ),
                      )
                      .toList(),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.isCurrentMonth,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime date;
  final bool isCurrentMonth;
  final bool isSelected;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    final textColor = isSelected
        ? _onAccent(primary)
        : isCurrentMonth
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface.withValues(alpha: 0.3);

    return Expanded(
      child: InkWell(
        onTap: () => onTap(date),
        borderRadius: BorderRadius.circular(999),
        child: AspectRatio(
          aspectRatio: 1.0,
          child: Center(
            child: Container(
              width: 30,
              height: 30,
              decoration: isSelected
                  ? BoxDecoration(shape: BoxShape.circle, color: primary)
                  : null,
              child: Center(
                child: Text(
                  '${date.day}',
                  style: theme.textTheme.bodySmall?.copyWith(color: textColor),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Events section
// ---------------------------------------------------------------------------

class _EventsSection extends StatelessWidget {
  const _EventsSection({required this.result, required this.loading});

  final CalendarFetchResult? result;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }

    final r = result;
    if (r == null || r.status == 'not_configured') return const SizedBox.shrink();

    if (r.status == 'needs_auth' || r.status == 'polling') {
      return _AuthPrompt(url: r.authUrl ?? '', code: r.authCode ?? '');
    }

    if (r.status == 'error') {
      return _ErrorText(message: r.errorMessage ?? 'Unknown error');
    }

    if (r.status == 'ready') {
      return _EventsList(events: r.events);
    }

    return const SizedBox.shrink();
  }
}

class _AuthPrompt extends StatelessWidget {
  const _AuthPrompt({required this.url, required this.code});

  final String url;
  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connect Google Calendar', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              'Open the link in your browser and authorize access. This window will update automatically.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 6),
            Text(url, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () => Clipboard.setData(ClipboardData(text: url)),
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                visualDensity: VisualDensity.compact,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy_rounded, size: 14),
                  SizedBox(width: 6),
                  Text('Copy Link to Clipboard'),
                ],
              ),
            ),
            if (code.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('Code: ', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  Text(
                    code,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Copy code',
                    onPressed: () => Clipboard.setData(ClipboardData(text: code)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      message,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.error,
      ),
    );
  }
}

class _EventsList extends StatelessWidget {
  const _EventsList({required this.events});

  final List<CalendarEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      final theme = Theme.of(context);
      return Text(
        'No events.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      );
    }

    final allDay = events.where((e) => e.isAllDay).toList();
    final timed = events.where((e) => !e.isAllDay).toList();
    final showDivider = allDay.isNotEmpty && timed.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...allDay.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _EventTile(event: e),
        )),
        if (showDivider)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Divider(),
          ),
        ...timed.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _EventTile(event: e),
        )),
      ],
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final dotColor = _parseColor(event.calendarColor, theme.colorScheme.primary);

    final timeLabel = event.isAllDay
        ? 'All Day'
        : '${event.startLabel} \u2013 ${event.endLabel}';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event.title, style: theme.textTheme.bodyMedium),
              Text(
                timeLabel,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _parseColor(String hex, Color fallback) {
    if (hex.length == 7 && hex.startsWith('#')) {
      final value = int.tryParse(hex.substring(1), radix: 16);
      if (value != null) return Color(value | 0xFF000000);
    }
    return fallback;
  }
}
