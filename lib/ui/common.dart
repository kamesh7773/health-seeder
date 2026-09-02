import 'package:flutter/material.dart';

/// Runs an action with the shell's busy flag held and a heading in the log.
typedef RunAction =
    Future<void> Function(String label, Future<void> Function() action);

/// One titled block of the tool.
class SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  const SectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Small grey explanatory text.
///
/// This tool has a lot to explain — which units the store uses, why a "?" is
/// not a failure — and putting all of it on screen at once is what made the UI
/// unreadable. Anything longer than a line belongs inside a [Collapsible].
class Hint extends StatelessWidget {
  final String text;
  final Color? colour;

  const Hint(this.text, {super.key, this.colour});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        height: 1.4,
        color: colour ?? Theme.of(context).hintColor,
      ),
    );
  }
}

/// A disclosure row that hides secondary controls until asked for.
///
/// Every card here has one thing you reach for constantly and one you reach for
/// rarely. Showing both at equal weight is what made each card a wall. The rare
/// half goes in here.
class Collapsible extends StatefulWidget {
  final String title;
  final Widget child;
  final bool initiallyOpen;

  const Collapsible({
    super.key,
    required this.title,
    required this.child,
    this.initiallyOpen = false,
  });

  @override
  State<Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<Collapsible> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: Theme.of(context).hintColor,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_open) widget.child,
      ],
    );
  }
}

/// A tappable date + time field.
///
/// Two separate pickers rather than one combined control, because the mistakes
/// that cost the most time here were a wrong AM/PM and a date that silently
/// rolled to the next day — both easier to spot when the value is spelled out
/// on the button itself.
class DateTimeField extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final bool enabled;

  const DateTimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String get _dateText => '${value.day} ${_months[value.month - 1]}';

  /// Always 12-hour with an explicit AM/PM, even where the device is set to
  /// 24-hour: the point is to make the half of the day unmissable.
  String get _timeText {
    final h = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final m = value.minute.toString().padLeft(2, '0');
    return '$h:$m ${value.hour < 12 ? 'AM' : 'PM'}';
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime(value.year - 2),
      lastDate: DateTime(value.year + 2),
    );
    if (picked == null) return;
    onChanged(
      DateTime(picked.year, picked.month, picked.day, value.hour, value.minute),
    );
  }

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
    );
    if (picked == null) return;
    onChanged(
      DateTime(value.year, value.month, value.day, picked.hour, picked.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: OutlinedButton(
            onPressed: enabled ? () => _pickDate(context) : null,
            child: Text(_dateText),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: enabled ? () => _pickTime(context) : null,
            child: Text(_timeText),
          ),
        ),
      ],
    );
  }
}

/// A compact labelled number input.
class NumberField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool enabled;
  final String? suffix;

  const NumberField({
    super.key,
    required this.label,
    required this.controller,
    this.enabled = true,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
