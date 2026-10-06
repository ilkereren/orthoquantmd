import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;
  SubscriptionService._internal();

  // Entitlement ID we defined in RevenueCat (Fallback to 'pro' if needed)
  static const String _entitlementId = 'OrthoQuant MD Pro';

  // RevenueCat API Key — provided at build time via --dart-define.
  // Example:
  //   flutter run --dart-define=REVENUECAT_API_KEY=appl_xxx
  // The key is intentionally NOT committed to source control.
  static const String _apiKey = String.fromEnvironment(
    'REVENUECAT_API_KEY',
    defaultValue: '',
  );
  static const bool _forceProForTesting = bool.fromEnvironment(
    'ORTHOQUANT_FORCE_PRO',
    defaultValue: false,
  );

  bool _isPro = false;
  bool _initialized = false;
  bool _revenueCatConfigured = false;
  Offerings? _offerings;
  bool _isLoadingOfferings = false;
  String? _offeringsError;

  static const Duration _offeringsTimeout = Duration(seconds: 15);

  bool get isPro => (kDebugMode && _forceProForTesting) || _isPro;
  bool get isInitialized => _initialized;
  Offerings? get offerings => _offerings;
  bool get canUseRevenueCat => _revenueCatConfigured;
  bool get isLoadingOfferings => _isLoadingOfferings;
  String? get offeringsError => _offeringsError;
  List<Package> get availablePackages =>
      _offerings?.current?.availablePackages ?? const [];

  Future<void> init() async {
    if (_initialized) return;

    if (kDebugMode && _forceProForTesting) {
      _isPro = true;
      _initialized = true;
      debugPrint('OrthoQuant force-pro test mode enabled.');
      notifyListeners();
      return;
    }

    if (_apiKey.isEmpty) {
      debugPrint(
        'RevenueCat API key is empty. Pass it via '
        '--dart-define=REVENUECAT_API_KEY=appl_xxx. Skipping init.',
      );
      _initialized = true;
      return;
    }

    try {
      await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.warn);

      PurchasesConfiguration configuration;
      if (Platform.isIOS) {
        configuration = PurchasesConfiguration(_apiKey);
        await Purchases.configure(configuration);
      } else if (Platform.isMacOS) {
        // macOS also uses the same logic or separate key if defined
        configuration = PurchasesConfiguration(_apiKey);
        await Purchases.configure(configuration);
      } else {
        // Handle other platforms if necessary
        _initialized = true;
        return;
      }

      _revenueCatConfigured = true;

      // Check current status
      await updateSubscriptionStatus();

      // Load offerings
      await loadOfferings();

      final appUserId = await Purchases.appUserID;
      debugPrint('RevenueCat initialized for User ID: $appUserId');

      _initialized = true;
      notifyListeners();
    } catch (e) {
      _revenueCatConfigured = false;
      _initialized = true;
      debugPrint('Error initializing RevenueCat: $e');
    }
  }

  /// Fetches offerings with a timeout so the paywall never waits forever.
  /// Sets [offeringsError] when nothing could be loaded.
  Future<void> loadOfferings() async {
    if (_isLoadingOfferings) return;
    if (!_revenueCatConfigured) {
      _offeringsError = 'Subscriptions are currently unavailable.';
      notifyListeners();
      return;
    }

    _isLoadingOfferings = true;
    _offeringsError = null;
    notifyListeners();

    try {
      _offerings = await Purchases.getOfferings().timeout(_offeringsTimeout);
      if (availablePackages.isEmpty) {
        _offeringsError = 'No subscription plans are available right now.';
      }
    } on TimeoutException {
      _offeringsError = 'Loading subscription plans timed out.';
    } catch (e) {
      debugPrint('Error loading offerings: $e');
      _offeringsError = 'Could not load subscription plans.';
    } finally {
      _isLoadingOfferings = false;
      notifyListeners();
    }
  }

  Future<String> getAppUserId() async {
    if (!_revenueCatConfigured) {
      return 'RevenueCat not configured';
    }
    try {
      return await Purchases.appUserID;
    } catch (e) {
      debugPrint('Error reading RevenueCat app user ID: $e');
      return 'RevenueCat unavailable';
    }
  }

  Future<void> updateSubscriptionStatus() async {
    if (!_revenueCatConfigured) return;
    try {
      CustomerInfo customerInfo = await Purchases.getCustomerInfo();

      customerInfo.entitlements.all.forEach((key, entitlement) {
        debugPrint('Entitlement: $key, Active: ${entitlement.isActive}');
      });

      _isPro = customerInfo.entitlements.all[_entitlementId]?.isActive ?? false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating subscription status: $e');
    }
  }

  Future<bool> purchasePackage(Package package) async {
    if (!_revenueCatConfigured) {
      debugPrint('Purchase skipped because RevenueCat is not configured.');
      return false;
    }
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      CustomerInfo customerInfo = result.customerInfo;
      _isPro = customerInfo.entitlements.all[_entitlementId]?.isActive ?? false;
      notifyListeners();
      return _isPro;
    } catch (e) {
      debugPrint('Purchase failed: $e');
      return false;
    }
  }

  Future<void> restorePurchases() async {
    if (!_revenueCatConfigured) {
      debugPrint('Restore skipped because RevenueCat is not configured.');
      return;
    }
    try {
      CustomerInfo customerInfo = await Purchases.restorePurchases();
      _isPro = customerInfo.entitlements.all[_entitlementId]?.isActive ?? false;
      notifyListeners();
    } catch (e) {
      debugPrint('Restore failed: $e');
    }
  }

  // Temporary method for testing (removed shared_preferences dependency)
  Future<void> setProStatus(bool status) async {
    _isPro = status;
    notifyListeners();
  }

  bool canAccessTemplate(bool isPremium) {
    if (!isPremium) return true;
    return isPro;
  }
}
