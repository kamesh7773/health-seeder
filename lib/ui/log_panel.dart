import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The output pane, which is the whole point of the tool.
///
/// Everything here writes into HealthKit and then reads it straight back, so
/// the log *is* the result — a fixed 170px strip meant a night's per-stage
/// totals scrolled out of view before they could be read. It can be dragged to
/// any height, snapped full-screen with one tap, and copied out.
class LogPanel extends StatefulWidget {
  final List<String> lines;
  final ScrollController controller;
  final VoidCallback onClear;

  const LogPanel({
    super.key,
    required this.lines,
    required this.controller,
    required this.onClear,
  });

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  static const _minHeight = 90.0;
  static const _defaultHeight = 210.0;

  double _height = _defaultHeight;

  /// The last height before going full-screen, so the toggle is reversible.
  double? _restoreTo;

  double _maxHeight(BuildContext context) =>
      MediaQuery.of(context).size.height * 0.78;

  bool get _isFull => _restoreTo != null;

  void _toggleFull(BuildContext context) {
    setState(() {
      if (_isFull) {
        _height = _restoreTo!;
        _restoreTo = null;
      } else {
        _restoreTo = _height;
        _height = _maxHeight(context);
      }
    });
  }

  void _drag(DragUpdateDetails d, BuildContext context) {
    setState(() {
      // Dragging up grows the pane, so the delta is inverted.
      _height = (_height - d.delta.dy).clamp(_minHeight, _maxHeight(context));
      _restoreTo = null;
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.lines.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${widget.lines.length} lines copied'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final empty = widget.lines.isEmpty;

    return Container(
      height: _height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (d) => _drag(d, context),
            onDoubleTap: () => _toggleFull(context),
            child: _Header(
              count: widget.lines.length,
              isFull: _isFull,
              onToggleFull: () => _toggleFull(context),
              onCopy: empty ? null : _copy,
              onClear: empty ? null : widget.onClear,
            ),
          ),
          Expanded(
            child: empty
                ? Center(
                    child: Text(
                      'Output appears here.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  )
                : Scrollbar(
                    controller: widget.controller,
                    child: ListView.builder(
                      controller: widget.controller,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      itemCount: widget.lines.length,
                      itemBuilder: (_, i) => SelectableText(
                        widget.lines[i],
                        style: TextStyle(
                          fontFamily: 'Menlo',
                          fontSize: 11,
                          height: 1.5,
                          // Headings emitted by the shell start with "--", and
                          // picking them out is how you find where a run began.
                          color: widget.lines[i].startsWith('--')
                              ? Theme.of(context).colorScheme.primary
                              : null,
                          fontWeight: widget.lines[i].startsWith('--')
                              ? FontWeight.w600
                              : null,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int count;
  final bool isFull;
  final VoidCallback onToggleFull;
  final VoidCallback? onCopy;
  final VoidCallback? onClear;

  const _Header({
    required this.count,
    required this.isFull,
    required this.onToggleFull,
    required this.onCopy,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 2),
      child: Row(
        children: [
          // Grab handle — the affordance for the drag the whole row accepts.
          Container(
            width: 30,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).hintColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            count == 0 ? 'Log' : 'Log · $count',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).hintColor,
            ),
          ),
          const Spacer(),
          _IconButton(icon: Icons.copy_all, tooltip: 'Copy', onPressed: onCopy),
          _IconButton(
            icon: isFull ? Icons.close_fullscreen : Icons.open_in_full,
            tooltip: isFull ? 'Shrink' : 'Full screen',
            onPressed: onToggleFull,
          ),
          _IconButton(
            icon: Icons.playlist_remove,
            tooltip: 'Clear',
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 17),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(),
      color: Theme.of(context).hintColor,
    );
  }
}
