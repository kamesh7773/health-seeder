import 'dart:io';

import 'package:health/health.dart';

import 'seed_data.dart';

/// The sleep types this tool can write on **iOS** — the same six the Health
/// app offers on its own "Add Data" screen.
const iosSleepTypes = <HealthDataType>[
  HealthDataType.SLEEP_IN_BED,
  HealthDataType.SLEEP_ASLEEP,
  HealthDataType.SLEEP_AWAKE,
  HealthDataType.SLEEP_LIGHT,
  HealthDataType.SLEEP_DEEP,
  HealthDataType.SLEEP_REM,
];

/// The sleep types this tool can write on **Android**.
///
/// Health Connect's full stage vocabulary, which is wider than Apple's: it adds
/// Awake in Bed, Out of Bed and Unspecified, and it has no `inBed` blanket —
/// instead the stages nest inside a `SleepSessionRecord`, written here as
/// [HealthDataType.SLEEP_SESSION].
///
/// This list is deliberately identical to what the Kai apps *read* on Android.
/// A seeder that can write a type the app ignores, or that cannot write one the
/// app reads, is worse than no seeder: it produces confident wrong answers.
const androidSleepTypes = <HealthDataType>[
  HealthDataType.SLEEP_SESSION,
  HealthDataType.SLEEP_ASLEEP,
  HealthDataType.SLEEP_AWAKE,
  HealthDataType.SLEEP_AWAKE_IN_BED,
  HealthDataType.SLEEP_OUT_OF_BED,
  HealthDataType.SLEEP_LIGHT,
  HealthDataType.SLEEP_DEEP,
  HealthDataType.SLEEP_REM,
  HealthDataType.SLEEP_UNKNOWN,
];

/// The sleep types for whichever store is on this device.
///
/// Asking for a type the platform does not have fails the **whole**
/// authorisation call rather than just that type, so these lists must never be
/// merged.
List<HealthDataType> get sleepTypes =>
    Platform.isAndroid ? androidSleepTypes : iosSleepTypes;

/// The body measurements this tool can write.
///
/// Mirrors exactly what Kai asks for — height and weight — because a seeder
/// that writes types the app never reads only produces false confidence.
///
/// **Date of birth and biological sex cannot be written by any app.** They are
/// HealthKit *characteristics*, and Apple exposes no write API for them at all;
/// the user has to set them by hand in Health → profile → Health Details. So
/// testing those two means typing them there once.
const bodyTypes = <HealthDataType>[
  HealthDataType.HEIGHT,
  HealthDataType.WEIGHT,
];

/// Everything this tool writes. Kept in one place so [wipe] can promise to undo
/// exactly what the write methods did, and so [HealthWriter.writeStatus] only
/// ever asks about types that *could* be writable.
List<HealthDataType> get writableTypes => [
  ...sleepTypes,
  ...bodyTypes,
  HealthDataType.STEPS,
];

/// Types this tool reads but can never write: the HealthKit characteristics.
///
/// They still have to be part of the authorisation request. Reading one that
/// was never asked for fails with
/// `com.apple.healthkit Code=5 "Authorization is not determined"` — HealthKit
/// treats "never requested" as its own state, distinct from denied.
///
/// They must be requested as `READ`, never `READ_WRITE`: a characteristic
/// cannot go in HealthKit's share set, and putting one there fails the whole
/// authorisation call rather than just that type.
///
/// **Empty on Android.** Health Connect has no record for date of birth or
/// biological sex at all, and asking for one fails the entire authorisation
/// call — the same trap the Kai apps hit, for the same reason.
List<HealthDataType> get readOnlyTypes =>
    Platform.isAndroid ? const [] : iosReadOnlyTypes;

const iosReadOnlyTypes = <HealthDataType>[
  HealthDataType.BIRTH_DATE,
  HealthDataType.GENDER,
];

/// Everything the authorisation sheet covers.
List<HealthDataType> get allTypes => [...writableTypes, ...readOnlyTypes];

