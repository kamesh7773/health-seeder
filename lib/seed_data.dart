import 'dart:math';

import 'package:health/health.dart';

/// One sample destined for HealthKit.
class SeedSample {
  final HealthDataType type;
  final DateTime start;
  final DateTime end;

  const SeedSample(this.type, this.start, this.end);

  Duration get duration => end.difference(start);
}

/// Which store a night is being written to.
///
/// The stage vocabulary overlaps almost completely — Light, Deep, REM and Awake
/// mean the same thing in both — but the sample that *wraps* a night does not.
/// Apple lays an `inBed` blanket under the stages; Health Connect nests them
/// inside a `SleepSessionRecord`. Both start before every stage and end after,
/// which is precisely why both have to be treated as containers on the way back
/// in.
enum SeedDialect {
  healthKit(HealthDataType.SLEEP_IN_BED),
  healthConnect(HealthDataType.SLEEP_SESSION);

  const SeedDialect(this.wrapper);

  /// The sample laid across the whole night, underneath the stages.
  final HealthDataType wrapper;
}

/// Stages that are not sleep, in either dialect.
///
/// Health Connect's two extra awake states belong here: someone lying awake in
/// bed, or up and out of it, is not asleep — and getting that wrong is exactly
/// the bug the Android nights exist to catch.
const _notAsleep = <HealthDataType>{
  HealthDataType.SLEEP_AWAKE,
  HealthDataType.SLEEP_AWAKE_IN_BED,
  HealthDataType.SLEEP_OUT_OF_BED,
};

/// A generated night, ready to write.
class SeedNight {
  /// Chronological and non-overlapping, except for [wrapper] — the one sample
  /// that spans the whole night underneath the rest.
  final List<SeedSample> samples;
  final DateTime bedTime;
  final DateTime wakeTime;

  /// The type laid across the whole night, or null for a night that has no
  /// wrapper at all (a bare Health Connect session is the night).
  final HealthDataType? wrapper;

  const SeedNight({
    required this.samples,
    required this.bedTime,
    required this.wakeTime,
    this.wrapper,
  });

  Duration get timeInBed => wakeTime.difference(bedTime);

  /// Minutes per type, ignoring the wrapper so this reads like the Health app's
  /// Stages tab, or Health Connect's session detail.
  Map<HealthDataType, Duration> get stageTotals {
    final out = <HealthDataType, Duration>{};
    for (final s in samples) {
      if (s.type == wrapper) continue;
      out[s.type] = (out[s.type] ?? Duration.zero) + s.duration;
    }
    return out;
  }

  Duration get timeAsleep => stageTotals.entries
      .where((e) => !_notAsleep.contains(e.key))
      .fold(Duration.zero, (sum, e) => sum + e.value);
}

/// A night shaped the way an Apple Watch actually records one.
///
/// Four to five ~85-minute cycles of Core → Deep → Core → REM, with deep sleep
/// front-loaded and REM growing toward morning, a settling-down stretch at
/// bedtime and short awakenings between cycles. Each stage run is emitted as
/// several adjacent samples rather than one long one, because that is what the
/// watch does — and it exercises the chart's run-merging, which a handful of
/// tidy blocks never will.
///
/// Deterministic for a given [seed], so a test that fails can be repeated.
///
/// The night is built backwards from [wakeTime]: the Kai apps bucket a night by
/// its start using a 6 PM cutoff, so a night that ends this morning lands on
/// today, which is the day the app shows by default.
SeedNight watchNight({
  required DateTime wakeTime,
  int seed = 7,
  SeedDialect dialect = SeedDialect.healthKit,
}) {
  final rnd = Random(seed);
  final plan = <({HealthDataType type, int minutes})>[];

  void add(HealthDataType type, int minutes) {
    if (minutes > 0) plan.add((type: type, minutes: minutes));
  }

  /// Emits [minutes] as 1-3 adjacent samples of the same stage.
  void addRun(HealthDataType type, int minutes) {
    if (minutes <= 0) return;
    final pieces = minutes < 10 ? 1 : 1 + rnd.nextInt(3);
    var left = minutes;
    for (var i = 0; i < pieces; i++) {
      final isLast = i == pieces - 1;
      final take = isLast ? left : max(3, (left / (pieces - i)).round());
      add(type, take);
      left -= take;
    }
  }

  // Settling down: awake in bed before sleep onset.
  add(HealthDataType.SLEEP_AWAKE, 6 + rnd.nextInt(7));

  const cycles = 5;
  for (var cycle = 0; cycle < cycles; cycle++) {
    // 0 at lights-out, 1 by the last cycle.
    final late = cycle / (cycles - 1);

    addRun(HealthDataType.SLEEP_LIGHT, 20 + rnd.nextInt(10));
    // Deep sleep is almost all in the first half of the night.
    addRun(
      HealthDataType.SLEEP_DEEP,
      (25 * (1 - late)).round() + rnd.nextInt(6),
    );
    addRun(HealthDataType.SLEEP_LIGHT, 12 + rnd.nextInt(8));
    // REM periods lengthen toward morning.
    addRun(HealthDataType.SLEEP_REM, (8 + 25 * late).round() + rnd.nextInt(6));

    // Brief awakening between cycles — real, and easy to miss on a chart that
    // cannot draw sub-minute bars.
    if (cycle < cycles - 1 && rnd.nextBool()) {
      add(HealthDataType.SLEEP_AWAKE, 1 + rnd.nextInt(5));
    }
  }

  add(HealthDataType.SLEEP_AWAKE, 2 + rnd.nextInt(4));

  return _materialise(plan, wakeTime, dialect: dialect);
}

