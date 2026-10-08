import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'organization_subscription_service.dart';

class OrganizationBillingUpdate {
  final String status;
  final String message;

  const OrganizationBillingUpdate({
    required this.status,
    required this.message,
  });
}

class OrganizationBillingService {
  OrganizationBillingService._();

  static final OrganizationBillingService instance =
      OrganizationBillingService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _pendingOrganizationKey =
      'keeper_pending_subscription_organization';

  final InAppPurchase _store = InAppPurchase.instance;
  final StreamController<OrganizationBillingUpdate> _updates =
      StreamController<OrganizationBillingUpdate>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  Stream<OrganizationBillingUpdate> get updates => _updates.stream;

  Future<void> initialize() async {
    _purchaseSubscription ??= _store.purchaseStream.listen(
      _handlePurchases,
      onError: (_) {
        _updates.add(
          const OrganizationBillingUpdate(
            status: 'error',
            message: 'Unable to receive Google Play payment updates.',
          ),
        );
      },
    );
  }

  Future<ProductDetails?> loadMonthlyPlan() async {
    final DocumentSnapshot<Map<String, dynamic>> billingConfig =
        await FirebaseFirestore.instance
            .collection('app_config')
            .doc('billing')
            .get();
    final bool enabled =
        billingConfig.data()?['organizationSubscriptionsEnabled'] as bool? ??
        false;
    if (!enabled) return null;
    if (!await _store.isAvailable()) return null;
    final ProductDetailsResponse response = await _store.queryProductDetails({
      OrganizationSubscriptionService.productId,
    });
    if (response.error != null || response.productDetails.isEmpty) return null;
    return response.productDetails.first;
  }

  Future<bool> startMonthlySubscription({
    required ProductDetails product,
    required String organizationId,
  }) async {
    await initialize();
    await _storage.write(key: _pendingOrganizationKey, value: organizationId);
    return _store.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final PurchaseDetails purchase in purchases) {
      if (purchase.productID != OrganizationSubscriptionService.productId) {
        continue;
      }

      if (purchase.status == PurchaseStatus.pending) {
        _updates.add(
          const OrganizationBillingUpdate(
            status: 'pending',
            message: 'Payment is pending in Google Play.',
          ),
        );
        continue;
      }

      if (purchase.status == PurchaseStatus.error) {
        _updates.add(
          OrganizationBillingUpdate(
            status: 'error',
            message: purchase.error?.message ?? 'Payment failed.',
          ),
        );
        continue;
      }

      if (purchase.status == PurchaseStatus.canceled) {
        _updates.add(
          const OrganizationBillingUpdate(
            status: 'cancelled',
            message: 'Payment was cancelled.',
          ),
        );
        continue;
      }

      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }

      final String organizationId =
          await _storage.read(key: _pendingOrganizationKey) ?? '';
      if (organizationId.isEmpty) {
        _updates.add(
          const OrganizationBillingUpdate(
            status: 'verification_pending',
            message:
                'Purchase found. Open the organization plan to finish verification.',
          ),
        );
        continue;
      }

      _updates.add(
        const OrganizationBillingUpdate(
          status: 'verifying',
          message: 'Verifying your subscription securely...',
        ),
      );

      try {
        final String requestId = await submitForSecureVerification(
          organizationId: organizationId,
          purchase: purchase,
        );
        final bool verified = await waitForVerification(requestId);
        if (!verified) {
          _updates.add(
            const OrganizationBillingUpdate(
              status: 'verification_pending',
              message:
                  'Verification is still pending. Please check again shortly.',
            ),
          );
          continue;
        }

        await complete(purchase);
        await _storage.delete(key: _pendingOrganizationKey);
        _updates.add(
          const OrganizationBillingUpdate(
            status: 'active',
            message: 'Subscription activated successfully.',
          ),
        );
      } catch (_) {
        _updates.add(
          const OrganizationBillingUpdate(
            status: 'verification_pending',
            message: 'Payment received, but secure verification is pending.',
          ),
        );
      }
    }
  }

  Future<String> submitForSecureVerification({
    required String organizationId,
    required PurchaseDetails purchase,
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Please sign in again.');

    final DocumentReference<Map<String, dynamic>> request =
        await FirebaseFirestore.instance
            .collection('subscription_verification_requests')
            .add({
              'organizationId': organizationId,
              'userId': user.uid,
              'productId': purchase.productID,
              'purchaseId': purchase.purchaseID ?? '',
              'serverVerificationData':
                  purchase.verificationData.serverVerificationData,
              'verificationSource': purchase.verificationData.source,
              'status': 'pending',
              'createdAt': FieldValue.serverTimestamp(),
            });
    return request.id;
  }

  Future<bool> waitForVerification(String requestId) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> result =
          await FirebaseFirestore.instance
              .collection('subscription_verification_requests')
              .doc(requestId)
              .snapshots()
              .firstWhere((snapshot) {
                final String status =
                    snapshot.data()?['status']?.toString() ?? 'pending';
                return status == 'verified' || status == 'rejected';
              })
              .timeout(const Duration(seconds: 90));
      return result.data()?['status'] == 'verified';
    } on TimeoutException {
      return false;
    }
  }

  Future<void> complete(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      await _store.completePurchase(purchase);
    }
  }

  Future<void> restorePurchases() => _store.restorePurchases();
}