/// What the store's own UI calls each type, so the log and the pickers read the
/// same way the Health app / Health Connect does.
extension HealthDataTypeLabel on HealthDataType {
  String get label => switch (this) {
    HealthDataType.SLEEP_IN_BED => 'In Bed',
    HealthDataType.SLEEP_ASLEEP => Platform.isAndroid ? 'Sleeping' : 'Asleep',
    HealthDataType.SLEEP_AWAKE => 'Awake',
    // Apple calls light sleep "Core"; Health Connect calls it "Light".
    HealthDataType.SLEEP_LIGHT => Platform.isAndroid ? 'Light' : 'Core',
    HealthDataType.SLEEP_DEEP => 'Deep',
    HealthDataType.SLEEP_REM => 'REM',
    HealthDataType.SLEEP_SESSION => 'Session',
    HealthDataType.SLEEP_AWAKE_IN_BED => 'Awake in Bed',
    HealthDataType.SLEEP_OUT_OF_BED => 'Out of Bed',
    HealthDataType.SLEEP_UNKNOWN => 'Unspecified',
    HealthDataType.STEPS => 'Steps',
    HealthDataType.HEIGHT => 'Height',
    HealthDataType.WEIGHT => 'Weight',
    HealthDataType.BIRTH_DATE => 'Date of Birth',
    HealthDataType.GENDER => 'Sex',
    _ => name,
  };

  /// The unit the Health app shows, for the log line.
  String get displayUnit => switch (this) {
    HealthDataType.HEIGHT => 'cm',
    HealthDataType.WEIGHT => 'kg',
    _ => '',
  };
}

/// Writes synthetic samples into HealthKit and takes them back out again.
class HealthWriter {
  final Health _health = Health();
  final void Function(String) log;

  HealthWriter({required this.log});

  Future<void> configure() => _health.configure();