/// The hand-built 14-sample night the sleep work was verified against.
///
/// Fixed on purpose: this exact shape is what settled the overlap rule, so it
/// is worth being able to reproduce byte-for-byte rather than approximately.
/// Bed 23:20, wake 06:45, and the numbers it must produce are:
///
/// ```
/// in bed  7h 25m   (445m)   <- Health's "Time In Bed"
/// asleep  7h  1m   (421m)   <- Health's "Time Asleep", and Kai's card
///   Core  4h 10m   (250m)
///   Deep  1h 19m    (79m)
///   REM   1h 32m    (92m)
///   Awake              24m
/// ```
///
/// If Kai ever shows 7h 25m here, the inBed blanket has leaked into the total.
SeedNight referenceNight({required DateTime wakeTime}) {
  // Minutes from lights-out, so the arithmetic is checkable at a glance
  // instead of hiding inside wall-clock times that cross midnight.
  const plan = <({HealthDataType type, int minutes})>[
    (type: HealthDataType.SLEEP_AWAKE, minutes: 18), //  23:20 -> 23:38
    (type: HealthDataType.SLEEP_LIGHT, minutes: 64), //  23:38 -> 00:42
    (type: HealthDataType.SLEEP_DEEP, minutes: 47), //   00:42 -> 01:29
    (type: HealthDataType.SLEEP_LIGHT, minutes: 36), //  01:29 -> 02:05
    (type: HealthDataType.SLEEP_REM, minutes: 33), //    02:05 -> 02:38
    (type: HealthDataType.SLEEP_LIGHT, minutes: 42), //  02:38 -> 03:20
    (type: HealthDataType.SLEEP_DEEP, minutes: 32), //   03:20 -> 03:52
    (type: HealthDataType.SLEEP_LIGHT, minutes: 38), //  03:52 -> 04:30
    (type: HealthDataType.SLEEP_AWAKE, minutes: 6), //   04:30 -> 04:36
    (type: HealthDataType.SLEEP_LIGHT, minutes: 38), //  04:36 -> 05:14
    (type: HealthDataType.SLEEP_REM, minutes: 44), //    05:14 -> 05:58
    (type: HealthDataType.SLEEP_LIGHT, minutes: 32), //  05:58 -> 06:30
    (type: HealthDataType.SLEEP_REM, minutes: 15), //    06:30 -> 06:45
  ];
  return _materialise(plan, wakeTime);
}

/// A night tracked by an iPhone alone: no stage detail, just one undifferentiated
/// "asleep" stretch under an inBed blanket.
///
/// This is the case the chart falls back on — a single **Asleep** lane instead
/// of four — and the only way to see it without a second real device.
SeedNight phoneOnlyNight({
  required DateTime wakeTime,
  int seed = 7,
  SeedDialect dialect = SeedDialect.healthKit,
}) {
  final rnd = Random(seed);
  final plan = <({HealthDataType type, int minutes})>[
    (type: HealthDataType.SLEEP_AWAKE, minutes: 8 + rnd.nextInt(8)),
    (type: HealthDataType.SLEEP_ASLEEP, minutes: 200 + rnd.nextInt(40)),
    (type: HealthDataType.SLEEP_AWAKE, minutes: 3 + rnd.nextInt(6)),
    (type: HealthDataType.SLEEP_ASLEEP, minutes: 150 + rnd.nextInt(40)),
  ];
  return _materialise(plan, wakeTime, dialect: dialect);
}

/// **Android.** A session record with nothing inside it — the thinnest thing a
/// tracker can write, and what several phone-only apps actually do.
///
/// There is no Apple equivalent: an `inBed` sample on its own is time in bed,
/// not sleep, whereas a bare `SleepSessionRecord` *is* the night. Kai has to
/// report the whole span as sleep and fall back to a single Asleep lane, with
/// no stage detail to draw.
SeedNight sessionOnlyNight({required DateTime wakeTime, int minutes = 445}) {
  final bedTime = wakeTime.subtract(Duration(minutes: minutes));
  return SeedNight(
    // No wrapper: this sample is not laid *under* anything, it is the night.
    // Leaving `wrapper` null is what keeps it counted in the totals below.
    samples: [SeedSample(HealthDataType.SLEEP_SESSION, bedTime, wakeTime)],
    bedTime: bedTime,
    wakeTime: wakeTime,
  );
}

