import '../services/rider_service.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_constants.dart';
import '../models/checkpoint.dart';
import '../services/scan_history_service.dart';
import '../services/local_storage_service.dart';
import 'login_screen.dart';
import 'qr_scanner_page.dart';
import 'settings_screen.dart';
import 'scan_history_screen.dart';

class ScannerScreen extends StatefulWidget {
  final String checkpointName;
  final String checkpointId;
  final String checkpointCategory;
  final String volunteerPhone;
  final String volunteerName;

  const ScannerScreen({
    super.key,
    required this.checkpointName,
    required this.checkpointId,
    this.checkpointCategory = '',
    required this.volunteerPhone,
    required this.volunteerName,
  });

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  late String _checkpointName;
  late String _checkpointCategory;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _checkpointName = widget.checkpointName;
    _checkpointCategory = Checkpoint.normalizeCategory(
      widget.checkpointCategory,
    );
  }

  // ── Scan QR Button ─────────────────────────────────────────────────────────

  Future<void> _onScanQR() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    final Object? result;
    try {
      result = await Navigator.push<Object>(
        context,
        MaterialPageRoute(builder: (_) => const QRScannerPage()),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
    if (!mounted || result == null) return;
    if (result == QRScannerAction.manualEntry) {
      await _onManualCheckIn();
    } else if (result is String) {
      await _processQRResult(result);
    }
  }

  // ── Manual Check-in ────────────────────────────────────────────────────────

  Future<void> _onManualCheckIn() async {
    if (_isProcessing) return;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _ManualCheckInDialog(),
    );

    if (!mounted || result == null) return;
    await _processManualEntry(riderId: result);
  }

  // ── Manual Entry Processing ────────────────────────────────────────────────

  Future<void> _processManualEntry({required String riderId}) async {
    if (!mounted || _isProcessing) return;
    setState(() => _isProcessing = true);
    await _verifyAndConfirmRider(riderId: riderId);
  }

  // Shared by manual entry and QR search after their input/preview steps.
  // Callers hold _isProcessing until this flow finishes or is cancelled.
  Future<void> _verifyAndConfirmRider({required String riderId}) async {
    if (!mounted) return;

    while (mounted) {
      final pending = RiderService.riderDownload;
      if (pending != null) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const PopScope(
            canPop: false,
            child: AlertDialog(
              title: Text('Downloading rider master'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Please wait before verifying this rider.'),
                  SizedBox(height: 16),
                  LinearProgressIndicator(),
                ],
              ),
            ),
          ),
        );
        await pending;
        if (!mounted) return;
        Navigator.of(context).pop();
      }
      if (LocalStorageService.riderList != null) {
        break;
      }
      final retry = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Rider master unavailable'),
          content: Text(
            RiderService.riderDownloadError ??
                'Download riders before scanning.',
          ),
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
      if (!mounted) return;
      if (retry != true) {
        setState(() => _isProcessing = false);
        return;
      }
      RiderService.downloadRiderList();
    }
    if (!mounted) return;

    final list = LocalStorageService.riderList;
    final rider = list?.riders[riderId.trim()];
    if (rider == null) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            list == null
                ? 'Download the rider list in Settings before scanning.'
                : 'Rider not found in the downloaded list. Refresh it in Settings if riders have been added.',
          ),
          action: SnackBarAction(label: 'Settings', onPressed: _openSettings),
        ),
      );
      return;
    }
    final verifiedName = rider.name;
    final verifiedCategory = rider.category;

    // Step 2 — Show confirmation dialog with verified name.
    if (!mounted) return;
    final confirmed = await _showConfirmationDialog(
      riderId: riderId,
      riderName: verifiedName,
      category: verifiedCategory,
    );

    if (!mounted) return;
    if (confirmed == true) {
      await _submitScan(riderId: riderId, category: verifiedCategory);
    } else {
      setState(() => _isProcessing = false);
    }
  }

  // ── Core QR Processing Flow ────────────────────────────────────────────────

  Future<void> _processQRResult(String rawValue) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    // Read only the rider ID, from a JSON object or a plain ID string.
    String riderId = rawValue.trim();
    try {
      final dynamic qrData = jsonDecode(rawValue);
      if (qrData is Map<String, dynamic>) {
        riderId = qrData['rider_id']?.toString().trim() ?? '';
      } else if (qrData is String) {
        riderId = qrData.trim();
      }
    } on FormatException {
      // Plain rider IDs do not need JSON decoding.
    }

    if (riderId.isEmpty) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QR code must contain a Rider ID.'),
          backgroundColor: AppConstants.primaryColor,
        ),
      );
      return;
    }

    // Step 1 — Show QR preview with SEARCH / CANCEL.
    if (!mounted) return;
    final doSearch = await _showQRPreviewDialog(riderId: riderId);

    if (!mounted) return;
    if (doSearch != true) {
      setState(() => _isProcessing = false);
      return;
    }

    await _verifyAndConfirmRider(riderId: riderId);
  }

  // ── QR Preview Popup ──────────────────────────────────────────────────────

  Future<bool?> _showQRPreviewDialog({required String riderId}) {
    if (!mounted) return Future.value(null);

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: AppConstants.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'QR Scanned',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.qr_code,
                  color: AppConstants.primaryColor,
                  size: 40,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                riderId,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Cancel'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      icon: const Icon(Icons.search, size: 16),
                      label: const Text(
                        'Search',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConstants.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Confirmation Popup ─────────────────────────────────────────────────────

  Future<bool?> _showConfirmationDialog({
    required String riderId,
    required String? riderName,
    required String category,
  }) {
    if (!mounted) return Future.value(null);

    final displayName = (riderName != null && riderName.isNotEmpty)
        ? riderName
        : null;
    final savedList = LocalStorageService.riderList;
    final usingSavedList =
        RiderService.riderDownloadError != null && savedList != null;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: AppConstants.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header label
              const Text(
                'Confirm Rider',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  letterSpacing: 1,
                ),
              ),
              if (usingSavedList) ...[
                const SizedBox(height: 12),
                Text(
                  'Refresh failed. Using rider list downloaded '
                  '${MaterialLocalizations.of(context).formatMediumDate(savedList.updatedAt.toLocal())} '
                  '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(savedList.updatedAt.toLocal()))}. '
                  'Recent rider changes may be missing. Refresh in Settings when connected.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppConstants.secondaryColor),
                ),
              ],
              const SizedBox(height: 16),
              // Avatar
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person,
                  color: AppConstants.primaryColor,
                  size: 40,
                ),
              ),
              const SizedBox(height: 14),
              // Rider Name or ID (large)
              Text(
                displayName ?? riderId,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              // Show ID beneath if name is known
              if (displayName != null) ...[
                const SizedBox(height: 4),
                Text(
                  'ID: $riderId',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.38),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              // Category badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppConstants.secondaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppConstants.secondaryColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  category,
                  style: const TextStyle(
                    color: AppConstants.secondaryColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white10),
              const SizedBox(height: 8),
              // Checkpoint indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.location_on,
                    color: Colors.white30,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _checkpointName,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Cancel'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text(
                        'Submit',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConstants.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Submit / Upload ────────────────────────────────────────────────────────

  Future<void> _submitScan({
    required String riderId,
    required String category,
  }) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppConstants.primaryColor),
      ),
    );

    String? uploadError;
    bool isDuplicate = false;
    Map<String, dynamic>? entry;
    try {
      entry = await ScanHistoryService.record(
        riderId: riderId,
        riderName:
            LocalStorageService.riderList?.riders[riderId]?.name ?? riderId,
        category: category,
        checkpoint: _checkpointName,
        scannedBy: widget.volunteerPhone,
      );
    } on LocalDuplicateScanException catch (e) {
      isDuplicate = true;
      uploadError = e.toString();
    } catch (_) {
      uploadError = entry == null
          ? 'Could not save on this device. Nothing was sent. Please try again.'
          : 'Saved on this device. Upload not confirmed. Use Settings → Scan history & sync later; you do not need to scan again.';
    }

    if (!mounted) return;
    Navigator.of(context).pop(); // close upload loading
    setState(() => _isProcessing = false);

    if (uploadError != null) {
      await _showResultDialog(
        success: false,
        message: uploadError,
        isDuplicate: isDuplicate,
        savedLocally: entry != null,
      );
    } else {
      final riderName = entry?['rider_name']?.toString() ?? 'Rider';
      await _showResultDialog(
        success: true,
        savedLocally: true,
        message:
            '$riderName saved on this device at $_checkpointName. '
            'Upload queued automatically while the app is open. You can scan the next rider.',
      );
    }
  }

  // ── Result Popup (Success / Failure) ───────────────────────────────────────

  Future<void> _showResultDialog({
    required bool success,
    required String message,
    bool isDuplicate = false,
    bool savedLocally = false,
  }) async {
    if (!mounted) return;

    final Color iconColor = success
        ? Colors.greenAccent
        : isDuplicate
        ? Colors.orange
        : AppConstants.primaryColor;
    final IconData iconData = success
        ? Icons.check_circle
        : isDuplicate
        ? Icons.warning_amber_rounded
        : Icons.error_outline;
    final Color bgColor = success
        ? Colors.green.withValues(alpha: 0.15)
        : isDuplicate
        ? Colors.orange.withValues(alpha: 0.15)
        : AppConstants.primaryColor.withValues(alpha: 0.15);
    final Color btnColor = success
        ? Colors.green.shade700
        : isDuplicate
        ? Colors.orange.shade700
        : AppConstants.primaryColor;
    final String title = savedLocally
        ? 'Saved locally'
        : success
        ? 'Success!'
        : isDuplicate
        ? 'Already Scanned'
        : 'Failed';
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: AppConstants.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(iconData, color: iconColor, size: 48),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  color: iconColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: btnColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'DISMISS',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Change Checkpoint ──────────────────────────────────────────────────────

  Future<void> _openSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    if (!mounted) return;
    setState(() {
      _checkpointName = LocalStorageService.checkpointName;
      _checkpointCategory = LocalStorageService.checkpointCategory;
    });
  }

  // ── Logout ─────────────────────────────────────────────────────────────────

  Future<void> _onLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Logout',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'LOGOUT',
              style: TextStyle(
                color: AppConstants.primaryColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await LocalStorageService.clearSession();
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppConstants.backgroundDark,
        appBar: AppBar(
          backgroundColor: AppConstants.primaryColor,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          centerTitle: false,
          title: Text(
            'Hi, ${widget.volunteerName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: _isProcessing ? null : _openSettings,
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
              onPressed: _onLogout,
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 48).clamp(
                    0.0,
                    double.infinity,
                  ),
                ),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      _buildCheckpointCard(),
                      ValueListenableBuilder<ScanQueueStatus>(
                        valueListenable: ScanHistoryService.queueStatus,
                        builder: (context, status, _) => TextButton.icon(
                          onPressed: _isProcessing
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const ScanHistoryScreen(),
                                  ),
                                ),
                          icon: Icon(
                            status.uploading
                                ? Icons.cloud_upload_outlined
                                : Icons.cloud_outlined,
                          ),
                          label: Text(
                            '${status.pending} pending · ${status.rejected} need attention'
                            '${status.uploading ? " · Uploading" : ""}'
                            '${status.error != null ? "\nUploads delayed. Open history for details." : ""}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const Spacer(),
                      _buildScanArea(),
                      const SizedBox(height: 28),
                      _buildManualCheckIn(),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckpointCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppConstants.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppConstants.primaryColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_on_outlined,
              color: AppConstants.primaryColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _checkpointCategory.isEmpty
                  ? 'CP: $_checkpointName'
                  : 'CP: $_checkpointName ($_checkpointCategory)',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanArea() {
    return Column(
      children: [
        Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppConstants.primaryColor.withValues(alpha: 0.08),
            border: Border.all(
              color: AppConstants.primaryColor.withValues(alpha: 0.25),
              width: 2,
            ),
          ),
          child: const Icon(
            Icons.qr_code_scanner,
            size: 76,
            color: AppConstants.primaryColor,
          ),
        ),
        const SizedBox(height: 30),
        SizedBox(
          width: double.infinity,
          height: 58,
          child: ElevatedButton.icon(
            onPressed: _isProcessing ? null : _onScanQR,
            icon: const Icon(Icons.qr_code_scanner, size: 22),
            label: const Text(
              'SCAN QR',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppConstants.primaryColor.withValues(
                alpha: 0.45,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 6,
              shadowColor: AppConstants.primaryColor.withValues(alpha: 0.4),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildManualCheckIn() {
    return TextButton.icon(
      onPressed: _isProcessing ? null : _onManualCheckIn,
      icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.white54),
      label: const Text(
        'Manual Check-in',
        style: TextStyle(
          color: Colors.white54,
          fontSize: 14,
          decoration: TextDecoration.underline,
          decorationColor: Colors.white30,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Manual Check-in Dialog
// ---------------------------------------------------------------------------

class _ManualCheckInDialog extends StatefulWidget {
  const _ManualCheckInDialog();

  @override
  State<_ManualCheckInDialog> createState() => _ManualCheckInDialogState();
}

class _ManualCheckInDialogState extends State<_ManualCheckInDialog> {
  final _riderIdController = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _riderIdController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
      prefixIcon: Icon(icon, color: Colors.white54, size: 20),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.07),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppConstants.primaryColor),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppConstants.primaryColor),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: AppConstants.primaryColor,
          width: 1.5,
        ),
      ),
    );
  }

  void _onSubmit() {
    final riderId = _riderIdController.text.trim();
    if (riderId.isEmpty) {
      setState(() => _validationError = 'Please enter a Rider ID.');
      return;
    }
    Navigator.of(context).pop(riderId);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppConstants.surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppConstants.primaryColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.edit_outlined,
                    color: AppConstants.primaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Manual Check-in',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: Colors.white10),
            const SizedBox(height: 16),

            // Rider ID field
            const Text(
              'Rider ID / Bib No.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _riderIdController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofocus: true,
              onChanged: (_) {
                if (_validationError != null) {
                  setState(() => _validationError = null);
                }
              },
              decoration: _fieldDecoration(
                hint: 'Enter Rider ID',
                icon: Icons.badge_outlined,
              ),
            ),
            if (_validationError != null) ...[
              const SizedBox(height: 6),
              Text(
                _validationError!,
                style: const TextStyle(
                  color: AppConstants.primaryColor,
                  fontSize: 12,
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
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
                  child: ElevatedButton.icon(
                    onPressed: _onSubmit,
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text(
                      'SEARCH',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