  /// Whether the device can talk to Health Connect at all.
  ///
  /// Android only, and worth asking before anything else: Health Connect is a
  /// separate app below Android 14, so "not installed" and "permission refused"
  /// are different problems that otherwise produce the same silent failure.
  /// Returns null on iOS, where the question does not apply.
  Future<HealthConnectSdkStatus?> healthConnectStatus() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _health.getHealthConnectSdkStatus();
    } catch (e) {
      log('Health Connect status check failed: $e');
      return null;
    }
  }

  /// Per-type **write** authorisation.
  ///
  /// Only write status is knowable on iOS. Apple deliberately hides read
  /// authorisation so an app cannot infer what the user is hiding, and the
  /// plugin returns null for both `READ` and `READ_WRITE` because of it — so
  /// this asks for `WRITE` specifically. A null value means "iOS would not
  /// say", not "denied".
  ///
  /// Android is the opposite: Health Connect reports every grant honestly, in
  /// both directions. The same `WRITE` question is asked anyway, because write
  /// is what this tool needs and a truthful answer to it is enough.
  ///
  /// Only [writableTypes] are asked about. The characteristics are read-only by
  /// nature, so a write status for them would be meaningless — never `true`,
  /// and easy to misread as a problem.
  Future<Map<HealthDataType, bool?>> writeStatus() async {
    final out = <HealthDataType, bool?>{};
    for (final type in writableTypes) {
      try {
        out[type] = await _health.hasPermissions(
          [type],
          permissions: [HealthDataAccess.WRITE],
        );
      } catch (e) {
        out[type] = null;
      }
    }
    return out;
  }

  /// Shows the HealthKit sheet. Returns false when the user declines outright.
  ///
  /// A `true` only means the sheet was answered — iOS reports success even for
  /// types the user left switched off, which is why [writeStatus] exists.
  ///
  /// Access is per type, not one blanket level: the characteristics have to be
  /// `READ` because HealthKit has no share set for them.
  Future<bool> requestPermissions() async {
    final granted = await _health.requestAuthorization(
      allTypes,
      permissions: [
        for (final type in allTypes)
          readOnlyTypes.contains(type)
              ? HealthDataAccess.READ
              : HealthDataAccess.READ_WRITE,
      ],
    );
    log(
      granted
          ? 'authorisation sheet answered'
          : 'authorisation refused outright',
    );
    return granted;
  }

  /// Writes one sleep sample. The stage is carried entirely by [type] — the
  /// iOS plugin derives the HKCategoryValue from it and ignores any value.
  Future<bool> writeSleepSample({
    required HealthDataType type,
    required DateTime start,
    required DateTime end,
  }) async {
    final ok = await _health.writeHealthData(
      value: 0,
      type: type,
      startTime: start,
      endTime: end,
      recordingMethod: RecordingMethod.manual,
    );
    log(
      ok
          ? 'wrote ${type.label}  ${_clock(start)} -> ${_clock(end)}'
                '  (${end.difference(start).inMinutes}m)'
          : 'REFUSED ${type.label} — is write access on for it?',
    );
    return ok;
  }

  Future<bool> writeStepBucket({
    required DateTime start,
    required DateTime end,
    required int steps,
  }) async {
    final ok = await _health.writeHealthData(
      value: steps.toDouble(),
      unit: HealthDataUnit.COUNT,
      type: HealthDataType.STEPS,
      startTime: start,
      endTime: end,
      recordingMethod: RecordingMethod.manual,
    );
    log(
      ok
          ? 'wrote $steps steps  ${_clock(start)} -> ${_clock(end)}'
          : 'REFUSED steps — is write access on for Steps?',
    );
    return ok;
  }

  /// Writes one body measurement, taking the value in the unit the Health app
  /// *shows* and converting to the one HealthKit *stores*.
  ///
  /// The two disagree exactly where it matters: height is stored in **metres**
  /// though every screen says centimetres. Doing the conversion here means
  /// writing 178 and reading back 178 actually proves the round-trip, rather
  /// than proving both sides share a bug.
  ///
  /// Body measurements are instantaneous, so start and end are the same moment.
  Future<bool> writeBodySample({
    required HealthDataType type,
    required double displayValue,
    required DateTime at,
  }) async {
    final stored = switch (type) {
      HealthDataType.HEIGHT => displayValue / 100, // cm -> m
      _ => displayValue,
    };

    final ok = await _health.writeHealthData(
      value: stored,
      unit: dataTypeToUnit[type],
      type: type,
      startTime: at,
      endTime: at,
      recordingMethod: RecordingMethod.manual,
    );
    log(
      ok
          ? 'wrote ${type.label} $displayValue${type.displayUnit}  ${_clock(at)}'
          : 'REFUSED ${type.label} — is write access on for it?',
    );
    return ok;
  }

  /// Reads the body measurements back in display units.
  ///
  /// Looks a long way back on purpose: these are not daily numbers, and the
  /// point is to see the newest of each — the same rule Kai applies.
  Future<void> verifyBody() async {
    final now = DateTime.now();
    final points = await _health.getHealthDataFromTypes(
      types: bodyTypes,
      startTime: now.subtract(const Duration(days: 365 * 5)),
      endTime: now,
    );

    final latest = <HealthDataType, HealthDataPoint>{};
    for (final p in points) {
      final best = latest[p.type];
      if (best == null || p.dateTo.isAfter(best.dateTo)) latest[p.type] = p;
    }

    log('read back ${points.length} body samples, newest of each:');
    for (final type in bodyTypes) {
      final p = latest[type];
      if (p == null) {
        log('   ${type.label.padRight(10)} —');
        continue;
      }
      final raw = (p.value as NumericHealthValue).numericValue.toDouble();
      final shown = switch (type) {
        HealthDataType.HEIGHT => raw * 100,
        _ => raw,
      };
      log(
        '   ${type.label.padRight(10)} '
        '${shown.toStringAsFixed(1)}${type.displayUnit}  ${_clock(p.dateTo)}',
      );
    }
  }

  /// Reports the characteristics Kai reads but nothing can write, so the log
  /// shows whether the Health profile has actually been filled in.
  ///
  /// Empty here is ambiguous by design: iOS never reveals read authorisation,
  /// so "denied" and "never set" are indistinguishable — which is exactly the
  /// behaviour Kai has to cope with.
  ///
  /// Nothing to report on Android: Health Connect has no record for either, so
  /// Kai's Android prefill genuinely cannot fill in age or sex.
  Future<void> verifyCharacteristics() async {
    const sexNames = ['not set', 'female', 'male', 'other'];
    final now = DateTime.now();

    if (readOnlyTypes.isEmpty) {
      log(
        '   (Health Connect has no date-of-birth or sex record — '
        'Kai cannot prefill those on Android)',
      );
      return;
    }

    for (final type in readOnlyTypes) {
      try {
        final points = await _health.getHealthDataFromTypes(
          types: [type],
          startTime: now.subtract(const Duration(days: 1)),
          endTime: now,
        );
        if (points.isEmpty) {
          log('   ${type.label.padRight(14)} — (not readable)');
          continue;
        }
        final raw = (points.first.value as NumericHealthValue).numericValue;
        final shown = switch (type) {
          // Epoch SECONDS, and 0 means "not set" rather than 1 Jan 1970.
          HealthDataType.BIRTH_DATE =>
            raw <= 0
                ? '— (not set)'
                : DateTime.fromMillisecondsSinceEpoch(
                    (raw * 1000).round(),
                  ).toLocal().toString().split(' ').first,
          // HKBiologicalSex raw value; 0 is "not set", same as a missing value.
          HealthDataType.GENDER =>
            raw >= 0 && raw < sexNames.length
                ? '${sexNames[raw.toInt()]}  (raw $raw)'
                : 'unknown (raw $raw)',
          _ => '$raw',
        };
        log('   ${type.label.padRight(14)} $shown');
      } catch (e) {
        log('   ${type.label.padRight(14)} failed: $e');
      }
    }
    log('(read-only — set them in Health > profile > Health Details)');
  }

  /// Writes every sample of [night], oldest first.
  Future<int> writeNight(SeedNight night) async {
    var written = 0;
    for (final s in night.samples) {
      final ok = await _health.writeHealthData(
        value: 0,
        type: s.type,
        startTime: s.start,
        endTime: s.end,
        recordingMethod: RecordingMethod.manual,
      );
      if (ok) {
        written++;
      } else {
        log('REFUSED ${s.type.label} ${_clock(s.start)}');
      }
    }
    log('wrote $written/${night.samples.length} sleep samples');
    return written;
  }

  Future<int> writeSteps(List<SeedSteps> buckets) async {
    var written = 0;
    for (final b in buckets) {
      final ok = await _health.writeHealthData(
        value: b.steps.toDouble(),
        unit: HealthDataUnit.COUNT,
        type: HealthDataType.STEPS,
        startTime: b.start,
        endTime: b.end,
        recordingMethod: RecordingMethod.manual,
      );
      if (ok) written++;
    }
    final total = buckets.fold(0, (sum, b) => sum + b.steps);
    log('wrote $written/${buckets.length} step buckets ($total steps)');
    return written;
  }

  /// Deletes this tool's sleep and step samples from the last [days] days.
  ///
  /// Both stores only permit deleting records this app wrote — HealthKit by
  /// sample ownership, Health Connect by originating package — so anything the
  /// watch, the phone or another app owns survives untouched. That is why this
  /// is safe on a real device, not just a simulator or emulator.
  Future<void> wipe({int days = 7}) async {
    final now = DateTime.now();
    final from = now.subtract(Duration(days: days));
    // Writable types only — a characteristic cannot be deleted any more than it
    // can be written, and asking would just log a failure per type.
    for (final type in writableTypes) {
      try {
        await _health.delete(type: type, startTime: from, endTime: now);
      } catch (e) {
        log('delete ${type.label} failed: $e');
      }
    }
    log('wiped this tool\'s samples from the last $days days');
  }

  /// Reads back what the store holds around [wakeTime], as proof the writes
  /// landed rather than silently no-op'd.
  ///
  /// Returns the minutes per type it found, so the caller can compare them with
  /// what it meant to write — see `SleepCard._warnIfStale`.
  Future<Map<HealthDataType, int>> verifySleep(DateTime wakeTime) async {
    final points = await _health.getHealthDataFromTypes(
      types: sleepTypes,
      startTime: wakeTime.subtract(const Duration(hours: 24)),
      endTime: wakeTime.add(const Duration(hours: 1)),
    );

    final perType = <HealthDataType, int>{};
    for (final p in points) {
      perType[p.type] =
          (perType[p.type] ?? 0) + p.dateTo.difference(p.dateFrom).inMinutes;
    }

    log('read back ${points.length} sleep samples:');
    perType.forEach(
      (type, mins) => log('   ${type.label.padRight(13)} ${mins}m'),
    );
    return perType;
  }

  Future<void> verifySteps(DateTime day) async {
    final from = DateTime(day.year, day.month, day.day);
    final total = await _health.getTotalStepsInInterval(
      from,
      from.add(const Duration(days: 1)),
      includeManualEntry: true,
    );
    log('read back ${total ?? 0} steps for ${day.day}/${day.month}');
  }

  String _clock(DateTime t) =>
      '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}'
      ':${t.minute.toString().padLeft(2, '0')}';
}
