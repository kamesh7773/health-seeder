import 'package:flutter/material.dart';

import '../health_writer.dart';
import '../seed_data.dart';
import 'common.dart';

/// Two ways to put steps in: spread a daily total across waking hours, or drop
/// one bucket at an exact time.
///
/// The spread is what you want almost always — a phone records steps in many
/// small chunks, and a single daily blob reads as obviously fake when you open
/// the Health app next to it.
class StepsCard extends StatefulWidget {
  final HealthWriter writer;
  final RunAction run;
  final bool busy;

  const StepsCard({
    super.key,
    required this.writer,
    required this.run,
    required this.busy,
  });

  @override
  State<StepsCard> createState() => _StepsCardState();
}

class _StepsCardState extends State<StepsCard> {
  final _total = TextEditingController(text: '8000');
  final _oneOff = TextEditingController(text: '250');

  late DateTime _day = DateTime.now();
  late DateTime _bucketStart = _roundedNow();
  late DateTime _bucketEnd = _roundedNow().add(const Duration(minutes: 30));

  static DateTime _roundedNow() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, n.hour);
  }

  int get _totalSteps => int.tryParse(_total.text.trim()) ?? 0;
  int get _oneOffSteps => int.tryParse(_oneOff.text.trim()) ?? 0;

  Future<void> _writeSpread() => widget.run('Steps across the day', () async {
    final buckets = daySteps(day: _day, total: _totalSteps);
    await widget.writer.writeSteps(buckets);
    await widget.writer.verifySteps(_day);
  });

  Future<void> _writeBucket() => widget.run('One step bucket', () async {
    if (!_bucketEnd.isAfter(_bucketStart)) {
      widget.writer.log('end must be after start');
      return;
    }
    await widget.writer.writeStepBucket(
      start: _bucketStart,
      end: _bucketEnd,
      steps: _oneOffSteps,
    );
    await widget.writer.verifySteps(_bucketStart);
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Steps',
      subtitle:
          'Spread across 07:00-21:00 in hourly buckets, weighted so a '
          'morning and an evening walk stand out.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: NumberField(
                  label: 'Daily total',
                  controller: _total,
                  enabled: !widget.busy,
                  suffix: 'steps',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.busy
                      ? null
                      : () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _day,
                            firstDate: DateTime(_day.year - 1),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) setState(() => _day = picked);
                        },
                  child: Text('${_day.day}/${_day.month}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: widget.busy || _totalSteps <= 0 ? null : _writeSpread,
            child: const Text('Write steps across the day'),
          ),
          Collapsible(
            title: 'Write one bucket at an exact time',
            child: _oneBucket(),
          ),
        ],
      ),
    );
  }

  Widget _oneBucket() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DateTimeField(
          label: 'From',
          value: _bucketStart,
          enabled: !widget.busy,
          onChanged: (v) => setState(() => _bucketStart = v),
        ),
        const SizedBox(height: 6),
        DateTimeField(
          label: 'To',
          value: _bucketEnd,
          enabled: !widget.busy,
          onChanged: (v) => setState(() => _bucketEnd = v),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: NumberField(
                label: 'Steps',
                controller: _oneOff,
                enabled: !widget.busy,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: widget.busy || _oneOffSteps <= 0
                    ? null
                    : _writeBucket,
                child: const Text('Write bucket'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _total.dispose();
    _oneOff.dispose();
    super.dispose();
  }
}
