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

Color _parseHexColor(String hex, [Color fallback = Colors.transparent]) {
  if (hex.length == 7 && hex.startsWith('#')) {
    final value = int.tryParse(hex.substring(1), radix: 16);
    if (value != null) return Color(value | 0xFF000000);
  }
  return fallback;
}

String _pad(int n) => n.toString().padLeft(2, '0');

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

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

  Map<String, List<Color>> _indicators = {};
  int _calYear = DateTime.now().year;
  int _calMonth = DateTime.now().month;

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
    if (result.status == 'ready') {
      _refreshIndicators(_calYear, _calMonth);
    }
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

  Future<void> _refreshIndicators(int year, int month) async {
    final daysInMonth = DateTime(year, month + 1, 0).day;

    final futures = List.generate(daysInMonth, (i) {
      final dateStr = '$year-${_pad(month)}-${_pad(i + 1)}';
      return fetchCalendarEvents(date: dateStr);
    });
    final results = await Future.wait(futures);
    if (!mounted) return;

    final newIndicators = <String, List<Color>>{};
    for (var i = 0; i < daysInMonth; i++) {
      final result = results[i];
      if (result.status != 'ready' || result.events.isEmpty) continue;
      final colors = _extractUniqueColors(result.events);
      if (colors.isNotEmpty) {
        newIndicators['$year-${_pad(month)}-${_pad(i + 1)}'] = colors;
      }
    }
    setState(() => _indicators = newIndicators);
  }

  List<Color> _extractUniqueColors(List<CalendarEvent> events) {
    final seen = <String>{};
    final hexes = <String>[];
    for (final e in events) {
      if (e.calendarColor.isNotEmpty && seen.add(e.calendarColor)) {
        hexes.add(e.calendarColor);
      }
    }
    hexes.sort();
    return hexes.take(3).map((h) => _parseHexColor(h)).toList();
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
            indicators: _indicators,
            onMonthChanged: (y, m) {
              _calYear = y;
              _calMonth = m;
              _refreshIndicators(y, m);
            },
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: _EventsSection(result: _fetchResult, loading: _loading),
            ),
          ),
        ],
      ),
    );
  }

  String _shortMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
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
    this.indicators = const {},
    this.onMonthChanged,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final Map<String, List<Color>> indicators;
  final void Function(int year, int month)? onMonthChanged;

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

  void _prevMonth() {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month - 1,
      );
    });
    widget.onMonthChanged?.call(_displayedMonth.year, _displayedMonth.month);
  }

  void _nextMonth() {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + 1,
      );
    });
    widget.onMonthChanged?.call(_displayedMonth.year, _displayedMonth.month);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final year = _displayedMonth.year;
    final month = _displayedMonth.month;

    final firstDay = DateTime(year, month, 1);
    final leadingBlanks = firstDay.weekday % 7;
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
    final today = DateTime.now();
    final selectedIsToday =
        widget.selectedDate.year == today.year &&
        widget.selectedDate.month == today.month &&
        widget.selectedDate.day == today.day;

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
                          isToday:
                              !selectedIsToday &&
                              date.year == today.year &&
                              date.month == today.month &&
                              date.day == today.day,
                          onTap: widget.onDateSelected,
                          dotColors:
                              widget
                                  .indicators['${date.year}-${_pad(date.month)}-${_pad(date.day)}'] ??
                              const [],
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
    required this.isToday,
    required this.onTap,
    this.dotColors = const [],
  });

  final DateTime date;
  final bool isCurrentMonth;
  final bool isSelected;
  final bool isToday;
  final ValueChanged<DateTime> onTap;
  final List<Color> dotColors;

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
        child: Center(
          child: Container(
            width: 30,
            height: dotColors.isEmpty ? 30 : 38,
            decoration: isSelected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: primary,
                  )
                : isToday
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: primary.withValues(alpha: 0.12),
                  )
                : null,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${date.day}',
                  style: theme.textTheme.bodySmall?.copyWith(color: textColor),
                ),
                if (dotColors.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  _buildDots(dotColors, isCurrentMonth),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDots(List<Color> colors, bool currentMonth) {
    if (colors.isEmpty) return const SizedBox.shrink();
    final opacity = currentMonth ? 1.0 : 0.3;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < colors.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors[i].withValues(alpha: opacity),
            ),
          ),
        ],
      ],
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
    if (r == null || r.status == 'not_configured')
      return const SizedBox.shrink();

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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
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
                  Text(
                    'Code: ',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  Text(
                    code,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Copy code',
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: code)),
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
        ...allDay.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _EventTile(event: e),
          ),
        ),
        if (showDivider)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Divider(),
          ),
        ...timed.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _EventTile(event: e),
          ),
        ),
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
    final dotColor = _parseHexColor(
      event.calendarColor,
      theme.colorScheme.primary,
    );

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
}