/// **Android.** The fixed night that exercises Health Connect's three stages
/// Apple has no equivalent for: Awake in Bed, Out of Bed and the session
/// wrapper they sit inside.
///
/// Fixed rather than seeded, for the same reason [referenceNight] is: this is a
/// regression case, and it is only useful if the numbers never move. Bed 23:20,
/// wake 06:45, and Kai must show:
///
/// ```
/// asleep  6h 36m   (396m)   <- Kai's card
///   Core  4h  0m   (240m)   <- Health Connect calls this Light
///   Deep  1h 19m    (79m)
///   REM   1h 17m    (77m)
///   Awake             49m   <- 6 awake + 18 awake-in-bed + 25 out-of-bed
/// ```
///
/// **If Kai reads 7h 1m here, out-of-bed time is being counted as sleep** —
/// the session wrapper won the 02:05–02:30 stretch because out-of-bed was
/// wrongly treated as a container too. That was a real bug, fixed on
/// 2026-08-07, and this night is what proves it stays fixed.
SeedNight outOfBedNight({required DateTime wakeTime}) {
  // Minutes from lights-out, so the arithmetic is checkable at a glance.
  const plan = <({HealthDataType type, int minutes})>[
    (type: HealthDataType.SLEEP_AWAKE_IN_BED, minutes: 18), // 23:20 -> 23:38
    (type: HealthDataType.SLEEP_LIGHT, minutes: 64), //        23:38 -> 00:42
    (type: HealthDataType.SLEEP_DEEP, minutes: 47), //         00:42 -> 01:29
    (type: HealthDataType.SLEEP_LIGHT, minutes: 36), //        01:29 -> 02:05
    (type: HealthDataType.SLEEP_OUT_OF_BED, minutes: 25), //   02:05 -> 02:30
    (type: HealthDataType.SLEEP_LIGHT, minutes: 30), //        02:30 -> 03:00
    (type: HealthDataType.SLEEP_REM, minutes: 33), //          03:00 -> 03:33
    (type: HealthDataType.SLEEP_LIGHT, minutes: 42), //        03:33 -> 04:15
    (type: HealthDataType.SLEEP_DEEP, minutes: 32), //         04:15 -> 04:47
    (type: HealthDataType.SLEEP_AWAKE, minutes: 6), //         04:47 -> 04:53
    (type: HealthDataType.SLEEP_LIGHT, minutes: 38), //        04:53 -> 05:31
    (type: HealthDataType.SLEEP_REM, minutes: 44), //          05:31 -> 06:15
    (type: HealthDataType.SLEEP_LIGHT, minutes: 30), //        06:15 -> 06:45
  ];
  return _materialise(plan, wakeTime, dialect: SeedDialect.healthConnect);
}

/// Turns relative durations into absolute samples ending at [wakeTime], and
/// lays the dialect's wrapper across the whole night.
SeedNight _materialise(
  List<({HealthDataType type, int minutes})> plan,
  DateTime wakeTime, {
  SeedDialect dialect = SeedDialect.healthKit,
}) {
  final total = plan.fold(0, (sum, p) => sum + p.minutes);
  final bedTime = wakeTime.subtract(Duration(minutes: total));

  final samples = <SeedSample>[
    // First, so it is the earliest sample in the list too — the shape that
    // caught the container bug in the first place.
    SeedSample(dialect.wrapper, bedTime, wakeTime),
  ];

  var cursor = bedTime;
  for (final p in plan) {
    final end = cursor.add(Duration(minutes: p.minutes));
    samples.add(SeedSample(p.type, cursor, end));
    cursor = end;
  }

  return SeedNight(
    samples: samples,
    bedTime: bedTime,
    wakeTime: wakeTime,
    wrapper: dialect.wrapper,
  );
}

/// One bucket of steps, the way a phone records them: many small chunks through
/// the day rather than one daily total.
class SeedSteps {
  final DateTime start;
  final DateTime end;
  final int steps;

  const SeedSteps(this.start, this.end, this.steps);
}

/// Steps spread across the waking hours of [day], totalling roughly [total].
///
/// Weighted so a morning and an evening walk stand out, because a flat
/// distribution makes it impossible to tell a real read from a stub.
List<SeedSteps> daySteps({
  required DateTime day,
  int total = 8000,
  int seed = 7,
}) {
  final rnd = Random(seed);
  // Relative activity per hour, 07:00 through 21:00.
  const shape = <double>[
    1.2, 2.4, 1.0, 0.6, 0.8, 1.6, 0.7, 0.5, //  7-14
    0.9, 0.6, 1.1, 2.2, 1.4, 0.8, 0.4, //       15-21
  ];
  final weightSum = shape.fold(0.0, (a, b) => a + b);

  final out = <SeedSteps>[];
  for (var i = 0; i < shape.length; i++) {
    final hour = 7 + i;
    final jitter = 0.85 + rnd.nextDouble() * 0.3;
    final steps = (total * (shape[i] / weightSum) * jitter).round();
    if (steps <= 0) continue;

    final start = DateTime(day.year, day.month, day.day, hour);
    out.add(SeedSteps(start, start.add(const Duration(minutes: 59)), steps));
  }
  return out;
}
