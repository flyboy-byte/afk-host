/// Onboarding view for AFK Host.
/// Two-step flow: Permissions → Pairing.
/// Fits within the main window (560x400).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/pairing_service.dart';
import '../services/permissions_service.dart';

// ─────────────────────────────────────────────────────────────
// Permissions Onboarding
// ─────────────────────────────────────────────────────────────

class PermissionsOnboardingView extends StatefulWidget {
  final VoidCallback onComplete;

  const PermissionsOnboardingView({super.key, required this.onComplete});

  @override
  State<PermissionsOnboardingView> createState() => _PermissionsOnboardingViewState();
}

class _PermissionsOnboardingViewState extends State<PermissionsOnboardingView> {
  bool _hasScreenRecording = false;
  bool _hasAccessibility = false;
  Timer? _pollTimer;

  final _permissionsService = PermissionsService.shared;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    // Poll every second to detect when user grants permissions in System Settings
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _checkPermissions());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    final perms = await _permissionsService.checkAll();
    if (mounted) {
      setState(() {
        _hasScreenRecording = perms['screenRecording'] ?? false;
        _hasAccessibility = perms['accessibility'] ?? false;
      });
    }
  }

  Future<void> _requestScreenRecording() async {
    await _permissionsService.requestScreenRecording();
    // Check again after a short delay (system dialog may have been shown)
    await Future.delayed(const Duration(milliseconds: 500));
    _checkPermissions();
  }

  Future<void> _requestAccessibility() async {
    await _permissionsService.requestAccessibility();
    // Check again after a short delay
    await Future.delayed(const Duration(milliseconds: 500));
    _checkPermissions();
  }

  bool get _allGranted => _hasScreenRecording && _hasAccessibility;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(60, 40, 60, 40),
      child: Column(
        children: [
          // App icon
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset('assets/app_icon.png', width: 72, height: 72),
          ),
          const SizedBox(height: 16),
          const Text(
            'Welcome to AFK Host',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),

          // Permissions
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This app requires:',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                _PermissionRow(
                  icon: Icons.screenshot_monitor,
                  title: 'Screen Recording',
                  description: 'To stream your desktop',
                  isGranted: _hasScreenRecording,
                  onGrant: _requestScreenRecording,
                ),
                const SizedBox(height: 10),
                _PermissionRow(
                  icon: Icons.touch_app,
                  title: 'Accessibility',
                  description: 'To manage windows remotely',
                  isGranted: _hasAccessibility,
                  onGrant: _requestAccessibility,
                ),
              ],
            ),
          ),

          const Spacer(),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _allGranted ? widget.onComplete : null,
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool isGranted;
  final VoidCallback onGrant;

  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.isGranted,
    required this.onGrant,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22, color: AppColors.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              Text(description, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ),
        if (isGranted)
          const Icon(Icons.check_circle, size: 20, color: AppColors.success)
        else
          OutlinedButton(
            onPressed: onGrant,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
            ),
            child: const Text('Grant', style: TextStyle(fontSize: 12)),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Pairing Onboarding
// ─────────────────────────────────────────────────────────────

class PairingOnboardingView extends StatefulWidget {
  final PairingService pairingService;
  final VoidCallback onComplete;
  final VoidCallback onSkip;

  const PairingOnboardingView({
    super.key,
    required this.pairingService,
    required this.onComplete,
    required this.onSkip,
  });

  @override
  State<PairingOnboardingView> createState() => _PairingOnboardingViewState();
}

class _PairingOnboardingViewState extends State<PairingOnboardingView> {
  PairingState _state = PairingState.idle;
  StreamSubscription<PairingState>? _subscription;

  @override
  void initState() {
    super.initState();
    _startPairing();
  }

  void _startPairing() {
    _subscription?.cancel();
    _subscription = widget.pairingService.startPairing().listen((state) {
      if (mounted) setState(() => _state = state);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    if (_state == PairingState.waitingForClient) {
      widget.pairingService.cancelPairing();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(60, 40, 60, 40),
      child: Column(
        children: [
          // App icon
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset('assets/app_icon.png', width: 72, height: 72),
          ),
          const SizedBox(height: 16),
          const Text(
            'Connect Your iPhone',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),

          Expanded(child: _buildContent()),

          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_state) {
      case PairingState.idle:
      case PairingState.generating:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(height: 16),
              Text('Generating code...', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        );

      case PairingState.waitingForClient:
        return _buildWaitingContent();

      case PairingState.success:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 48, color: AppColors.success),
              SizedBox(height: 12),
              Text('Paired Successfully!', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        );

      case PairingState.error:
      case PairingState.timeout:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _state == PairingState.timeout ? Icons.schedule : Icons.warning_amber_rounded,
                size: 48,
                color: _state == PairingState.timeout ? AppColors.textSecondary : AppColors.warning,
              ),
              const SizedBox(height: 12),
              Text(
                _state == PairingState.timeout ? 'Timed Out' : 'Pairing Failed',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildWaitingContent() {
    final code = widget.pairingService.currentCode ?? '';
    final first = code.length >= 3 ? code.substring(0, 3) : code;
    final second = code.length >= 6 ? code.substring(3, 6) : '';

    return Column(
      children: [
        // Steps
        Row(
          children: [
            _StepBadge(number: 1),
            const SizedBox(width: 10),
            const Text('Open the AFK app on your iPhone', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _StepBadge(number: 2),
            const SizedBox(width: 10),
            const Text('Enter this code:', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(height: 16),

        // Code
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.groupedBackground,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(first, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('–', style: TextStyle(fontSize: 28, color: AppColors.textSecondary)),
              ),
              Text(second, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    switch (_state) {
      case PairingState.idle:
      case PairingState.generating:
      case PairingState.waitingForClient:
        return TextButton(
          onPressed: () {
            widget.pairingService.cancelPairing();
            widget.onSkip();
          },
          child: const Text("I'll do this later", style: TextStyle(color: AppColors.textSecondary)),
        );

      case PairingState.success:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: widget.onComplete,
            child: const Text('Done'),
          ),
        );

      case PairingState.error:
      case PairingState.timeout:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(onPressed: widget.onSkip, child: const Text('Skip')),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () {
                widget.pairingService.reset();
                _startPairing();
              },
              child: const Text('Try Again'),
            ),
          ],
        );
    }
  }
}

class _StepBadge extends StatelessWidget {
  final int number;
  const _StepBadge({required this.number});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.accent),
      child: Center(
        child: Text('$number', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
      ),
    );
  }
}
