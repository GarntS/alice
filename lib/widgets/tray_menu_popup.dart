import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../tray_menu_controller.dart';
import '../rust_gen/tray_menu.dart';
import '../rust_gen/tray_menu_service.dart';

/// Owns an overlay in the dedicated popup view, not in the bar's clipped view.
class TrayMenuPopup extends StatefulWidget {
  const TrayMenuPopup({super.key, required this.controller});
  final TrayMenuController controller;
  @override
  State<TrayMenuPopup> createState() => _TrayMenuPopupState();
}

class _TrayMenuPopupState extends State<TrayMenuPopup> {
  late final ContextMenuController _overlay = ContextMenuController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.controller.snapshot == null) return;
      _overlay.show(
        context: context,
        contextMenuBuilder: (_) => AnimatedBuilder(
          animation: widget.controller,
          builder: (_, _) =>
              TrayContextMenuOverlay(controller: widget.controller),
        ),
      );
    });
  }

  @override
  void dispose() {
    _overlay.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _Entry {
  const _Entry.node(this.node) : secondary = false, separator = false;
  const _Entry.secondary() : node = null, secondary = true, separator = false;
  const _Entry.separator() : node = null, secondary = false, separator = true;
  final TrayMenuNode? node;
  final bool secondary;
  final bool separator;
  bool get isSeparator => separator || (node?.separator ?? false);
  bool get enabled => !isSeparator && (node?.enabled ?? true);
  String get label => secondary ? 'Secondary action' : (node?.label ?? '');
  bool get submenu => node?.submenu ?? false;
}

@visibleForTesting
Offset clampTrayMenuPosition(Offset desired, Size menu, Size bounds) => Offset(
  desired.dx.clamp(0.0, math.max(0.0, bounds.width - menu.width)),
  desired.dy.clamp(0.0, math.max(0.0, bounds.height - menu.height)),
);

class TrayContextMenuOverlay extends StatefulWidget {
  const TrayContextMenuOverlay({super.key, required this.controller});
  final TrayMenuController controller;
  @override
  State<TrayContextMenuOverlay> createState() => _TrayContextMenuOverlayState();
}

class _TrayContextMenuOverlayState extends State<TrayContextMenuOverlay> {
  final _focus = FocusNode();
  final List<int> _path = [];
  final List<Offset> _positions = [];
  final List<int> _parentRows = [];
  BigInt? _request;
  bool _preparing = false;
  final Map<String, GlobalKey> _rowKeys = {};
  int _column = 0;
  int _row = 0;
  double _width = 240;
  Size _bounds = Size.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  List<List<_Entry>> _columns() {
    final snapshot = widget.controller.snapshot;
    if (snapshot == null) return [];
    if (_request != snapshot.requestId) {
      _request = snapshot.requestId;
      _path.clear();
      _positions.clear();
      _parentRows.clear();
      _column = 0;
      _row = 0;
    }
    final root = <_Entry>[
      if (snapshot.secondarySupported) ...[
        const _Entry.secondary(),
        const _Entry.separator(),
      ],
      ...snapshot.root.children.where((node) => node.visible).map(_Entry.node),
    ];
    final columns = [root];
    if (_column == 0 && (_row >= root.length || !root[_row].enabled)) {
      _row = root.indexWhere((entry) => entry.enabled);
    }
    var children = snapshot.root.children;
    for (var depth = 0; depth < _path.length; depth++) {
      final matches = children.where(
        (node) =>
            node.id == _path[depth] &&
            node.visible &&
            node.enabled &&
            !node.separator,
      );
      if (matches.isEmpty || matches.first.children.isEmpty) {
        _path.removeRange(depth, _path.length);
        break;
      }
      children = matches.first.children;
      columns.add(
        children.where((node) => node.visible).map(_Entry.node).toList(),
      );
    }
    return columns;
  }

  double _height(List<_Entry> entries) => math.min(
    _bounds.height,
    8 + entries.fold<double>(0, (sum, row) => sum + (row.isSeparator ? 9 : 36)),
  );
  void _focusRow(int column, int row) {
    setState(() {
      _column = column;
      _row = row;
    });
    final context = _rowKeys['$column:$row']?.currentContext;
    if (context != null)
      Scrollable.ensureVisible(context, duration: Duration.zero);
  }

  TrayMenuNode? _find(TrayMenuNode root, int id) {
    if (root.id == id) return root;
    for (final child in root.children) {
      final found = _find(child, id);
      if (found != null) return found;
    }
    return null;
  }

  Future<void> _open(int column, int row, _Entry entry) async {
    var node = entry.node;
    if (node == null || !entry.enabled || !entry.submenu || _preparing) return;
    _preparing = true;
    final id = node.id;
    await widget.controller.prepareSubmenu(id);
    _preparing = false;
    final snapshot = widget.controller.snapshot;
    if (!mounted || snapshot == null) return;
    node = _find(snapshot.root, id);
    if (node == null || !node.enabled || !node.visible) return;
    final box =
        _rowKeys['$column:$row']?.currentContext?.findRenderObject()
            as RenderBox?;
    final rowTop = box?.localToGlobal(Offset.zero).dy ?? _positions[column].dy;
    final next = node.children
        .where((node) => node.visible)
        .map(_Entry.node)
        .toList();
    if (next.isEmpty || column >= _positions.length) return;
    final left = _positions[column].dx;
    final desiredX = left + _width * 2 > _bounds.width
        ? left - _width
        : left + _width;
    final position = clampTrayMenuPosition(
      Offset(desiredX, rowTop),
      Size(_width, _height(next)),
      _bounds,
    );
    setState(() {
      if (_path.length > column) _path.removeRange(column, _path.length);
      _path.add(id);
      if (_parentRows.length > column)
        _parentRows.removeRange(column, _parentRows.length);
      _parentRows.add(row);
      if (_positions.length > column + 1)
        _positions.removeRange(column + 1, _positions.length);
      _positions.add(position);
      _column = column + 1;
      _row = next.indexWhere((entry) => entry.enabled);
      if (_row < 0) _row = 0;
    });
  }

  void _activate(int column, int row, _Entry entry) {
    if (!entry.enabled || widget.controller.selecting || _preparing) return;
    if (entry.submenu) {
      _open(column, row, entry);
      return;
    }
    widget.controller.select(
      entry.secondary
          ? const TrayMenuSelection.secondary()
          : TrayMenuSelection.remote(id: entry.node!.id),
    );
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent)
      return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.controller.close();
      return KeyEventResult.handled;
    }
    final columns = _columns();
    if (columns.isEmpty) return KeyEventResult.ignored;
    _column = _column.clamp(0, columns.length - 1);
    final rows = columns[_column];
    final enabled = [
      for (var i = 0; i < rows.length; i++)
        if (rows[i].enabled) i,
    ];
    if (enabled.isEmpty) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.home ||
        key == LogicalKeyboardKey.end) {
      var index = enabled.indexOf(_row);
      if (key == LogicalKeyboardKey.home)
        index = 0;
      else if (key == LogicalKeyboardKey.end)
        index = enabled.length - 1;
      else
        index =
            (index + (key == LogicalKeyboardKey.arrowDown ? 1 : -1)) %
            enabled.length;
      _focusRow(_column, enabled[index]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft && _column > 0) {
      setState(() {
        _column--;
        _row = _parentRows[_column];
        _path.removeRange(_column, _path.length);
        _parentRows.removeRange(_column, _parentRows.length);
        _positions.removeRange(_column + 1, _positions.length);
      });
      return KeyEventResult.handled;
    }
    if (_row >= 0 &&
        _row < rows.length &&
        (key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space)) {
      if (key == LogicalKeyboardKey.arrowRight)
        _open(_column, _row, rows[_row]);
      else
        _activate(_column, _row, rows[_row]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _label(String raw) => raw
      .replaceAll('__', '\u0000')
      .replaceAll('_', '')
      .replaceAll('\u0000', '_');
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final origin = widget.controller.origin;
    if (origin == null || widget.controller.snapshot == null)
      return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        _bounds = Size(constraints.maxWidth, constraints.maxHeight);
        _width = math.min(240, _bounds.width);
        final columns = _columns();
        if (columns.isEmpty) return const SizedBox.shrink();
        final rootPosition = clampTrayMenuPosition(
          Offset(origin.popupPosition.dx - _width, origin.popupPosition.dy),
          Size(_width, _height(columns[0])),
          _bounds,
        );
        if (_positions.isEmpty)
          _positions.add(rootPosition);
        else
          _positions[0] = rootPosition;
        _column = _column.clamp(0, columns.length - 1);
        for (var i = 1; i < columns.length; i++) {
          _positions[i] = clampTrayMenuPosition(
            _positions[i],
            Size(_width, _height(columns[i])),
            _bounds,
          );
        }
        return Focus(
          autofocus: true,
          focusNode: _focus,
          onKeyEvent: _key,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.controller.close,
                  onSecondaryTap: widget.controller.close,
                ),
              ),
              for (var column = 0; column < columns.length; column++)
                Positioned(
                  left: _positions[column].dx,
                  top: _positions[column].dy,
                  width: _width,
                  child: GestureDetector(
                    onTap: () {},
                    child: Material(
                      elevation: 6,
                      borderRadius: BorderRadius.circular(4),
                      color: Theme.of(context).colorScheme.surface,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: _height(columns[column]),
                        ),
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (
                                  var row = 0;
                                  row < columns[column].length;
                                  row++
                                )
                                  _buildRow(
                                    context,
                                    column,
                                    row,
                                    columns[column][row],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRow(BuildContext context, int column, int row, _Entry entry) {
    if (entry.isSeparator)
      return const SizedBox(height: 9, child: Divider(height: 9));
    final node = entry.node;
    final enabled = entry.enabled && !widget.controller.selecting;
    final key = _rowKeys.putIfAbsent('$column:$row', GlobalKey.new);
    return Semantics(
      button: true,
      enabled: enabled,
      checked: node?.toggle == TrayMenuToggle.none
          ? null
          : node?.toggleState == 1,
      child: MouseRegion(
        onEnter: (_) {
          if (!enabled) return;
          _focusRow(column, row);
          if (entry.submenu &&
              (column >= _path.length || _path[column] != node!.id)) {
            _open(column, row, entry);
          } else if (!entry.submenu && column < _path.length) {
            setState(() {
              _path.removeRange(column, _path.length);
              _parentRows.removeRange(column, _parentRows.length);
              _positions.removeRange(column + 1, _positions.length);
            });
          }
        },
        child: InkWell(
          key: key,
          onTap: enabled ? () => _activate(column, row, entry) : null,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: _column == column && _row == row
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                : null,
            child: Opacity(
              opacity: enabled ? 1 : 0.45,
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: Text(
                      node?.toggleState == 1
                          ? (node?.toggle == TrayMenuToggle.radio ? '●' : '✓')
                          : '',
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _label(entry.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (entry.submenu) const Text('›'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
