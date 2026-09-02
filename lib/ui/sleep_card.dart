import 'dart:io';

import 'package:flutter/material.dart';
import 'package:health/health.dart';

import '../health_writer.dart';
import '../seed_data.dart';
import 'common.dart';

/// Which night the generator should build.
///
/// Three per platform, and only that platform's three are ever shown. The two
/// sets mirror each other on purpose — realistic / no-detail / fixed-regression
/// — because the questions you want to ask of a night are the same on both, but
/// the samples that answer them are not interchangeable.
enum NightKind {
  /// ~40 samples across all four lanes, seeded.
  watch(
    'Watch',
    'Write staged night',
    'About 40 samples across Core, Deep, REM and Awake, the way a watch '
        'actually records — stage runs split into adjacent samples, some barely '
        'a minute long. The realistic case.',
  ),

  /// No stage detail — Kai should fall back to a single Asleep lane.
  phoneOnly(
    'iPhone',
    'Write iPhone-only night',
    'No stage detail at all, just asleep under an in-bed blanket. Kai should '
        'fall back to a single Asleep lane — a path you cannot reach without a '
        'second device.',
  ),

  /// The fixed 14-sample night the sleep work was verified against.
  reference(
    'Reference',
    'Write reference night',
    'Fixed 14 samples, bed 23:20 to wake 06:45. Kai must show 7h 1m — not '
        '7h 25m, which would mean the in-bed blanket leaked into the total. '
        'Core 4h 10m · Deep 1h 19m · REM 1h 32m · Awake 24m.',
    fixed: true,
  ),

  /// Android's realistic case: a session record with stages nested inside.
  hcStaged(
    'Staged',
    'Write staged night',
    'A session wrapping about 40 stage records — Light, Deep, REM and Awake — '
        'the way a watch writing to Health Connect records one. Health Connect '
        'calls light sleep "Light"; Kai draws it in the Core lane.',
    android: true,
  ),

  /// A bare session record, no stages at all.
  hcSessionOnly(
    'Session only',
    'Write bare session',
    'One session record with nothing inside it — what several phone-only '
        'trackers write. Kai must report the whole span as sleep and fall back '
        'to a single Asleep lane. No Apple equivalent: an in-bed sample alone '
        'is time in bed, but a bare session IS the night.',
    android: true,
  ),

  /// The fixed regression night for the stages Apple has no equivalent for.
  hcOutOfBed(
    'Out of bed',
    'Write out-of-bed night',
    'Fixed night, bed 23:20 to wake 06:45, containing the three stages Apple '
        'has no equivalent for. Kai must show 6h 36m — 7h 1m would mean '
        'out-of-bed time is being counted as sleep. '
        'Core 4h · Deep 1h 19m · REM 1h 17m · Awake 49m.',
    android: true,
    fixed: true,
  );

  const NightKind(
    this.chip,
    this.action,
    this.blurb, {
    this.android = false,
    this.fixed = false,
  });

  final String chip;
  final String action;

  /// What this night is for, shown under the picker so the choice explains
  /// itself instead of needing the README.
  final String blurb;

  /// Android nights write Health Connect's shape and types; iOS nights write
  /// HealthKit's. Neither set can be written to the other store.
  final bool android;

  /// A fixed night ignores the seed — the whole point of a regression case is
  /// that it never moves — so the slider is hidden for it.
  final bool fixed;

  /// The three that apply to the device this is running on.
  static List<NightKind> get available =>
      values.where((k) => k.android == Platform.isAndroid).toList();
}

/// Sleep in, two ways: one sample at a time with the stage picked by hand, or a
/// whole generated night.
class SleepCard extends StatefulWidget {
  final HealthWriter writer;
  final RunAction run;
  final bool busy;

  const SleepCard({
    super.key,
    required this.writer,
    required this.run,
    required this.busy,
  });

  @override
  State<SleepCard> createState() => _SleepCardState();
}

class _SleepCardState extends State<SleepCard> {
  // ── one sample ───────────────────────────────────────────────────────────
  HealthDataType _type = HealthDataType.SLEEP_LIGHT;
  late DateTime _start = _lastNight(23, 0);
  late DateTime _end = _lastNight(23, 0).add(const Duration(hours: 1));

  // ── generated night ──────────────────────────────────────────────────────
  NightKind _kind = NightKind.available.first;
  int _seed = 7;

