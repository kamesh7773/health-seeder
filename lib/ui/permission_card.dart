import 'dart:io';

import 'package:flutter/material.dart';
import 'package:health/health.dart';

import '../health_writer.dart';
import 'common.dart';

/// Access, stated as one answer instead of eleven.
///
/// The card used to list every type with a tick, all the time, and offer
/// "Request access" whether or not access had already been granted — so the
/// screen looked identical before and after the one action that mattered. Now
/// the headline says whether the tool can work, the per-type breakdown is there
/// only when something is wrong or you ask for it, and the request button
/// disappears once there is nothing left to request.
class PermissionCard extends StatefulWidget {
  final HealthWriter writer;
  final RunAction run;
  final bool busy;

  const PermissionCard({
    super.key,
    required this.writer,
    required this.run,
    required this.busy,
  });

  @override
  State<PermissionCard> createState() => _PermissionCardState();
}

class _PermissionCardState extends State<PermissionCard> {
  Map<HealthDataType, bool?>? _status;
  HealthConnectSdkStatus? _sdk;

  @override
  void initState() {
    super.initState();
    // Check on open. `hasPermissions` never prompts, so this costs the user
    // nothing and removes the "why is everything failing" first run where the
    // card sat at "not checked yet".
    WidgetsBinding.instance.addPostFrameCallback((_) => _check(quiet: true));
  }

  /// Whether Health Connect itself is missing or out of date.
  ///
  /// Asked before permissions on purpose: below Android 14 Health Connect is a
  /// separate app from the Play Store, and when it is absent every call fails
  /// in exactly the same silent way a refused permission does.
  bool get _sdkUnavailable =>
      _sdk != null && _sdk != HealthConnectSdkStatus.sdkAvailable;

  int get _granted => _status?.values.where((v) => v == true).length ?? 0;

  bool get _allGranted => _status != null && _granted == writableTypes.length;

  Future<void> _check({bool quiet = false}) =>
      widget.run('Check access', () async {
        final sdk = await widget.writer.healthConnectStatus();
        final status = await widget.writer.writeStatus();
        if (mounted) {
          setState(() {
            _sdk = sdk;
            _status = status;
          });
        }
        if (!quiet) {
          widget.writer.log('$_granted/${writableTypes.length} types writable');
        }
      });

  Future<void> _request() => widget.run('Request access', () async {
    await widget.writer.requestPermissions();
    final status = await widget.writer.writeStatus();
    if (mounted) setState(() => _status = status);
  });

  @override
  Widget build(BuildContext context) {
    final status = _status;

    return SectionCard(
      title: 'Access',
      trailing: _Badge(status: status, granted: _granted),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Hint(_headline),
          if (_sdkUnavailable) ...[
            const SizedBox(height: 8),
            Hint(
              _sdk ==
                      HealthConnectSdkStatus
                          .sdkUnavailableProviderUpdateRequired
                  ? 'Health Connect is out of date. Update it from the Play '
                        'Store — until then nothing can be written or read.'
                  : 'Health Connect is not available on this device. Below '
                        'Android 14 it is a separate app; install it from the '
                        'Play Store.',
              colour: Colors.orange[300],
            ),
          ],
          const SizedBox(height: 12),
          _actions(),
          if (status != null) ...[
            const SizedBox(height: 4),
            Collapsible(
              title: 'Per-type detail',
              // Opened for you when something is off, because then the list is
              // the answer to "which one".
              initiallyOpen: !_allGranted,
              child: _Detail(status: status),
            ),
          ],
        ],
      ),
    );
  }

  String get _headline {
    if (_status == null) return 'Checking…';
    if (_allGranted) {
      final extra = readOnlyTypes.isEmpty
          ? '' // Android: there are no read-only types to mention.
          : ', and the ${readOnlyTypes.length} read-only ones were requested too';
      return 'Ready. All ${writableTypes.length} types are writable$extra.';
    }
    return '$_granted of ${writableTypes.length} types are writable. Anything '
        'off will silently refuse to write.';
  }

  Widget _actions() {
    // Nothing left to request: iOS will not re-prompt for a type it has already
    // been answered for, so offering the button again only teaches distrust.
    if (_allGranted) {
      return OutlinedButton.icon(
        onPressed: widget.busy ? null : () => _check(),
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('Re-check'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: widget.busy ? null : _request,
          child: const Text('Request access'),
        ),
        if (_status != null) ...[
          const SizedBox(height: 8),
          Hint(
            Platform.isAndroid
                // Health Connect will re-prompt, but only twice per type —
                // after that the sheet silently stops appearing, which looks
                // exactly like a refusal.
                ? 'Health Connect stops showing the sheet after a couple of '
                      'refusals. Switch the missing types on in Health Connect > '
                      'App permissions > Health Seeder, then re-check.'
                : 'Already answered once? iOS will not ask again. Switch the '
                      'missing types on in Health > Sharing > Apps > '
                      'Health Seeder, then re-check.',
            colour: Colors.orange[300],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: widget.busy ? null : () => _check(),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Re-check'),
          ),
        ],
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final Map<HealthDataType, bool?>? status;
  final int granted;

  const _Badge({required this.status, required this.granted});

  @override
  Widget build(BuildContext context) {
    if (status == null) return const SizedBox.shrink();

    final all = granted == writableTypes.length;
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: (all ? Colors.green : Colors.orange).withValues(
        alpha: 0.18,
      ),
      side: BorderSide.none,
      avatar: Icon(
        all ? Icons.check_circle : Icons.error_outline,
        size: 15,
        color: all ? Colors.green : Colors.orange,
      ),
      label: Text(
        '$granted/${writableTypes.length}',
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  final Map<HealthDataType, bool?> status;

  const _Detail({required this.status});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...writableTypes.map((t) => _Row(type: t, ok: status[t])),
        // Nothing to list on Android: Health Connect has no date-of-birth or
        // sex record at all, so there is no read-only tier to explain.
        if (readOnlyTypes.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Hint(
            'Read-only — no app can write these, and iOS never reports '
            'read status, so they stay unanswered even when they work.',
          ),
          const SizedBox(height: 4),
          ...readOnlyTypes.map((t) => _Row(type: t, ok: null)),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final HealthDataType type;
  final bool? ok;

  const _Row({required this.type, required this.ok});

  @override
  Widget build(BuildContext context) {
    final (icon, colour) = switch (ok) {
      true => (Icons.check_circle, Colors.green),
      false => (Icons.cancel, Colors.red),
      null => (Icons.remove, Theme.of(context).hintColor),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: colour),
          const SizedBox(width: 8),
          Expanded(
            child: Text(type.label, style: const TextStyle(fontSize: 12.5)),
          ),
          Text(
            type.name,
            style: TextStyle(
              fontSize: 9.5,
              fontFamily: 'Menlo',
              color: Theme.of(context).hintColor,
            ),
          ),
        ],
      ),
    );
  }
}
