import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OrganizationSubscriptionAccess {
  final String organizationId;
  final String organizationName;
  final String ownerId;
  final String status;
  final DateTime trialEndsAt;
  final DateTime? currentPeriodEnd;
  final bool isOwner;

  const OrganizationSubscriptionAccess({
    required this.organizationId,
    required this.organizationName,
    required this.ownerId,
    required this.status,
    required this.trialEndsAt,
    required this.currentPeriodEnd,
    required this.isOwner,
  });

  bool get isTrialActive => status == 'trialing';
  bool get isSubscriptionActive => status == 'active';
  bool get isFreeAccess =>
      !OrganizationSubscriptionService.subscriptionsEnabled;
  bool get canUseOrganizationUploads =>
      isFreeAccess || isTrialActive || isSubscriptionActive;

  int get trialDaysRemaining {
    if (!isTrialActive) return 0;
    final Duration remaining = trialEndsAt.difference(DateTime.now());
    if (remaining.isNegative) return 0;
    return (remaining.inMinutes / Duration.minutesPerDay).ceil();
  }
}

class OrganizationSubscriptionService {
  OrganizationSubscriptionService._();

  // Keep organizations free until Play Store billing is ready. Change this to
  // true only when the subscription product and secure backend are live.
  static const bool subscriptionsEnabled = false;
  static const int trialDays = 14;
  static const int monthlyPriceInr = 499;
  static const String productId = 'keeper_organization_monthly_499';

  static DateTime? _date(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '');
  }

  static Future<OrganizationSubscriptionAccess> load(
    String organizationId,
  ) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Please sign in again.');

    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await FirebaseFirestore.instance
            .collection('organizations')
            .doc(organizationId)
            .get();

    if (!snapshot.exists) {
      throw StateError('Organization is no longer available.');
    }

    final Map<String, dynamic> data = snapshot.data() ?? const {};
    final DateTime now = DateTime.now();
    final DateTime createdAt =
        _date(data['trialStartedAt']) ?? _date(data['createdAt']) ?? now;
    final DateTime trialEndsAt =
        _date(data['trialEndsAt']) ??
        createdAt.add(const Duration(days: trialDays));
    final DateTime? currentPeriodEnd = _date(data['currentPeriodEnd']);
    final String storedStatus =
        data['subscriptionStatus']?.toString().toLowerCase() ?? 'trialing';

    String effectiveStatus;
    if (!subscriptionsEnabled) {
      effectiveStatus = 'free';
    } else if (storedStatus == 'active' &&
        currentPeriodEnd != null &&
        currentPeriodEnd.isAfter(now)) {
      effectiveStatus = 'active';
    } else if (trialEndsAt.isAfter(now)) {
      effectiveStatus = 'trialing';
    } else {
      effectiveStatus = 'expired';
    }

    final String ownerId = data['ownerId']?.toString() ?? '';
    return OrganizationSubscriptionAccess(
      organizationId: organizationId,
      organizationName: data['name']?.toString() ?? 'Organization',
      ownerId: ownerId,
      status: effectiveStatus,
      trialEndsAt: trialEndsAt,
      currentPeriodEnd: currentPeriodEnd,
      isOwner: ownerId == user.uid,
    );
  }

  static Stream<OrganizationSubscriptionAccess> watch(String organizationId) {
    return FirebaseFirestore.instance
        .collection('organizations')
        .doc(organizationId)
        .snapshots()
        .asyncMap((_) => load(organizationId));
  }
}
