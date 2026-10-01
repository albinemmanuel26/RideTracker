import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_constants.dart';
import '../models/checkpoint.dart';
import '../models/volunteer.dart';
import '../services/api_service.dart';
import '../services/rider_service.dart';
import '../services/local_storage_service.dart';
import 'scanner_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePin = true;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final volunteer = await ApiService.loginVolunteer(
        phone: _phoneController.text.trim(),
        pin: _pinController.text.trim(),
      );

      if (!mounted) return;

      // Login success → show checkpoint selection
      await _showCheckpointDialog(volunteer);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showCheckpointDialog(Volunteer volunteer) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CheckpointDialog(
        volunteer: volunteer,
        onSelected: (checkpoint) async {
          await LocalStorageService.saveSession(
            volunteerPhone: volunteer.phone,
            volunteerName: volunteer.name,
            volunteerRole: volunteer.role,
            checkpointId: checkpoint.id,
            checkpointName: checkpoint.name,
            checkpointCategory: checkpoint.category,
          );

          if (!mounted || !ctx.mounted) return;
          Navigator.of(ctx).pop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ScannerScreen(
                checkpointName: checkpoint.name,
                checkpointId: checkpoint.id,
                checkpointCategory: checkpoint.category,
                volunteerPhone: volunteer.phone,
                volunteerName: volunteer.name,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundDark,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLogo(),
                const SizedBox(height: 40),
                _buildForm(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: AppConstants.primaryColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppConstants.primaryColor.withValues(alpha: 0.4),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Icon(
            Icons.directions_bike,
            size: 56,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'RideTrack',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppConstants.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Volunteer Login',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _buildPhoneField(),
            const SizedBox(height: 16),
            _buildPinField(),
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppConstants.primaryColor.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppConstants.primaryColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: AppConstants.primaryColor,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            _buildLoginButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneField() {
    return TextFormField(
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(color: Colors.white),
      decoration: _inputDecoration(
        label: 'Phone Number',
        hint: 'Enter your phone number',
        prefixIcon: Icons.phone_outlined,
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Phone number is required';
        if (v.trim().length < 6) return 'Enter a valid phone number';
        return null;
      },
    );
  }

  Widget _buildPinField() {
    return TextFormField(
      controller: _pinController,
      obscureText: _obscurePin,
      keyboardType: TextInputType.number,
      maxLength: 6,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      style: const TextStyle(color: Colors.white),
      decoration: _inputDecoration(
        label: 'PIN',
        hint: 'Enter 6-digit PIN',
        prefixIcon: Icons.lock_outline,
        suffix: IconButton(
          icon: Icon(
            _obscurePin
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: Colors.white54,
            size: 20,
          ),
          onPressed: () => setState(() => _obscurePin = !_obscurePin),
        ),
      ).copyWith(counterText: ''),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'PIN is required';
        if (v.trim().length != 6) return 'PIN must be exactly 6 digits';
        return null;
      },
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _onLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppConstants.primaryColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppConstants.primaryColor.withValues(
            alpha: 0.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 4,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : const Text(
                'LOGIN',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData prefixIcon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
      prefixIcon: Icon(prefixIcon, color: Colors.white54, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.07),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: AppConstants.primaryColor,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppConstants.primaryColor),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppConstants.primaryColor, width: 1.5),
      ),
      errorStyle: TextStyle(color: AppConstants.primaryColor),
    );
  }
}

// ---------------------------------------------------------------------------
// Checkpoint Selection Dialog
// ---------------------------------------------------------------------------

class _CheckpointDialog extends StatefulWidget {
  final Volunteer volunteer;
  final Future<void> Function(Checkpoint checkpoint) onSelected;

  const _CheckpointDialog({required this.volunteer, required this.onSelected});

  @override
  State<_CheckpointDialog> createState() => _CheckpointDialogState();
}

class _CheckpointDialogState extends State<_CheckpointDialog> {
  Checkpoint? _selected;
  bool _isSubmitting = false;
  String? _error;

  List<Checkpoint> _checkpoints = LocalStorageService.checkpoints;
  bool _downloading = true;
  bool _ridersReady = false;
  String _riderStatus = 'Downloading riders…';
  String _checkpointStatus = 'Downloading checkpoints…';
  bool _retryRiders = false;
  bool _checkpointsReady = false;
  bool _checkpointDownloading = true;

  @override
  void initState() {
    super.initState();
    _download();
  }

  Future<void> _download({bool failedOnly = false}) async {
    final riders = !failedOnly || !_ridersReady;
    final checkpoints = !failedOnly || !_checkpointsReady;
    setState(() {
      _downloading = true;
      if (riders) _ridersReady = false;
      _retryRiders = false;
      _error = null;
      if (riders) _riderStatus = 'Downloading riders…';
      if (checkpoints) {
        _checkpointDownloading = true;
        _checkpointsReady = false;
        _checkpointStatus = 'Downloading checkpoints…';
      }
    });
    try {
      await RiderService.refresh(
        downloadRiders: riders,
        downloadCheckpoints: checkpoints,
        onRidersDone: (error) {
          if (!mounted) return;
          setState(() {
            _ridersReady = error == null;
            _riderStatus = error == null
                ? 'Rider master updated.'
                : 'Rider master failed: $error';
          });
        },
        onCheckpointsDone: (error) {
          if (!mounted) return;
          setState(() {
            _checkpointDownloading = false;
            _checkpointsReady = error == null;
            _checkpoints = LocalStorageService.checkpoints;
            final id = _selected?.id;
            _selected = null;
            for (final checkpoint in _checkpoints) {
              if (checkpoint.id == id) _selected = checkpoint;
            }
            _checkpointStatus = error == null
                ? 'Checkpoints updated.'
                : 'Checkpoint download failed. ${_checkpoints.isEmpty ? "No saved options available." : "Using saved options."}\n$error';
          });
        },
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _retryRiders = true;
        _error = e.message;
      });
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }

  Future<void> _onSubmit() async {
    if (_isSubmitting) return;
    if (!_checkpointsReady) return;
    if (_selected == null) {
      setState(() => _error = 'Please select a checkpoint.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await widget.onSelected(_selected!);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save session. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_checkpointDownloading,
      child: Dialog(
        backgroundColor: AppConstants.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SingleChildScrollView(
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
                        Icons.location_on,
                        color: AppConstants.primaryColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Select Checkpoint',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Hello, ${widget.volunteer.name}!',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  _riderStatus,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Text(
                  _checkpointStatus,
                  style: const TextStyle(color: Colors.white70),
                ),
                if (_downloading) const LinearProgressIndicator(),
                if ((_retryRiders || !_checkpointsReady) && !_downloading)
                  TextButton(onPressed: _download, child: const Text('Retry')),
                TextButton(
                  onPressed: _downloading || _isSubmitting
                      ? null
                      : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const Divider(color: Colors.white12),
                const SizedBox(height: 16),
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
                      value: _selected,
                      hint: Text(
                        'Choose your checkpoint',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                      isExpanded: true,
                      dropdownColor: const Color(0xFF3A3A3A),
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.white54,
                      ),
                      items: _checkpoints
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
                      onChanged: (val) => setState(() {
                        _selected = val;
                        _error = null;
                      }),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppConstants.primaryColor,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSubmitting || !_checkpointsReady
                        ? null
                        : _onSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.primaryColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppConstants.primaryColor
                          .withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'START SCANNING',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
