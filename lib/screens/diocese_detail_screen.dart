import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/async_section.dart';
import '../widgets/hierarchy_summary_sections.dart';
import 'parish_detail_screen.dart';

/// Same concept as ParishDetailScreen, one level up - header, quick actions,
/// children list (Parishes here, Churches there), and the same four
/// summary sections aggregated from those children.
class DioceseDetailScreen extends StatelessWidget {
  final String dioceseId;
  const DioceseDetailScreen({super.key, required this.dioceseId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: FutureBuilder<Map<String, dynamic>>(
        future: FirestoreService().getDioceseById(dioceseId),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: ${snap.error}')));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final diocese = snap.data!;

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SafeArea(
                  bottom: false,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.stone, AppColors.stoneDark]),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 960),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                              onPressed: () => Navigator.pop(context),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(border: Border.all(color: Colors.white38), borderRadius: BorderRadius.circular(3)),
                              child: Text((diocese['type'] ?? 'Diocese').toString().toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 9, letterSpacing: 0.5)),
                            ),
                            Text(diocese['name'] ?? '', style: const TextStyle(fontFamily: appSerif, fontSize: 26, color: Colors.white)),
                            const SizedBox(height: 12),
                            FutureBuilder<Map<String, dynamic>?>(
                              future: FirestoreService().getDioceseLeadership(dioceseId),
                              builder: (context, leadershipSnap) {
                                final leadership = leadershipSnap.data;
                                if (leadership == null) return const SizedBox.shrink();
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (leadership['bishopName'] != null)
                                      Text('${leadership['bishopTitle'] ?? 'Bishop'} ${leadership['bishopName']}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 10, runSpacing: 10,
                                      children: [
                                        if (leadership['phone'] != null)
                                          OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                                            onPressed: () => launchUrl(Uri.parse('tel:${leadership['phone']}')),
                                            icon: const Icon(Icons.phone, size: 15),
                                            label: Text(leadership['phone']),
                                          ),
                                        if (leadership['email'] != null)
                                          OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                                            onPressed: () => launchUrl(Uri.parse('mailto:${leadership['email']}')),
                                            icon: const Icon(Icons.email_outlined, size: 15),
                                            label: const Text('Email'),
                                          ),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionLabel(numeral: 'I', title: 'Parishes'),
                          AsyncSection<List<Map<String, dynamic>>>(
                            future: FirestoreService().getParishes(dioceseId),
                            isEmpty: (l) => l.isEmpty,
                            emptyMessage: 'No parishes added to this diocese yet.',
                            builder: (context, parishes) => Column(
                              children: parishes.map((p) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.location_city, color: AppColors.brass, size: 20),
                                title: Text(p['name'] ?? ''),
                                trailing: const Icon(Icons.chevron_right, size: 18),
                                onTap: () => Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => ParishDetailScreen(parishId: p['id']),
                                )),
                              )).toList(),
                            ),
                          ),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'II', title: 'Parochial Notices'),
                          NoticesSummarySection(future: FirestoreService().getDioceseNotices(dioceseId), tagKey: 'parishName'),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'III', title: 'Prayers'),
                          PrayersSummarySection(future: FirestoreService().getDiocesePrayers(dioceseId), tagKey: 'parishName'),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'IV', title: 'Courses'),
                          CoursesSummarySection(future: FirestoreService().getDioceseCourses(dioceseId), tagKey: 'parishName'),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'V', title: 'Gallery'),
                          GallerySummarySection(future: FirestoreService().getDioceseApprovedMedia(dioceseId)),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'VI', title: 'Marketplace'),
                          ProductsSummarySection(future: FirestoreService().getDioceseProducts(dioceseId), tagKey: 'parishName'),

                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
