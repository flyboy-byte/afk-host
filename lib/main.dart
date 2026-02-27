/// Flutter Host - WebRTC remote desktop host.
/// Single window app with sidebar navigation.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/app_host_service.dart';
import 'services/auto_update_service.dart';
import 'services/device_storage.dart';
import 'services/log_service.dart';
import 'services/pairing_service.dart';
import 'services/permissions_service.dart';
import 'services/remote_session_manager.dart';
import 'theme/app_theme.dart';
import 'ui/settings_view.dart';
import 'ui/onboarding_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize logging first
  await LogService.shared.initialize();
  hlog('AFK Host starting...', source: 'Main');

  if (Platform.isWindows) {
    final data = await rootBundle.load('assets/ca/isrg-root-x1.pem');
    SecurityContext.defaultContext
        .setTrustedCertificatesBytes(data.buffer.asUint8List());
  }

  final remoteSessionManager = RemoteSessionManager();
  await remoteSessionManager.initialize();

  // Initialize auto-updater (macOS/Windows only)
  await AutoUpdateService.shared.initialize();

  runApp(AFKHostApp(remoteSessionManager: remoteSessionManager));
}

class AFKHostApp extends StatelessWidget {
  final RemoteSessionManager remoteSessionManager;

  const AFKHostApp({super.key, required this.remoteSessionManager});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AFK Host',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: AppRoot(remoteSessionManager: remoteSessionManager),
    );
  }
}

class AppRoot extends StatefulWidget {
  final RemoteSessionManager remoteSessionManager;

  const AppRoot({super.key, required this.remoteSessionManager});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  bool _showOnboarding = false;
  bool _isLoading = true;
  int _onboardingStep = 0; // 0 = permissions, 1 = pairing
  final _pairingService = PairingService();
  final _appHostService = AppHostService.shared;
  final _permissionsService = PermissionsService.shared;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkOnboarding();
    _setupAppHostCallbacks();
  }

  @override
  void dispose() {
    widget.remoteSessionManager.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check onboarding when app comes to foreground
    if (state == AppLifecycleState.resumed) {
      _checkOnboarding();
    }
  }

  Future<void> _checkOnboarding() async {
    // Check permissions first
    final hasPermissions = await _permissionsService.hasAllPermissions();
    final hasPaired = DeviceStorage.shared.hasPairedClients;

    if (!mounted) return;

    final needsOnboarding = !hasPermissions || !hasPaired;

    setState(() {
      _isLoading = false;
      if (!hasPermissions) {
        // Need permissions - show permissions step
        _showOnboarding = true;
        _onboardingStep = 0;
      } else if (!hasPaired) {
        // Have permissions but no paired devices - show pairing step
        _showOnboarding = true;
        _onboardingStep = 1;
      } else {
        // All good - skip onboarding
        _showOnboarding = false;
      }
    });

    // Show the main window if onboarding is needed
    if (needsOnboarding) {
      await _appHostService.showMainWindow();
    }
  }

  void _setupAppHostCallbacks() {
    if (!Platform.isMacOS) return;
    
    // Re-check onboarding when window is shown from menu bar
    _appHostService.onShowPairing = () {
      _checkOnboarding();
    };
    _appHostService.onShowSettings = () {
      _checkOnboarding();
    };
    _appHostService.onQuit = () {};
  }

  void _completeOnboarding() {
    setState(() => _showOnboarding = false);
    // Reconnect signaling after pairing
    widget.remoteSessionManager.reconnect();
  }

  void _onPairingSuccess() {
    setState(() {});
    // Reconnect signaling after new pairing
    widget.remoteSessionManager.reconnect();
    
    final result = _pairingService.result;
    if (result != null) {
      _appHostService.notifyPairingComplete(
        deviceName: result.deviceName ?? 'iOS Device',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_showOnboarding) {
      return Scaffold(
        body: Center(
          child: _onboardingStep == 0
              ? PermissionsOnboardingView(
                  onComplete: _onPermissionsComplete,
                )
              : PairingOnboardingView(
                  pairingService: _pairingService,
                  onComplete: _completeOnboarding,
                  onSkip: _completeOnboarding,
                ),
        ),
      );
    }

    return Scaffold(
      body: SettingsView(
        pairingService: _pairingService,
        onPairingSuccess: _onPairingSuccess,
      ),
    );
  }

  void _onPermissionsComplete() {
    // After permissions, check if we need pairing
    final hasPaired = DeviceStorage.shared.hasPairedClients;
    if (hasPaired) {
      _completeOnboarding();
    } else {
      setState(() => _onboardingStep = 1);
    }
  }
}
