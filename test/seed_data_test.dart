import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:health_seeder/seed_data.dart';

/// The generators are the whole point of this tool — if they emit a malformed
/// night then every test run downstream is measuring the wrong thing.
void main() {
  final wake = DateTime(2026, 8, 6, 6, 45);

  group('watchNight', () {
    test('is deterministic for a seed', () {
      final a = watchNight(wakeTime: wake, seed: 12);
      final b = watchNight(wakeTime: wake, seed: 12);

      expect(a.samples.length, b.samples.length);
      expect(a.bedTime, b.bedTime);
      for (var i = 0; i < a.samples.length; i++) {
        expect(a.samples[i].type, b.samples[i].type);
        expect(a.samples[i].start, b.samples[i].start);
        expect(a.samples[i].end, b.samples[i].end);
      }
    });

    test('a different seed gives a different night', () {
      final a = watchNight(wakeTime: wake, seed: 1);
      final b = watchNight(wakeTime: wake, seed: 2);
      expect(
        a.bedTime == b.bedTime && a.samples.length == b.samples.length,
        isFalse,
      );
    });

    test('ends exactly at the requested wake time', () {
      final night = watchNight(wakeTime: wake);
      expect(night.wakeTime, wake);
      expect(night.samples.last.end, wake);
    });

    test('the inBed blanket comes first and spans the whole night', () {
      final night = watchNight(wakeTime: wake);
      final blanket = night.samples.first;

      expect(blanket.type, HealthDataType.SLEEP_IN_BED);
      expect(blanket.start, night.bedTime);
      expect(blanket.end, night.wakeTime);
      // Exactly one — a second blanket would change what the app resolves.
      expect(
        night.samples.where((s) => s.type == HealthDataType.SLEEP_IN_BED),
        hasLength(1),
      );
    });

    test('stage samples are contiguous and never overlap', () {
      final night = watchNight(wakeTime: wake);
      final stages = night.samples.skip(1).toList();

      var cursor = night.bedTime;
      for (final s in stages) {
        expect(s.start, cursor, reason: 'gap or overlap before ${s.type.name}');
        expect(s.end.isAfter(s.start), isTrue);
        cursor = s.end;
      }
      expect(cursor, night.wakeTime);
    });

    test('produces watch-like density, not a handful of tidy blocks', () {
      final night = watchNight(wakeTime: wake);
      // Enough samples that run-merging and hairline bars get exercised.
      expect(night.samples.length, greaterThan(30));
    });

    test('covers all four lanes with a plausible split', () {
      final night = watchNight(wakeTime: wake);
      final totals = night.stageTotals;

      for (final type in [
        HealthDataType.SLEEP_LIGHT,
        HealthDataType.SLEEP_DEEP,
        HealthDataType.SLEEP_REM,
        HealthDataType.SLEEP_AWAKE,
      ]) {
        expect(totals[type]?.inMinutes ?? 0, greaterThan(0),
            reason: '${type.name} lane would be missing');
      }

      // A night nobody would question: 5-9 hours in bed, mostly asleep.
      expect(night.timeInBed.inMinutes, inInclusiveRange(5 * 60, 9 * 60));
      expect(
        night.timeAsleep.inMinutes,
        greaterThan((night.timeInBed.inMinutes * 0.85).round()),
      );
    });

    test('deep sleep is front-loaded and REM builds toward morning', () {
      final night = watchNight(wakeTime: wake);
      final midpoint = night.bedTime.add(night.timeInBed ~/ 2);

      int minutesOf(HealthDataType type, {required bool firstHalf}) => night
          .samples
          .where((s) => s.type == type)
          .where((s) => s.start.isBefore(midpoint) == firstHalf)
          .fold(0, (sum, s) => sum + s.duration.inMinutes);

      expect(minutesOf(HealthDataType.SLEEP_DEEP, firstHalf: true),
          greaterThan(minutesOf(HealthDataType.SLEEP_DEEP, firstHalf: false)));
      expect(minutesOf(HealthDataType.SLEEP_REM, firstHalf: false),
          greaterThan(minutesOf(HealthDataType.SLEEP_REM, firstHalf: true)));
    });
  });

  group('referenceNight', () {
    test('reproduces the verified night exactly', () {
      final night = referenceNight(wakeTime: wake);
      final totals = night.stageTotals;

      // 14 samples: the inBed blanket plus 13 stage runs.
      expect(night.samples, hasLength(14));
      expect(night.bedTime, DateTime(2026, 8, 5, 23, 20));
      expect(night.wakeTime, DateTime(2026, 8, 6, 6, 45));

      expect(night.timeInBed, const Duration(hours: 7, minutes: 25));
      expect(night.timeAsleep, const Duration(hours: 7, minutes: 1));

      expect(totals[HealthDataType.SLEEP_LIGHT], const Duration(minutes: 250));
      expect(totals[HealthDataType.SLEEP_DEEP], const Duration(minutes: 79));
      expect(totals[HealthDataType.SLEEP_REM], const Duration(minutes: 92));
      expect(totals[HealthDataType.SLEEP_AWAKE], const Duration(minutes: 24));
    });

    test('leaves no gaps between lights-out and waking', () {
      final night = referenceNight(wakeTime: wake);
      var cursor = night.bedTime;
      for (final s in night.samples.skip(1)) {
        expect(s.start, cursor);
        cursor = s.end;
      }
      expect(cursor, night.wakeTime);
    });

    test('the stage runs and the blanket agree on the span', () {
      final night = referenceNight(wakeTime: wake);
      final staged = night.stageTotals.values
          .fold(Duration.zero, (sum, d) => sum + d);
      // Every minute in bed is accounted for by exactly one stage — which is
      // what makes "asleep" and "in bed" differ by precisely the awake time.
      expect(staged, night.timeInBed);
      expect(night.timeInBed - night.timeAsleep, const Duration(minutes: 24));
    });
  });

  group('phoneOnlyNight', () {
    test('emits no stage detail, only undifferentiated asleep', () {
      final night = phoneOnlyNight(wakeTime: wake);
      final types = night.samples.map((s) => s.type).toSet();

      expect(types.contains(HealthDataType.SLEEP_ASLEEP), isTrue);
      expect(types.contains(HealthDataType.SLEEP_LIGHT), isFalse);
      expect(types.contains(HealthDataType.SLEEP_DEEP), isFalse);
      expect(types.contains(HealthDataType.SLEEP_REM), isFalse);
    });

    test('still lays an inBed blanket', () {
      final night = phoneOnlyNight(wakeTime: wake);
      expect(night.samples.first.type, HealthDataType.SLEEP_IN_BED);
      expect(night.samples.first.end, night.wakeTime);
    });
  });

  group('Health Connect dialect', () {
    test('wraps the night in a session instead of an in-bed blanket', () {
      final night = watchNight(
        wakeTime: wake,
        dialect: SeedDialect.healthConnect,
      );

      expect(night.samples.first.type, HealthDataType.SLEEP_SESSION);
      expect(night.samples.first.start, night.bedTime);
      expect(night.samples.first.end, night.wakeTime);
      // SLEEP_IN_BED does not exist on Health Connect. Writing one would fail
      // the whole authorisation call, not just that sample.
      expect(
        night.samples.any((s) => s.type == HealthDataType.SLEEP_IN_BED),
        isFalse,
      );
    });

    test('the stages themselves are unchanged by the dialect', () {
      // Only the wrapper differs, so the same seed has to give the same night —
      // otherwise a number that matches on one platform proves nothing on the
      // other.
      final apple = watchNight(wakeTime: wake, seed: 3);
      final android = watchNight(
        wakeTime: wake,
        seed: 3,
        dialect: SeedDialect.healthConnect,
      );

      expect(android.bedTime, apple.bedTime);
      expect(android.samples.length, apple.samples.length);
      for (var i = 1; i < apple.samples.length; i++) {
        expect(android.samples[i].type, apple.samples[i].type);
        expect(android.samples[i].start, apple.samples[i].start);
      }
    });
  });

  group('sessionOnlyNight', () {
    test('is one bare session and nothing else', () {
      final night = sessionOnlyNight(wakeTime: wake);

      expect(night.samples, hasLength(1));
      expect(night.samples.single.type, HealthDataType.SLEEP_SESSION);
      expect(night.samples.single.start, night.bedTime);
      expect(night.samples.single.end, wake);
    });

    test('the session counts as sleep — it is the night, not a container', () {
      // The distinction that has no Apple equivalent: an inBed sample on its
      // own is time in bed, but a stage-less SleepSessionRecord IS the sleep.
      final night = sessionOnlyNight(wakeTime: wake, minutes: 445);

      expect(night.wrapper, isNull);
      expect(night.timeAsleep, const Duration(minutes: 445));
      expect(night.timeInBed, const Duration(minutes: 445));
    });
  });

  group('outOfBedNight', () {
    test('reproduces the fixed Android regression night exactly', () {
      final night = outOfBedNight(wakeTime: wake);
      final totals = night.stageTotals;

      // 14 samples: the session wrapper plus 13 stage runs.
      expect(night.samples, hasLength(14));
      expect(night.samples.first.type, HealthDataType.SLEEP_SESSION);
      expect(night.bedTime, DateTime(2026, 8, 5, 23, 20));
      expect(night.wakeTime, DateTime(2026, 8, 6, 6, 45));

      expect(night.timeInBed, const Duration(hours: 7, minutes: 25));
      expect(night.timeAsleep, const Duration(hours: 6, minutes: 36));

      expect(totals[HealthDataType.SLEEP_LIGHT], const Duration(minutes: 240));
      expect(totals[HealthDataType.SLEEP_DEEP], const Duration(minutes: 79));
      expect(totals[HealthDataType.SLEEP_REM], const Duration(minutes: 77));
      expect(totals[HealthDataType.SLEEP_AWAKE], const Duration(minutes: 6));
      expect(
        totals[HealthDataType.SLEEP_AWAKE_IN_BED],
        const Duration(minutes: 18),
      );
      expect(
        totals[HealthDataType.SLEEP_OUT_OF_BED],
        const Duration(minutes: 25),
      );
    });

    test('out-of-bed and awake-in-bed are awake time, not sleep', () {
      // The whole point of this night. If either ever counts as sleep the
      // total climbs to 7h 1m — which is exactly what the Kai bug produced.
      final night = outOfBedNight(wakeTime: wake);

      expect(night.timeAsleep, isNot(const Duration(hours: 7, minutes: 1)));
      expect(
        night.timeInBed - night.timeAsleep,
        const Duration(minutes: 49), // 6 awake + 18 in bed + 25 out of bed
      );
    });

    test('leaves no gaps between lights-out and waking', () {
      final night = outOfBedNight(wakeTime: wake);
      var cursor = night.bedTime;
      for (final s in night.samples.skip(1)) {
        expect(s.start, cursor);
        cursor = s.end;
      }
      expect(cursor, night.wakeTime);
    });
  });

  group('daySteps', () {
    test('totals land near the requested count', () {
      final buckets = daySteps(day: DateTime(2026, 8, 6), total: 8000);
      final total = buckets.fold(0, (sum, b) => sum + b.steps);
      // Per-bucket jitter is +/-15%, so the sum should stay close.
      expect(total, inInclusiveRange(6800, 9200));
    });

    test('buckets sit inside waking hours and never overlap', () {
      final buckets = daySteps(day: DateTime(2026, 8, 6));

      for (final b in buckets) {
        expect(b.start.hour, inInclusiveRange(7, 21));
        expect(b.end.isAfter(b.start), isTrue);
        expect(b.steps, greaterThan(0));
      }
      for (var i = 0; i < buckets.length - 1; i++) {
        expect(buckets[i].end.isAfter(buckets[i + 1].start), isFalse);
      }
    });
  });
}
