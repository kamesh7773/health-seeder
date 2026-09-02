import 'package:flutter/material.dart';
import 'package:health/health.dart';

import '../health_writer.dart';
import 'common.dart';

/// The body profile: the two measurements this tool can write, and a read-back
/// for the two fields it cannot.
///
/// Height is entered in the unit the Health app displays — centimetres — and
/// converted on the way in, because HealthKit stores metres. That split is
/// exactly where a bug hides, so the conversion lives in one place
/// ([HealthWriter.writeBodySample]) and the read-back undoes it, making a
/// matching number actual evidence rather than two sides sharing a mistake.
class BodyCard extends StatefulWidget {
  final HealthWriter writer;
  final RunAction run;
  final bool busy;

  const BodyCard({
    super.key,
    required this.writer,
    required this.run,
    required this.busy,
  });

  @override
  State<BodyCard> createState() => _BodyCardState();
}

class _BodyCardState extends State<BodyCard> {
  final _height = TextEditingController(text: '178');
  final _weight = TextEditingController(text: '72.4');

  /// Dated slightly in the past so a freshly written profile does not depend on
  /// the clock ticking past the write.
  DateTime get _at => DateTime.now().subtract(const Duration(minutes: 1));

  double? _read(TextEditingController c) => double.tryParse(c.text.trim());

  Future<void> _writeAll() => widget.run('Body profile', () async {
    final entries = <HealthDataType, double?>{
      HealthDataType.HEIGHT: _read(_height),
      HealthDataType.WEIGHT: _read(_weight),
    };

    var wrote = 0;
    for (final entry in entries.entries) {
      final value = entry.value;
      if (value == null) {
        widget.writer.log(
          'skipped ${entry.key.label} — blank or not a '
          'number',
        );
        continue;
      }
      final ok = await widget.writer.writeBodySample(
        type: entry.key,
        displayValue: value,
        at: _at,
      );
      if (ok) wrote++;
    }
    widget.writer.log('wrote $wrote/${entries.length} body measurements');
    await widget.writer.verifyBody();
  });

  Future<void> _readProfile() => widget.run('Read body profile', () async {
    await widget.writer.verifyBody();
    widget.writer.log('characteristics (read-only):');
    await widget.writer.verifyCharacteristics();
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Body',
      subtitle:
          'The two measurements Kai reads. Height is entered the way the '
          'Health app shows it — cm — and stored as metres; the conversion '
          'happens on the way in.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: NumberField(
                  label: 'Height',
                  suffix: 'cm',
                  controller: _height,
                  enabled: !widget.busy,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NumberField(
                  label: 'Weight',
                  suffix: 'kg',
                  controller: _weight,
                  enabled: !widget.busy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: widget.busy ? null : _writeAll,
            child: const Text('Write height and weight'),
          ),
          const SizedBox(height: 6),
          OutlinedButton(
            onPressed: widget.busy ? null : _readProfile,
            child: const Text('Read the whole profile back'),
          ),
          const Collapsible(
            title: 'Date of birth and sex',
            child: Hint(
              'No app can write these — HealthKit has no write API for them, '
              'and Health Connect has no record for them at all. Set them once '
              'by hand in Health > profile > Health Details, then use "Read '
              'the whole profile back" to confirm Kai can see them.\n\n'
              'Nothing shown there also means the profile was never filled in. '
              'iOS never says whether a read was refused, so the two look '
              'identical — which is exactly what Kai has to cope with.',
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }
}
