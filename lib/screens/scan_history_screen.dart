import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
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
  bool _isInvalid(Map<String, dynamic> entry) =>
      entry['rejected'] == true ||
      entry['error']?.toString().trim().toLowerCase() == 'invalid checkpoint';
  @override
  void initState() {
    super.initState();
    ScanHistoryService.queueStatus.addListener(_queueChanged);
    _load();
  }

  void _queueChanged() {
    if (!_busy) _load();
  }

  @override
  void dispose() {
    ScanHistoryService.queueStatus.removeListener(_queueChanged);
    super.dispose();
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
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'Total ${_entries.length} entries, '),
                      TextSpan(
                        text:
                            '${_entries.where((e) => e['confirmed'] != true && !_isInvalid(e)).length} unconfirmed',
                        style: const TextStyle(
                          color: AppConstants.secondaryColor,
                        ),
                      ),
                      const TextSpan(text: ', '),
                      TextSpan(
                        text:
                            '${_entries.where(_isInvalid).length} need attention',
                        style: const TextStyle(
                          color: AppConstants.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy || _entries.isEmpty ? null : _sync,
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync now'),
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_message != null) Text(_message!),
                ValueListenableBuilder<ScanQueueStatus>(
                  valueListenable: ScanHistoryService.queueStatus,
                  builder: (_, status, _) => status.error == null
                      ? const SizedBox.shrink()
                      : Text(
                          'Upload status: ${status.error}. Saved entries are retained.',
                        ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                final e = _entries[index];
                final invalidCheckpoint = _isInvalid(e);
                final entryColor = invalidCheckpoint
                    ? AppConstants.primaryColor
                    : e['confirmed'] != true
                    ? AppConstants.secondaryColor
                    : null;
                final date = DateTime.parse(
                  e['scanned_at'] as String,
                ).toLocal();
                return ListTile(
                  textColor: entryColor,
                  iconColor: entryColor,
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
