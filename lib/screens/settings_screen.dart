import 'scan_history_screen.dart';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../models/checkpoint.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import '../services/rider_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _checkpointId = LocalStorageService.checkpointId;
  String _checkpointName = LocalStorageService.checkpointName;
  String _checkpointCategory = LocalStorageService.checkpointCategory;
  bool _isProcessing = false;
  String? _error;
  String _refreshStatus = '';
  bool _awaitingRetry = false;

  Future<void> _refresh() async {
    if (_isProcessing || _awaitingRetry) return;
    setState(() {
      _isProcessing = true;
      _error = null;
    });
    try {
      while (mounted) {
        try {
          setState(() {
            _isProcessing = true;
            _refreshStatus = 'Downloading riders and checkpoints…';
          });
          var ridersDone = false;
          var checkpointsDone = false;
          void updateProgress() {
            if (!mounted) return;
            setState(
              () => _refreshStatus = ridersDone && checkpointsDone
                  ? 'Downloads finished.'
                  : ridersDone
                  ? 'Riders finished. Downloading checkpoints…'
                  : checkpointsDone
                  ? 'Checkpoints finished. Downloading riders…'
                  : 'Downloading riders and checkpoints…',
            );
          }

          final warning = await RiderService.refresh(
            onRidersDone: (_) {
              ridersDone = true;
              updateProgress();
            },
            onCheckpointsDone: (_) {
              checkpointsDone = true;
              updateProgress();
            },
          );
          if (!mounted) return;
          setState(() => _error = warning);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(warning ?? 'Riders and checkpoints updated.'),
            ),
          );
          break;
        } on ApiException catch (e) {
          if (!mounted) return;
          setState(() {
            _error = e.message;
            _isProcessing = false;
            _awaitingRetry = true;
          });
          final retry = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Rider master update failed'),
              content: Text(e.message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
          _awaitingRetry = false;
          if (retry != true) break;
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _awaitingRetry = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = LocalStorageService.riderList;
    final updated = list?.updatedAt.toLocal();
    final material = MaterialLocalizations.of(context);
    final timestamp = updated == null
        ? 'Never'
        : '${material.formatMediumDate(updated)} ${material.formatTimeOfDay(TimeOfDay.fromDateTime(updated), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Scan history & sync'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _isProcessing
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ScanHistoryScreen(),
                      ),
                    ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rider list',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Riders and checkpoint options are saved on this device. Refresh both after an organizer changes either list.',
                  ),
                  const SizedBox(height: 12),
                  Text('Last updated: $timestamp'),
                  if (list != null)
                    Text(
                      '40 km: ${list.riders.values.where((r) => r.category == '40').length} riders • 100 km: ${list.riders.values.where((r) => r.category == '100').length} riders',
                    ),
                  if (list == null)
                    const Text('Download the rider list before scanning.'),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: _isProcessing ? null : _refresh,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(
                      _isProcessing
                          ? _refreshStatus
                          : 'Refresh riders and checkpoints',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Change Checkpoint'),
              subtitle: Text('$_checkpointName ($_checkpointCategory)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _isProcessing ? null : _changeCheckpoint,
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 40, bottom: 12),
            child: Text(
              'Crafted by Albin Emmanuel',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0x73D3D3D3),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changeCheckpoint() async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppConstants.primaryColor),
      ),
    );

    List<Checkpoint>? checkpoints;
    String? error;
    try {
      checkpoints = LocalStorageService.checkpoints;
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Failed to load checkpoints.';
    }

    if (!mounted) return;
    Navigator.of(context).pop();

    if (error != null || checkpoints == null || checkpoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error ??
                'No saved checkpoints. Refresh riders and checkpoints in Settings.',
          ),
          backgroundColor: AppConstants.primaryColor,
        ),
      );
      return;
    }

    Checkpoint selected = checkpoints.firstWhere(
      (c) => c.id == _checkpointId,
      orElse: () => checkpoints!.first,
    );

    // Capture as non-nullable for use inside the dialog builder
    final List<Checkpoint> cpList = checkpoints;

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: AppConstants.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppConstants.primaryColor.withValues(
                          alpha: 0.15,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.swap_horiz,
                        color: AppConstants.primaryColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Change Checkpoint',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Checkpoint>(
                      value: selected,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF3A3A3A),
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.white54,
                      ),
                      items: cpList
                          .map(
                            (cp) => DropdownMenuItem(
                              value: cp,
                              child: Text(
                                cp.name,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selected = val);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('CANCEL'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          await LocalStorageService.saveSession(
                            volunteerPhone: LocalStorageService.volunteerPhone,
                            volunteerName: LocalStorageService.volunteerName,
                            volunteerRole: LocalStorageService.volunteerRole,
                            checkpointId: selected.id,
                            checkpointName: selected.name,
                            checkpointCategory: selected.category,
                          );
                          if (!ctx.mounted) return;
                          Navigator.of(ctx).pop();
                          if (!mounted) return;
                          setState(() {
                            _checkpointName = selected.name;
                            _checkpointId = selected.id;
                            _checkpointCategory = selected.category;
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppConstants.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'CONFIRM',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
