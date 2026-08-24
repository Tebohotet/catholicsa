import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// This is a genuine draft, written against what the app actually does -
/// not a placeholder, and not a legally-reviewed document either. POPIA
/// specifically requires a designated Information Officer and has real
/// data-subject-rights obligations; this covers the substance honestly
/// but the [DRAFT] labeling and the notice at the top are load-bearing,
/// not decoration. Have an attorney familiar with POPIA review and
/// finalise this before treating it as the app's binding policy.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              color: AppColors.stone,
              padding: const EdgeInsets.fromLTRB(4, 12, 16, 20),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                  const Text('Privacy Policy', style: TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: Colors.orange.withValues(alpha: 0.12),
                      child: const Text(
                        'DRAFT — this describes what the app actually collects and does with it, but has not been reviewed by an attorney. '
                        'South Africa\'s POPIA requires a designated Information Officer and gives real rights to the people whose data this app holds. '
                        'This should be reviewed and finalised by someone qualified before being relied on as the app\'s binding policy.',
                        style: TextStyle(fontSize: 12, color: Colors.deepOrange, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _section('1. What we collect', [
                      'Your name, email address, and profile photo, from Google Sign-In.',
                      'Phone numbers you provide - for confession bookings, Mass intention requests, marketplace purchases and sales, and donations.',
                      'Delivery addresses, if you choose courier delivery for a marketplace purchase.',
                      'Photos or PDFs you upload as proof of payment for a purchase or donation - these can show bank account details, since that\'s what a deposit slip or bank app screenshot contains.',
                      'Your approximate or precise location, only when a feature that needs it is actually used (e.g. finding the nearest church, or "Can I still make it?").',
                      'A device token used to deliver push notifications, if notifications are enabled.',
                      'Content you choose to post yourself - comments, ratings, course reviews, marketplace listings.',
                    ]),
                    _section('2. Why we collect it', [
                      'To show you relevant parish information and let you use features you\'ve chosen to use (bookings, purchases, donations, courses).',
                      'To let a parish confirm a payment was made, or a catechist confirm who\'s enrolled in their course.',
                      'To send notifications you\'ve opted into (new notices, Mass reminders, order and donation status updates).',
                      'Location is used only to power the specific feature that asked for it, at the moment it\'s used - not collected in the background.',
                    ]),
                    _section('3. Who can see it', [
                      'You can always see and manage your own data.',
                      'A parish\'s own admins (priest or secretary) can see information relevant to that parish - bookings, orders, donations, applications - not data from other parishes.',
                      'A small number of platform administrators can access data for support and moderation purposes.',
                      'We do not sell personal data, and do not share it with third parties beyond what\'s needed to provide the service itself (see section 5).',
                    ]),
                    _section('4. How long we keep it', [
                      'For as long as your account exists, plus what\'s reasonably needed for financial and pastoral record-keeping.',
                      'You can delete your account at any time from Settings. Deleting your account anonymises your public contributions (like comments) rather than removing them entirely, since removing them would also erase other people\'s replies and the parish\'s own record of the conversation - but your personal identifying information is removed.',
                    ]),
                    _section('5. Third-party services this app uses', [
                      'Google Firebase / Google Cloud - hosts the app\'s data and files.',
                      'Google Sign-In - handles authentication; we never see or store your Google password.',
                      'If a parish has configured its own payment gateway (PayFast, PayStack, or PayPal), that provider handles payment details directly - we don\'t store card numbers.',
                      'Bank deposit details you submit as proof of payment are stored to let the parish confirm your payment, and are only visible to you and that parish\'s admins.',
                    ]),
                    _section('6. Your rights under POPIA', [
                      'To ask what personal information we hold about you.',
                      'To ask us to correct information that\'s wrong.',
                      'To ask us to delete your information, subject to the record-keeping note in section 4.',
                      'To object to how your information is used.',
                      'To lodge a complaint with the Information Regulator of South Africa.',
                    ]),
                    const SizedBox(height: 20),
                    const Text(
                      '[Information Officer contact details to be added here - POPIA requires this parish/organisation to designate one]',
                      style: TextStyle(fontSize: 12, color: Colors.black45, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<String> points) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontFamily: appSerif, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...points.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  ', style: TextStyle(fontSize: 13)),
                    Expanded(child: Text(p, style: const TextStyle(fontSize: 13, height: 1.4))),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
