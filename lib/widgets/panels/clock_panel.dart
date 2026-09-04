import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../alice_config.dart';
import '../../alice_theme.dart';
import '../../rust_gen/api.dart' show fetchCalendarEvents;
import '../../rust_gen/state.dart';
import '../alice_icon.dart';
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

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime _monthOnly(DateTime date) => DateTime(date.year, date.month);

bool _sameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;

bool _sameDate(DateTime a, DateTime b) => _sameMonth(a, b) && a.day == b.day;

String _dateKey(DateTime date) =>
    '${date.year}-${_pad(date.month)}-${_pad(date.day)}';

// ---------------------------------------------------------------------------
// ClockPanel — stateful so it tracks the selected calendar date + events
// ---------------------------------------------------------------------------

typedef CalendarEventFetcher =
    Future<CalendarFetchResult> Function({required String date});

class ClockPanel extends StatefulWidget {
  const ClockPanel({
    super.key,
    required this.config,
    required this.snapshot,
    this.calendarEventFetcher = fetchCalendarEvents,
  });

  final AliceConfig config;
  final ClockSnapshot snapshot;
  final CalendarEventFetcher calendarEventFetcher;

  @override
  State<ClockPanel> createState() => _ClockPanelState();
}

class _ClockPanelState extends State<ClockPanel> {
  late DateTime _selectedDate;
  CalendarFetchResult? _fetchResult;
  bool _loading = false;
  Timer? _pollTimer;
  int _eventRequestGeneration = 0;

  Map<String, List<Color>> _indicators = {};
  DateTime _calendarMonth = _monthOnly(DateTime.now());
  int _indicatorRequestGeneration = 0;

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
    final requestGeneration = ++_eventRequestGeneration;
    setState(() => _loading = true);
    final result = await widget.calendarEventFetcher(date: _dateKey(date));
    if (!mounted ||
        requestGeneration != _eventRequestGeneration ||
        !_sameDate(date, _selectedDate)) {
      return;
    }
    setState(() {
      _fetchResult = result;
      _loading = false;
    });
    _updatePollTimer(result);
    if (result.status == 'ready') {
      _refreshIndicators(_calendarMonth);
    }
  }

  void _updatePollTimer(CalendarFetchResult result) {
    if (result.status == 'polling' || result.status == 'needs_auth') {
      _pollTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
        _fetchEvents(_selectedDate);
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

  Future<void> _refreshIndicators(DateTime month) async {
    final requestGeneration = ++_indicatorRequestGeneration;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    final dates = List.generate(
      daysInMonth,
      (i) => DateTime(month.year, month.month, i + 1),
    );
    final futures = dates.map(
      (date) => widget.calendarEventFetcher(date: _dateKey(date)),
    );
    final results = await Future.wait(futures);
    if (!mounted ||
        requestGeneration != _indicatorRequestGeneration ||
        !_sameMonth(month, _calendarMonth)) {
      return;
    }

    final newIndicators = <String, List<Color>>{};
    for (var i = 0; i < daysInMonth; i++) {
      final result = results[i];
      if (result.status != 'ready' || result.events.isEmpty) continue;
      final colors = _extractUniqueColors(result.events);
      if (colors.isNotEmpty) {
        newIndicators[_dateKey(dates[i])] = colors;
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
    // The fixed-height panel must accommodate six calendar rows, time zones,
    // and an arbitrary event list. Scroll the complete clock content rather
    // than allowing PanelShell's Column to overflow its height constraint.
    return SingleChildScrollView(
      child: PanelShell(
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
              onMonthChanged: (month) {
                _calendarMonth = month;
                _refreshIndicators(month);
              },
            ),
            const SizedBox(height: 16),
            _EventsSection(result: _fetchResult, loading: _loading),
          ],
        ),
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
    final colors = AliceColorTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: highlighted
          ? BoxDecoration(
              color: colors.accentSubtle,
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
  final ValueChanged<DateTime>? onMonthChanged;

  @override
  State<AliceCalendar> createState() => _AliceCalendarState();
}

class _AliceCalendarState extends State<AliceCalendar> {
  late DateTime _displayedMonth;

  @override
  void initState() {
    super.initState();
    _displayedMonth = _monthOnly(widget.selectedDate);
  }

  void _prevMonth() {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month - 1,
      );
    });
    widget.onMonthChanged?.call(_displayedMonth);
  }

  void _nextMonth() {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + 1,
      );
    });
    widget.onMonthChanged?.call(_displayedMonth);
  }

  List<List<DateTime>> _buildMonthRows(DateTime month) {
    final firstDay = _monthOnly(month);
    final firstCell = firstDay.subtract(Duration(days: firstDay.weekday % 7));
    final cells = List.generate(42, (i) => firstCell.add(Duration(days: i)));

    return List.generate(6, (row) => cells.sublist(row * 7, row * 7 + 7));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final month = _displayedMonth;
    final rows = _buildMonthRows(month);
    final today = _dateOnly(DateTime.now());

    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.4);
    final selectedIsToday = _sameDate(widget.selectedDate, today);

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
                        text: '${_monthNames[month.month - 1]} ',
                        style: TextStyle(color: theme.colorScheme.primary),
                      ),
                      TextSpan(text: '${month.year}'),
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
                child: AliceIcon(AliceIcons.caretLeft, size: 18),
              ),
            ),
            InkWell(
              onTap: _nextMonth,
              borderRadius: BorderRadius.circular(8),
              child: const SizedBox(
                width: 28,
                height: 28,
                child: AliceIcon(AliceIcons.caretRight, size: 18),
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
                          isCurrentMonth: _sameMonth(date, month),
                          isSelected: _sameDate(date, widget.selectedDate),
                          isToday: !selectedIsToday && _sameDate(date, today),
                          onTap: widget.onDateSelected,
                          dotColors:
                              widget.indicators[_dateKey(date)] ?? const [],
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
        key: ValueKey('calendar-day-${_dateKey(date)}'),
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
                  AliceIcon(AliceIcons.copy, size: 14),
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
                    icon: const AliceIcon(AliceIcons.copy, size: 16),
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