  /// Yesterday evening / this morning, so a night built from here lands on
  /// today under the Kai apps' 6 PM bucketing rule.
  static DateTime _lastNight(int hour, int minute) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, hour, minute);
    return hour >= 18 ? today.subtract(const Duration(days: 1)) : today;
  }

  DateTime get _wakeTime => _lastNight(6, 45);

  Future<void> _writeOne() => widget.run('One sleep sample', () async {
    if (!_end.isAfter(_start)) {
      widget.writer.log('end must be after start');
      return;
    }
    await widget.writer.writeSleepSample(type: _type, start: _start, end: _end);
    await widget.writer.verifySleep(_end);
  });

  Future<void> _writeNight() => widget.run('${_kind.chip} night', () async {
    final night = switch (_kind) {
      NightKind.watch => watchNight(wakeTime: _wakeTime, seed: _seed),
      NightKind.phoneOnly => phoneOnlyNight(wakeTime: _wakeTime, seed: _seed),
      NightKind.reference => referenceNight(wakeTime: _wakeTime),
      NightKind.hcStaged => watchNight(
        wakeTime: _wakeTime,
        seed: _seed,
        dialect: SeedDialect.healthConnect,
      ),
      NightKind.hcSessionOnly => sessionOnlyNight(wakeTime: _wakeTime),
      NightKind.hcOutOfBed => outOfBedNight(wakeTime: _wakeTime),
    };
    _describe(night);
    await widget.writer.writeNight(night);
    final readBack = await widget.writer.verifySleep(night.wakeTime);
    _warnIfStale(night, readBack);
  });

  /// Says so when the store holds more of a stage than this night put there.
  ///
  /// Every generated night ends at the same 06:45, so writing a second one
  /// without wiping first leaves both lying on top of each other — and the
  /// resulting number is neither night's. It reads like a passing test until
  /// you notice a stage the night never contained. Comparing what came back
  /// with what went in catches it while the log is still on screen.
  ///
  /// The session type is skipped: on Health Connect every stage is itself a
  /// session record, so the read-back is always about double what was written
  /// and would cry wolf on a perfectly clean store.
  void _warnIfStale(SeedNight night, Map<HealthDataType, int> readBack) {
    final written = <HealthDataType, int>{};
    for (final s in night.samples) {
      written[s.type] = (written[s.type] ?? 0) + s.duration.inMinutes;
    }

    final extra = <String>[];
    readBack.forEach((type, mins) {
      if (type == HealthDataType.SLEEP_SESSION) return;
      final expected = written[type] ?? 0;
      if (mins > expected) {
        extra.add('${type.label} ${mins - expected}m');
      }
    });

    if (extra.isEmpty) return;
    widget.writer.log(
      '⚠️ the store holds more than this night wrote — '
      '${extra.join(', ')} came from somewhere else. An earlier night is '
      'still there; run Clean up and write this one again.',
    );
  }

  void _describe(SeedNight night) {
    String hm(Duration d) => '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    final wrapper = night.wrapper;
    widget.writer.log(
      '${night.samples.length} samples'
      '${wrapper == null ? '' : ' (1 ${wrapper.label.toLowerCase()} + '
                '${night.samples.length - 1} stages)'}, '
      'in bed ${hm(night.timeInBed)}, asleep ${hm(night.timeAsleep)}',
    );
    night.stageTotals.forEach(
      (type, d) =>
          widget.writer.log('   ${type.label.padRight(13)} ${d.inMinutes}m'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Sleep',
      subtitle: Platform.isAndroid
          // Worth stating up front: it is the difference that makes the two
          // platforms' nights non-interchangeable, and it explains why the log
          // reports more records written than stages generated.
          ? 'Health Connect nests stages inside a session record. The plugin '
                'can only write one stage per record, so a night goes in as the '
                'session plus one record per stage — which Kai reads back the '
                'same either way. Nights land on the day they end.'
          : 'Nights are bucketed by the day they end, so anything built '
                'here lands on today.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<NightKind>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              for (final k in NightKind.available)
                ButtonSegment(value: k, label: Text(k.chip)),
            ],
            selected: {_kind},
            onSelectionChanged: widget.busy
                ? null
                : (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 10),
          Hint(_kind.blurb),
          if (!_kind.fixed) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Text('seed', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: _seed.toDouble(),
                    min: 1,
                    max: 40,
                    divisions: 39,
                    label: '$_seed',
                    onChanged: widget.busy
                        ? null
                        : (v) => setState(() => _seed = v.round()),
                  ),
                ),
                SizedBox(width: 26, child: Text('$_seed')),
              ],
            ),
          ],
          const SizedBox(height: 10),
          FilledButton(
            onPressed: widget.busy ? null : _writeNight,
            child: Text(_kind.action),
          ),
          Collapsible(title: 'Write one sample by hand', child: _oneSample()),
        ],
      ),
    );
  }

  Widget _oneSample() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<HealthDataType>(
          initialValue: _type,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'Stage',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final t in sleepTypes)
              DropdownMenuItem(value: t, child: Text(t.label)),
          ],
          onChanged: widget.busy
              ? null
              : (v) => setState(() => _type = v ?? _type),
        ),
        const SizedBox(height: 10),
        DateTimeField(
          label: 'From',
          value: _start,
          enabled: !widget.busy,
          onChanged: (v) => setState(() => _start = v),
        ),
        const SizedBox(height: 6),
        DateTimeField(
          label: 'To',
          value: _end,
          enabled: !widget.busy,
          onChanged: (v) => setState(() => _end = v),
        ),
        const SizedBox(height: 6),
        _Duration(start: _start, end: _end),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: widget.busy ? null : _writeOne,
          child: const Text('Write this sample'),
        ),
      ],
    );
  }
}

/// Spells the span out, because a silently inverted or day-long range is the
/// mistake this tool exists to stop repeating.
class _Duration extends StatelessWidget {
  final DateTime start;
  final DateTime end;

  const _Duration({required this.start, required this.end});

  @override
  Widget build(BuildContext context) {
    final d = end.difference(start);
    final bad = !end.isAfter(start);
    final long = d.inHours >= 12;

    final text = bad
        ? 'End is not after start'
        : '${d.inHours}h ${d.inMinutes.remainder(60)}m'
              '${long ? '  — that is over 12 hours, check AM/PM' : ''}';

    return Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        color: bad || long ? Colors.orange[300] : Theme.of(context).hintColor,
      ),
    );
  }
}
