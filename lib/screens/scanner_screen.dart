import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_constants.dart';
import '../models/checkpoint.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import 'login_screen.dart';
import 'qr_scanner_page.dart';

class ScannerScreen extends StatefulWidget {
  final String checkpointName;
  final String checkpointId;
  final String volunteerPhone;
  final String volunteerName;

  const ScannerScreen({
    super.key,
    required this.checkpointName,
    required this.checkpointId,
    required this.volunteerPhone,
    required this.volunteerName,
  });

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  late String _checkpointName;
  late String _checkpointId;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _checkpointName = widget.checkpointName;
    _checkpointId = widget.checkpointId;
  }

  // ── Scan QR Button ─────────────────────────────────────────────────────────

  Future<void> _onScanQR() async {
    if (_isProcessing) return;
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QRScannerPage()),
    );
    if (!mounted || result == null) return;
    await _processQRResult(result);
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

  Future<void> _processManualEntry({
    required String riderId,
  }) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    if (!mounted) return;

    // Step 1 — Verify rider via API and show loading while waiting.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppConstants.primaryColor),
      ),
    );

    String? verifyError;
    String? verifiedName;
    String verifiedCategory = '';
    try {
      final data = await ApiService.verifyRider(
        riderId: riderId,
      );
      verifiedName = data['rider_name']?.toString();
      verifiedCategory = data['category']?.toString().trim() ?? '';
      if (verifiedCategory.isEmpty) {
        throw ApiException('Rider category missing. Please contact an organizer.');
      }
    } on ApiException catch (e) {
      verifyError = e.message;
    } catch (e) {
      verifyError = 'Verification failed. Please try again.';
    }

    if (!mounted) return;
    Navigator.of(context).pop(); // close loading

    if (verifyError != null) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(verifyError),
        backgroundColor: AppConstants.primaryColor,
      ));
      return;
    }

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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('QR code must contain a Rider ID.'),
        backgroundColor: AppConstants.primaryColor,
      ));
      return;
    }

    // Step 1 — Show QR preview with SEARCH / CANCEL.
    if (!mounted) return;
    final doSearch = await _showQRPreviewDialog(
      riderId: riderId,
    );

    if (!mounted) return;
    if (doSearch != true) {
      setState(() => _isProcessing = false);
      return;
    }

    // Step 2 — Verify rider via API.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppConstants.primaryColor),
      ),
    );

    String? verifyError;
    String? verifiedName;
    String verifiedCategory = '';
    try {
      final data = await ApiService.verifyRider(
        riderId: riderId,
      );
      verifiedName = data['rider_name']?.toString();
      verifiedCategory = data['category']?.toString().trim() ?? '';
      if (verifiedCategory.isEmpty) {
        throw ApiException('Rider category missing. Please contact an organizer.');
      }
    } on ApiException catch (e) {
      verifyError = e.message;
    } catch (e) {
      verifyError = 'Verification failed. Please try again.';
    }

    if (!mounted) return;
    Navigator.of(context).pop(); // close loading

    if (verifyError != null) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(verifyError),
        backgroundColor: AppConstants.primaryColor,
      ));
      return;
    }

    // Step 3 — Show confirmation dialog with SUBMIT / CANCEL.
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

  // ── QR Preview Popup ──────────────────────────────────────────────────────

  Future<bool?> _showQRPreviewDialog({
    required String riderId,
  }) {
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
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
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
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                  const Icon(Icons.location_on,
                      color: Colors.white30, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    _checkpointName,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 13),
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
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
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
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
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
    Map<String, dynamic>? scanData;
    try {
      scanData = await ApiService.scanCheckpoint(
        riderId: riderId,
        category: category,
        checkpoint: _checkpointName,
        scannedBy: widget.volunteerPhone,
      );
    } on DuplicateScanException catch (e) {
      uploadError = e.message;
      isDuplicate = true;
    } on ApiException catch (e) {
      uploadError = e.message;
    } catch (_) {
      uploadError = 'Upload failed. Please try again.';
    }

    if (!mounted) return;
    Navigator.of(context).pop(); // close upload loading
    setState(() => _isProcessing = false);

    if (uploadError != null) {
      await _showResultDialog(
        success: false,
        message: uploadError,
        isDuplicate: isDuplicate,
      );
    } else {
      final riderName =
          scanData?['rider_name']?.toString() ?? 'Rider';
      await _showResultDialog(
        success: true,
        message: '$riderName scanned successfully\nat $_checkpointName!',
      );
    }
  }

  // ── Result Popup (Success / Failure) ───────────────────────────────────────

  Future<void> _showResultDialog({
    required bool success,
    required String message,
    bool isDuplicate = false,
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
    final String title =
        success ? 'Success!' : isDuplicate ? 'Already Scanned' : 'Failed';
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
                style:
                    const TextStyle(color: Colors.white70, fontSize: 14),
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
      checkpoints = await ApiService.getCheckpoints();
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
          content: Text(error ?? 'No active checkpoints available.'),
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
              borderRadius: BorderRadius.circular(20)),
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
                        color: AppConstants.primaryColor
                            .withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.swap_horiz,
                          color: AppConstants.primaryColor, size: 20),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color:
                            Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Checkpoint>(
                      value: selected,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF3A3A3A),
                      icon: const Icon(Icons.keyboard_arrow_down,
                          color: Colors.white54),
                      items: cpList
                          .map(
                            (cp) => DropdownMenuItem(
                              value: cp,
                              child: Text(cp.name,
                                  style: const TextStyle(
                                      color: Colors.white)),
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
                          side:
                              const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(
                              vertical: 14),
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
                            volunteerPhone: widget.volunteerPhone,
                            volunteerName: widget.volunteerName,
                            volunteerRole:
                                LocalStorageService.volunteerRole,
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
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppConstants.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'CONFIRM',
                          style:
                              TextStyle(fontWeight: FontWeight.w700),
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

  // ── Logout ─────────────────────────────────────────────────────────────────

  Future<void> _onLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to logout?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'LOGOUT',
              style: TextStyle(
                  color: AppConstants.primaryColor,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await LocalStorageService.clearSession();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
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
        title: Text(
          'CP: $_checkpointName',
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Change Checkpoint',
            onPressed: _changeCheckpoint,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _onLogout,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 28, vertical: 24),
          child: Column(
            children: [
              _buildVolunteerCard(),
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
    );
  }

  Widget _buildVolunteerCard() {
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
            child: const Icon(Icons.badge_outlined,
                color: AppConstants.primaryColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.volunteerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  widget.volunteerPhone,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: const Text(
              'Active',
              style: TextStyle(
                color: Colors.greenAccent,
                fontSize: 11,
                fontWeight: FontWeight.w600,
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
              disabledBackgroundColor:
                  AppConstants.primaryColor.withValues(alpha: 0.45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 6,
              shadowColor:
                  AppConstants.primaryColor.withValues(alpha: 0.4),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildManualCheckIn() {
    return TextButton.icon(
      onPressed: _isProcessing ? null : _onManualCheckIn,
      icon: const Icon(Icons.edit_outlined,
          size: 16, color: Colors.white54),
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
        borderSide:
            const BorderSide(color: AppConstants.primaryColor, width: 1.5),
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
                  child: const Icon(Icons.edit_outlined,
                      color: AppConstants.primaryColor, size: 20),
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
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _riderIdController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.text,
              inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
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
                    color: AppConstants.primaryColor, fontSize: 12),
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
