import 'package:flutter/material.dart';

import 'health_writer.dart';
import 'ui/body_card.dart';
import 'ui/common.dart';
import 'ui/log_panel.dart';
import 'ui/permission_card.dart';
import 'ui/sleep_card.dart';
import 'ui/steps_card.dart';

void main() => runApp(const SeederApp());

class SeederApp extends StatelessWidget {
  const SeederApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Health Seeder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const SeederScreen(),
    );
  }
}

class SeederScreen extends StatefulWidget {
  const SeederScreen({super.key});

  @override
  State<SeederScreen> createState() => _SeederScreenState();
}

class _SeederScreenState extends State<SeederScreen> {
  final _log = <String>[];
  final _scroll = ScrollController();
  late final HealthWriter _writer = HealthWriter(log: _append);

  bool _busy = false;

  void _append(String line) {
    if (!mounted) return;
    setState(() => _log.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  /// One writer, one HealthKit connection: serialise everything so two cards
  /// cannot interleave writes and leave the log unreadable.
  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    _append('-- $label');
    try {
      await _writer.configure();
      await action();
    } catch (e) {
      _append('ERROR: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Seeder'),
        // A thin bar rather than a spinner in the actions: it spans the whole
        // width, so "something is running" is unmissable from anywhere on the
        // screen, and it does not fight the log panel's own controls.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: SizedBox(
            height: 2,
            child: _busy ? const LinearProgressIndicator() : null,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              children: [
                PermissionCard(writer: _writer, run: _run, busy: _busy),
                SleepCard(writer: _writer, run: _run, busy: _busy),
                StepsCard(writer: _writer, run: _run, busy: _busy),
                BodyCard(writer: _writer, run: _run, busy: _busy),
                _DangerCard(writer: _writer, run: _run, busy: _busy),
              ],
            ),
          ),
          LogPanel(
            lines: _log,
            controller: _scroll,
            onClear: () => setState(_log.clear),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }
}

class _DangerCard extends StatelessWidget {
  final HealthWriter writer;
  final RunAction run;
  final bool busy;

  const _DangerCard({
    required this.writer,
    required this.run,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Clean up',
      subtitle:
          'HealthKit only lets an app delete what it wrote itself, so '
          'samples owned by a watch, the phone or another app are untouched. '
          'Safe on a real device.',
      child: OutlinedButton(
        onPressed: busy ? null : () => run('Wipe', () => writer.wipe()),
        style: OutlinedButton.styleFrom(foregroundColor: Colors.red[300]),
        child: const Text('Delete what this tool wrote (last 7 days)'),
      ),
    );
  }
}
