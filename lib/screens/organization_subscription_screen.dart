import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../services/organization_billing_service.dart';
import '../services/organization_subscription_service.dart';

class OrganizationSubscriptionScreen extends StatefulWidget {
  final String organizationId;
  final String organizationName;

  const OrganizationSubscriptionScreen({
    super.key,
    required this.organizationId,
    required this.organizationName,
  });

  @override
  State<OrganizationSubscriptionScreen> createState() =>
      _OrganizationSubscriptionScreenState();
}

class _OrganizationSubscriptionScreenState
    extends State<OrganizationSubscriptionScreen> {
  StreamSubscription<OrganizationBillingUpdate>? _purchaseSubscription;
  OrganizationSubscriptionAccess? _access;
  ProductDetails? _product;
  bool _isLoading = true;
  bool _isPurchasing = false;
  String? _storeMessage;

  @override
  void initState() {
    super.initState();
    _purchaseSubscription = OrganizationBillingService.instance.updates.listen(
      _handleBillingUpdate,
    );
    _load();
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        OrganizationSubscriptionService.load(widget.organizationId),
        OrganizationBillingService.instance.loadMonthlyPlan(),
      ]);
      if (!mounted) return;
      setState(() {
        _access = results[0] as OrganizationSubscriptionAccess;
        _product = results[1] as ProductDetails?;
        _storeMessage = _product == null
            ? 'The Google Play subscription is not available yet.'
            : null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _storeMessage = 'Unable to load the organization plan.';
      });
    }
  }

  Future<void> _handleBillingUpdate(OrganizationBillingUpdate update) async {
    if (!mounted) return;
    setState(() {
      _isPurchasing =
          update.status == 'pending' || update.status == 'verifying';
      _storeMessage = update.message;
    });
    if (update.status == 'active') {
      await _load();
    }
  }

  Future<void> _subscribe() async {
    final ProductDetails? product = _product;
    if (product == null || _isPurchasing) return;
    setState(() {
      _isPurchasing = true;
      _storeMessage = null;
    });
    final bool started = await OrganizationBillingService.instance
        .startMonthlySubscription(
          product: product,
          organizationId: widget.organizationId,
        );
    if (!started && mounted) {
      setState(() {
        _isPurchasing = false;
        _storeMessage = 'Unable to open Google Play payment.';
      });
    }
  }

  String _statusText(OrganizationSubscriptionAccess access) {
    if (access.isSubscriptionActive) return 'Active subscription';
    if (access.isTrialActive) {
      return '${access.trialDaysRemaining} trial day(s) remaining';
    }
    return 'Free trial ended';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D18),
        foregroundColor: Colors.white,
        title: const Text(
          'Organization Plan',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFC857)),
            )
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF503E14), Color(0xFF201B12)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFFFC857)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.workspace_premium_rounded,
                          color: Color(0xFFFFD978),
                          size: 34,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.organizationName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          _access == null
                              ? 'Organization subscription'
                              : _statusText(_access!),
                          style: const TextStyle(
                            color: Color(0xFFFFE4A3),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          _product?.price ?? '₹499/month',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'One subscription covers the complete organization. Members never pay separately.',
                          style: TextStyle(
                            color: Color(0xFFD7CCAF),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _PlanFeature(
                    icon: Icons.groups_rounded,
                    text: 'Access for all organization members',
                  ),
                  const _PlanFeature(
                    icon: Icons.upload_file_rounded,
                    text: 'Organization document uploads',
                  ),
                  const _PlanFeature(
                    icon: Icons.forum_rounded,
                    text: 'Organization chat and shared knowledge',
                  ),
                  if (_storeMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _storeMessage!,
                      style: const TextStyle(
                        color: Color(0xFFFFD978),
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _product == null || _isPurchasing
                        ? null
                        : _subscribe,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: const Color(0xFFFFC857),
                      foregroundColor: const Color(0xFF211800),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                    icon: _isPurchasing
                        ? const SizedBox(
                            width: 19,
                            height: 19,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_open_rounded),
                    label: Text(
                      _isPurchasing
                          ? 'Please wait...'
                          : 'Subscribe for ${_product?.price ?? '₹499/month'}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton(
                    onPressed: _isPurchasing
                        ? null
                        : OrganizationBillingService.instance.restorePurchases,
                    child: const Text('Restore purchase'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _PlanFeature extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PlanFeature({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFAAA4FF)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
