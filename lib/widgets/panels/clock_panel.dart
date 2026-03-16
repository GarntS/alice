import 'package:flutter/material.dart';

import '../../alice_config.dart';
import '../../rust_gen/state.dart';
import 'panel_shell.dart';

Color _onAccent(Color accent) =>
    ThemeData.estimateBrightnessForColor(accent) == Brightness.light
    ? Colors.black
    : Colors.white;

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

const _weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

class ClockPanel extends StatelessWidget {
  const ClockPanel({super.key, required this.config, required this.snapshot});

  final AliceConfig config;
  final ClockSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final nowUtc = DateTime.now().toUtc();
    final localTimeZoneLabel =
        config.localTimeZoneLabel ?? snapshot.timeZoneCode;
    final today = DateTime.now();
    return PanelShell(
      title: 'World Clock',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ClockRow(
            label: localTimeZoneLabel,
            dateLabel: snapshot.dateLabel,
            timeLabel: snapshot.timeLabel,
            highlighted: true,
          ),
          const SizedBox(height: 8),
          ...config.timeZones.map((zone) {
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
          AliceCalendar(selectedDate: today, onDateSelected: (_) {}),
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
