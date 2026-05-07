import 'package:flutter/material.dart';
import 'package:ortho_quant_md/services/subscription_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _isPurchasing = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SubscriptionService(),
      builder: (context, _) {
        final offerings = SubscriptionService().offerings;
        final currentOffering = offerings?.current;
        final packages = currentOffering?.availablePackages ?? [];

        return Scaffold(
          body: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF00BFA5), // Teal
                  Color(0xFF004D40), // Dark Teal
                ],
              ),
            ),
            child: SafeArea(
              child: Stack(
                children: [
                  Column(
                    children: [
                      // Header
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 30),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Icon(Icons.workspace_premium, color: Colors.amber, size: 80),
                      const SizedBox(height: 16),
                      const Text(
                        'OrthoQuant PRO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Text(
                        'Unlock advanced clinical analysis',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 40),

                      // Features List
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(40),
                              topRight: Radius.circular(40),
                            ),
                          ),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Premium Features',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF004D40),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                _buildFeatureItem(Icons.analytics_outlined, 'Advanced Templates', 'Access specialist templates (Glenoid, Spine, etc.)'),
                                _buildFeatureItem(Icons.folder_outlined, 'History Folder Structure', 'Organize and categorize your exams into folders'),
                                
                                const SizedBox(height: 32),
                                // Pricing Cards
                                if (packages.isEmpty)
                                  const Center(child: CircularProgressIndicator())
                                else
                                  ...packages.map((package) => _buildPackageCard(context, package)),

                                const SizedBox(height: 20),
                                
                                // Restore & Policy
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                  child: Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 8,
                                    children: [
                                      TextButton(
                                        onPressed: () => launchUrl(Uri.parse('https://gist.github.com/ilkereren/664c91885d847c7c69319b90629f40e6')),
                                        child: const Text('Privacy Policy', style: TextStyle(color: Colors.grey, fontSize: 13)),
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 12.0),
                                        child: Text('|', style: TextStyle(color: Colors.grey, fontSize: 13)),
                                      ),
                                      TextButton(
                                        onPressed: () => launchUrl(Uri.parse('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/')),
                                        child: const Text('Terms of Use', style: TextStyle(color: Colors.grey, fontSize: 13)),
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 12.0),
                                        child: Text('|', style: TextStyle(color: Colors.grey, fontSize: 13)),
                                      ),
                                      TextButton(
                                        onPressed: () async {
                                          await SubscriptionService().restorePurchases();
                                          if (SubscriptionService().isPro && context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Purchases restored successfully!')),
                                            );
                                            Navigator.pop(context);
                                          }
                                        },
                                        child: const Text('Restore', style: TextStyle(color: Colors.grey, fontSize: 13)),
                                      ),
                                    ],
                                  ),
                                ),
                                
                                const SizedBox(height: 12),
                                  const SizedBox(height: 24),
                                  // --- AUTO-RENEWAL DISCLOSURE ---
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.withAlpha(20),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Subscription Information:',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          '• Payment will be charged to your iTunes Account at confirmation of purchase.\n'
                                          '• Subscription automatically renews unless auto-renew is turned off at least 24-hours before the end of the current period.\n'
                                          '• Your account will be charged for renewal within 24-hours prior to the end of the current period.\n'
                                          '• Subscriptions may be managed by the user and auto-renewal may be turned off by going to the user\'s Account Settings after purchase.',
                                          style: TextStyle(fontSize: 11, color: Colors.black45, height: 1.4),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                // --- CONTRIBUTE & EARN PROMO ---
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E1E1E),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: Colors.amber.withOpacity(0.3), width: 1.5),
                                  ),
                                  child: Column(
                                    children: [
                                      const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.card_giftcard, color: Colors.amber, size: 24),
                                          SizedBox(width: 8),
                                          Text(
                                            'Want it for FREE?',
                                            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16),
                                          ),
                                        ],
                                      ),
                                        const SizedBox(height: 12),
                                      const Text(
                                        'Suggest a new clinical template logic.\nIf we implement it, you get 1 Month PRO.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                                      ),
                                      const SizedBox(height: 16),
                                      SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton(
                                          onPressed: _showRewardDialog,
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(color: Color(0xFF00BFA5)),
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                          child: const Text(
                                            'SEE HOW TO CONTRIBUTE',
                                            style: TextStyle(color: Color(0xFF00BFA5), fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 40),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_isPurchasing)
                    Container(
                      color: Colors.black26,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showRewardDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.card_giftcard, color: Colors.amber, size: 28),
            SizedBox(width: 12),
            Text('Contribute & Earn PRO', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Help us expand our clinical library!',
              style: TextStyle(color: Color(0xFF00BFA5), fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              'Suggest a new orthopedic template with clear landmarks and reference logic. If we implement your suggestion, we will gift you:',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '1 MONTH FREE PRO ACCESS',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Your contribution helps orthopedics around the world.',
              style: TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('LATER', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _launchRewardEmail();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00BFA5),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('SEND PROPOSAL'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchRewardEmail() async {
    const String body = """Medical Template Suggestion

Template Name: [e.g., Tibial Slope]
Clinical Reference (Link/Book):
Landmark Points (e.g., Center of Talus, Top of Calc):
1. 
2. 
Expected Result (e.g., Angle between A and B):

Reasoning/Importance:
""";

    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'ilker.eren@gmail.com',
      query: 'subject=OrthoQuant MD: Template Development Proposal&body=${Uri.encodeComponent(body)}',
    );

    try {
      if (!await launchUrl(emailLaunchUri)) {
        debugPrint('Could not launch email client');
      }
    } catch (e) {
      debugPrint('Error launching email: $e');
    }
  }

  Widget _buildFeatureItem(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00BFA5).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFF00BFA5), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageCard(BuildContext context, Package package) {
    final bool isBestValue = package.packageType == PackageType.annual;
    
    // Custom labels based on package type
    String displayTitle = 'Pro Access';
    if (package.packageType == PackageType.annual) {
      displayTitle = 'Pro Access - Annual';
    } else if (package.packageType == PackageType.monthly) {
      displayTitle = 'Pro Access - Monthly';
    }

    return GestureDetector(
      onTap: () async {
        setState(() => _isPurchasing = true);
        final success = await SubscriptionService().purchasePackage(package);
        setState(() => _isPurchasing = false);
        
        if (success && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Welcome to PRO!')),
          );
          Navigator.pop(context);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isBestValue ? const Color(0xFFF0FAF9) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isBestValue ? const Color(0xFF00BFA5) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        displayTitle,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      if (isBestValue)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00BFA5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'BEST VALUE',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    package.storeProduct.description,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  package.storeProduct.priceString,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF004D40)),
                ),
                Text(
                  package.packageType == PackageType.annual ? 'per year' : 'per month',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
