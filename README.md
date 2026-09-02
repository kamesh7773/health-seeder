# Health Seeder

Writes synthetic sleep and step data into **HealthKit** (iOS) or **Health
Connect** (Android) so the Kai apps can be tested without owning a watch.

## Why this is a separate app

**Kai is read-only for health data and must stay that way.** Adding write
permission to Kai would put a second prompt in front of every real user and
change the entitlement story App Store review sees. So the writing lives here,
in a throwaway app that never ships.

Both apps talk to the same store on the device, so whatever this writes, Kai
reads.

## The two platforms are not the same tool

Everything below applies to both unless a heading says otherwise, but the sleep
model genuinely differs and the differences are the point:

| | HealthKit | Health Connect |
|---|---|---|
| Stages | In Bed, Asleep, Awake, Core, Deep, REM | Session, Sleeping, Awake, **Awake in Bed**, **Out of Bed**, Light, Deep, REM, **Unspecified** |
| What wraps a night | an `inBed` sample laid under the stages | a `SleepSessionRecord` the stages nest inside |
| Is the wrapper sleep? | **No** — in bed is not asleep | **Yes** when it has no stages; it *is* the night |
| Age and sex | readable characteristics | **do not exist** — no record for either |
| Read authorisation | never disclosed | reported honestly |

The three Android-only stages are why the Android section exists. Kai reads all
nine types on Android, and until this tool could write them, three of them had
never once been through the app on a device — which is how out-of-bed time came
to be counted as sleep.

### One caveat, Android only

The `health` plugin writes **one record per sample**: a night goes in as the
session record *plus* one single-stage session record per stage, rather than one
session with the stages nested inside it. Kai reads types, not records, so the
result reads back identically — but Health Connect's own UI will show more
sessions than a real tracker would. The log always reports what came back on
read-back, so if Health Connect ever rejects or merges an overlapping write you
see it immediately rather than discovering it through a wrong number.

## Why not just type it into the Health app

You can, and for a quick check you should. But hand-entered nights are tidy in a
way real ones never are:

| | Hand-entered | This tool |
|---|---|---|
| Samples per night | 7–14 | **~40** |
| Shortest segment | ~6 min | **~1 min** |
| Stage runs split into adjacent samples | no | yes, like the watch |
| Deep front-loaded, REM building to morning | no | yes |
| Repeatable | no | yes, seeded |
| Typos | frequent | none |

The 1-minute segments matter: the chart clamps sub-minute bars to a hairline so
they stay visible, and hand-entered data never gets near that path.

## Use

```bash
flutter run          # pick the simulator, emulator or a real device
```

The app decides which store it is talking to from the platform it is running on
— there is no switch, and there is nothing to configure.

### Access

Checks itself when the app opens (`hasPermissions` never prompts) and answers in
one line: ready, or how many types are off. The per-type breakdown opens on
demand, and opens itself when something is wrong. Once everything is granted the
**Request access** button goes away — neither store will keep re-prompting, so
offering it again only teaches distrust.

Only *write* status is shown. On iOS it is the only one Apple will answer: read
authorisation is hidden deliberately, so an app cannot work out what the user is
withholding, and the plugin returns null for `READ` and, less obviously, for
`READ_WRITE` too. Health Connect reports both honestly, but write is what this
tool needs, so the same question is asked either way.

If a type comes back unwritable, turn it on by hand:

- **iOS** — Health → Sharing → Apps → Health Seeder. iOS will not re-prompt.
- **Android** — Health Connect → App permissions → Health Seeder. The sheet
  stops appearing after a couple of refusals, which looks exactly like a denial.

**iOS only.** Date of birth and sex are listed but never ticked. They are
requested as `READ` (a characteristic cannot go in HealthKit's share set —
putting one there fails the *entire* authorisation call), and read status is
never reported. They still have to be in the request: reading a type that was
never asked for fails with `Authorization is not determined`, which is its own
state, distinct from denied.

**Android only.** The card checks whether Health Connect is there at all before
it checks permissions. Below Android 14 it is a separate Play Store app, and
when it is missing every call fails in exactly the same silent way a refused
permission does.

### Sleep

**One sample** — pick a stage, a start and an end, and write it. The picker
lists whatever the store on this device supports: the same six the Health app's
own "Add Data" screen offers, or Health Connect's nine. The span is spelled out
under the fields and turns orange past 12 hours, because a mis-picked AM/PM is
the mistake that keeps costing an afternoon.

**A whole generated night** — three shapes per platform, mirroring each other:
realistic, no-detail, and a fixed regression case. Only the current platform's
three are shown.

**iOS**

| | What it writes | What it is for |
|---|---|---|
| **Watch** | ~40 samples, all four lanes, seeded | The realistic case; run-merging and hairline bars |
| **iPhone** | no stage detail, just `asleep` under an inBed blanket | Kai must fall back to a single **Asleep** lane — a path otherwise unreachable without a second device |
| **Reference** | the fixed 14-sample night | Regression case; exact numbers, no seed |

**Android**

| | What it writes | What it is for |
|---|---|---|
| **Staged** | a session wrapping ~40 stage records, seeded | The realistic case, and the only way to see the session-as-container rule work |
| **Session only** | one stage-less session record | Kai must call the whole span sleep and fall back to a single **Asleep** lane. No Apple equivalent |
| **Out of bed** | the fixed night with Awake in Bed + Out of Bed | Regression case for the three stages Apple has no equivalent for |

The **seed** slider changes the two seeded nights while keeping them plausible: a
free second test case. The fixed nights ignore it — the whole point is that they
never move.

Both fixed nights run bed 23:20 → wake 06:45 (7h 25m in bed) and must produce:

