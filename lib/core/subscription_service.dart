import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Subscription tier & billing manager.
/// - Android / iOS: uses Google Play Billing / Apple StoreKit via `in_app_purchase`.
/// - Web / Direct APK: gracefully falls back to QRIS payment flow.
/// Zero impact on Sherpa-ONNX AI performance (exposes an O(1) boolean notifier).
class SubscriptionService extends ChangeNotifier {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  // Configure these exact IDs in Google Play Console / App Store Connect
  static const String yearlyProductId = 'ngabar_premium_yearly';
  static const String monthlyProductId = 'ngabar_premium_monthly';
  static const Set<String> _productIds = {
    yearlyProductId,
    monthlyProductId,
  };

  final ValueNotifier<bool> isPremiumNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isBusyNotifier = ValueNotifier<bool>(false);

  bool get isPremium => isPremiumNotifier.value;
  String? _activePlanId;
  String? get activePlanId => _activePlanId;

  bool _storeAvailable = false;
  bool get storeAvailable => _storeAvailable;

  final Map<String, ProductDetails> _products = {};
  ProductDetails? productFor(String id) => _products[id];

  String? _lastError;
  String? get lastError => _lastError;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final bool savedPremium = prefs.getBool('ngabar_is_premium') ?? false;
      _activePlanId = prefs.getString('ngabar_active_plan_id');
      isPremiumNotifier.value = savedPremium;
    } catch (_) {}

    if (kIsWeb) {
      _storeAvailable = false;
      return;
    }

    try {
      final iap = InAppPurchase.instance;
      _storeAvailable = await iap.isAvailable();
      if (!_storeAvailable) return;

      _purchaseSub?.cancel();
      _purchaseSub = iap.purchaseStream.listen(
        _onPurchaseUpdated,
        onError: (Object error) {
          _lastError = error.toString();
          isBusyNotifier.value = false;
          notifyListeners();
        },
      );

      final response = await iap.queryProductDetails(_productIds);
      for (final p in response.productDetails) {
        _products[p.id] = p;
      }
      notifyListeners();
    } catch (e) {
      _storeAvailable = false;
      debugPrint('[SubscriptionService] init warning: $e');
    }
  }

  /// Starts Play Store / App Store subscription purchase for [productId].
  /// Returns `true` if the native store sheet was launched, `false` if unavailable
  /// (caller should show QRIS fallback).
  Future<bool> purchaseStorePlan(String productId) async {
    if (kIsWeb || !_storeAvailable) return false;
    final product = _products[productId];
    if (product == null) return false;

    _lastError = null;
    isBusyNotifier.value = true;
    notifyListeners();

    try {
      final param = PurchaseParam(productDetails: product);
      return await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      _lastError = e.toString();
      isBusyNotifier.value = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> restorePurchases() async {
    if (kIsWeb || !_storeAvailable) return;
    isBusyNotifier.value = true;
    notifyListeners();
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      _lastError = e.toString();
    } finally {
      isBusyNotifier.value = false;
      notifyListeners();
    }
  }

  Future<void> _onPurchaseUpdated(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          isBusyNotifier.value = true;
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _grantPremium(purchase.productID);
          isBusyNotifier.value = false;
          break;
        case PurchaseStatus.error:
          _lastError = purchase.error?.message ?? 'Pembelian gagal';
          isBusyNotifier.value = false;
          break;
        case PurchaseStatus.canceled:
          isBusyNotifier.value = false;
          break;
      }

      if (purchase.pendingCompletePurchase) {
        try {
          await InAppPurchase.instance.completePurchase(purchase);
        } catch (_) {}
      }
    }
    notifyListeners();
  }

  Future<void> _grantPremium(String planId) async {
    _activePlanId = planId;
    isPremiumNotifier.value = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ngabar_is_premium', true);
    await prefs.setString('ngabar_active_plan_id', planId);
    notifyListeners();
  }

  /// Activates Premium after QRIS / promo / sandbox verification.
  Future<void> activateWithCode(String planId) async {
    await _grantPremium(planId);
  }

  Future<void> clearForTesting() async {
    _activePlanId = null;
    isPremiumNotifier.value = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ngabar_is_premium', false);
    await prefs.remove('ngabar_active_plan_id');
    notifyListeners();
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }
}
