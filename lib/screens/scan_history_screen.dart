import 'package:flutter/material.dart';
import '../services/scan_history_service.dart';

class ScanHistoryScreen extends StatefulWidget {
  const ScanHistoryScreen({super.key});
  @override
  State<ScanHistoryScreen> createState() => _ScanHistoryScreenState();
}

class _ScanHistoryScreenState extends State<ScanHistoryScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _busy = true;
  String? _message;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await ScanHistoryService.entries();
      if (mounted) setState(() => _entries = entries);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Could not load local scan history.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ScanHistoryService.sync();
      if (mounted) {
        setState(() => _message = 'All local entries confirmed in backend.');
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _message = 'Sync incomplete: $e. Local entries are retained.',
        );
      }
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Scan history & sync')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'All check-ins saved on this device, including previous sessions. Sync compares them with the backend and uploads missing entries.',
                ),
                const SizedBox(height: 8),
                Text(
                  '${_entries.length} entries • ${_entries.where((e) => e['confirmed'] != true).length} unconfirmed',
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy || _entries.isEmpty ? null : _sync,
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync now'),
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_message != null) Text(_message!),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                final e = _entries[index];
                final date = DateTime.parse(
                  e['scanned_at'] as String,
                ).toLocal();
                return ListTile(
                  leading: Icon(
                    e['confirmed'] == true
                        ? Icons.cloud_done
                        : Icons.cloud_upload_outlined,
                  ),
                  title: Text('${e['rider_name']} (${e['rider_id']})'),
                  subtitle: Text(
                    '${e['checkpoint']} • ${e['category']} km\n$date\n${e['confirmed'] == true ? 'Confirmed' : 'Unconfirmed'}${e['error'] == null ? '' : '\n${e['error']}'}',
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