```
iOS   Reference    asleep 7h 1m    Core 4h 10m · Deep 1h 19m · REM 1h 32m · Awake 24m
And.  Out of bed   asleep 6h 36m   Core 4h 0m  · Deep 1h 19m · REM 1h 17m · Awake 49m
```

Each has a signature failure worth memorising:

- iOS reading **7h 25m** means the inBed blanket leaked into the total — the
  bug that started this work.
- Android reading **7h 1m** means out-of-bed time is being counted as sleep —
  the session wrapper won a stretch it should have lost. Fixed 2026-08-07; this
  night is what keeps it fixed.

### Steps

**Across the day** — a daily total spread over 07:00–21:00 in hourly buckets,
weighted so a morning and an evening walk stand out. Use this one; a single
daily blob reads as obviously fake next to the Health app.

**One bucket** — an exact start, end and count, for pinning down a specific case.

### Body

**Write body measurements** — height and weight, the two Kai reads, entered in
the units the Health app *shows*. HealthKit stores height in **metres** though
every screen says centimetres; the conversion happens on the way in and is
undone on the way out, so writing 178 and reading back 178 is real evidence
rather than two sides sharing a bug.

**Read the whole profile back** — the newest sample of each measurement, plus
the two fields nothing can write.

Date of birth and biological sex are HealthKit *characteristics*: Apple exposes
no write API for them, and **Health Connect has no record for them at all**. On
iOS, set them once by hand in **Health → profile → Health Details**, then use the
read-back to confirm Kai can see them. On Android the read-back says so plainly
— Kai genuinely cannot prefill age or sex there, only height and weight.

A blank read-back is ambiguous on purpose — iOS never reveals whether a read was
refused, so "denied" and "never filled in" look identical. That ambiguity is the
behaviour Kai has to cope with, so the tool does not pretend otherwise.

### Clean up

Removes only what this tool wrote. Neither store will let it touch records owned
by a watch, the phone, or another app — HealthKit goes by sample ownership,
Health Connect by originating package — so it is safe on a real device.

## Gotchas

**Nights land on the day they end.** Kai buckets a night by its start using a
6 PM cutoff, so nights are generated to finish at 06:45 *today* — which is the
date the app shows by default. A night written to end tomorrow morning will not
appear until tomorrow.

**On a fresh simulator, write steps or sleep before opening Kai.** iOS never
reveals read authorisation, so Kai infers it by sampling actual data: if steps,
sleep and workouts all come back empty it concludes permission was denied and
skips the sync entirely. An empty simulator therefore looks exactly like a
refusal. Seeding anything at all breaks the deadlock.

**On a real device, the in-app wipe is the only safe reset.** It deletes what
this tool wrote and nothing else, so real sleep and steps recorded by the phone
or a watch survive. There is no "erase Health" — anything hand-entered has to be
removed from the Health app by hand.

**On a simulator**, erasing is faster than the in-app wipe when you want a true
blank slate:

```bash
xcrun simctl list devices available     # pick the one you are actually using
xcrun simctl erase "<device name>"
```

**`MainActivity` must extend `FlutterFragmentActivity`.** The health plugin asks
Health Connect for permissions through `registerForActivityResult`, and casts
the host activity to `androidx.activity.ComponentActivity` to do it. Flutter's
default `FlutterActivity` extends plain `android.app.Activity`, so that cast
throws the moment the plugin attaches and the sheet never appears. The Kai apps
do the same thing for the same reason — if you ever regenerate the Android
folder with `flutter create`, this is the line it will silently undo.

**Android emulators do not ship with Health Connect.** On Android 14+ images it
is part of the system; below that you need a Play-enabled image and have to
install Health Connect from the Play Store first. The Access card says which of
those you are looking at, rather than leaving you to guess from a silent failure.

**Android's stage names differ from Apple's, and Kai shows Apple's.** Health
Connect's *Light* is what Kai draws in the **Core** lane, and *Sleeping* and
*Unspecified* both land in the **Asleep** bucket. So a per-stage number that
looks misfiled is usually just the two vocabularies meeting.

## Layout

| File | What |
|---|---|
| `lib/seed_data.dart` | Night and step generators — pure, deterministic, unit-tested; `SeedDialect` picks the wrapper |
| `lib/health_writer.dart` | Write / delete / read-back, the per-platform type lists, and the type labels |
| `lib/main.dart` | Shell, the shared log, and the clean-up card |
| `lib/ui/log_panel.dart` | The output pane — draggable, full-screen, copyable |
| `lib/ui/permission_card.dart` | Access status, summarised |
| `lib/ui/sleep_card.dart` | One sample by hand, or a generated night |
| `lib/ui/steps_card.dart` | Spread across a day, or one bucket |
| `lib/ui/body_card.dart` | Height and weight, and the read-only profile |
| `lib/ui/common.dart` | Section chrome, date+time field, number field |
| `test/seed_data_test.dart` | Guards the generators' shape, both dialects |
| `android/app/src/main/AndroidManifest.xml` | Health Connect permissions, package visibility, the two rationale entry points |
| `android/app/src/main/res/xml/health_connect_config.xml` | Which record types Health Connect lists this app under |

Every write goes through the shell's `run`, so the single HealthKit connection
is never used by two cards at once and the log stays readable.

Each card leads with the thing you reach for constantly and tucks the rare
variant behind a disclosure — one sample by hand, one step bucket at an exact
time. Everything writes and then reads straight back, so the log is the result
rather than a side channel: drag its header to resize, double-tap or use the
button for full screen, and copy the whole run out in one tap.

The `health` package is pinned to the exact version the Kai apps read with, so
what this writes and what Kai reads go through the same type mapping.
