import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/async_section.dart';
import '../widgets/hierarchy_summary_sections.dart';
import 'diocese_detail_screen.dart';

/// Same concept one level up again - Province -> Dioceses, same four
/// summary sections, reusing getProvinceX() which itself reuses
/// getDioceseX() which reuses getParishX(). Nothing new to design here,
/// just the next rung of the same ladder.
class ProvinceDetailScreen extends StatelessWidget {
  final String provinceId;
  const ProvinceDetailScreen({super.key, required this.provinceId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: FutureBuilder<Map<String, dynamic>>(
        future: FirestoreService().getProvinceById(provinceId),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: ${snap.error}')));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final province = snap.data!;

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
                              child: const Text('PROVINCE', style: TextStyle(color: Colors.white70, fontSize: 9, letterSpacing: 0.5)),
                            ),
                            Text(province['name'] ?? '', style: const TextStyle(fontFamily: appSerif, fontSize: 26, color: Colors.white)),
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
                          const SectionLabel(numeral: 'I', title: 'Archdiocese & Dioceses'),
                          AsyncSection<List<Map<String, dynamic>>>(
                            future: FirestoreService().getDioceses(provinceId),
                            isEmpty: (l) => l.isEmpty,
                            emptyMessage: 'No dioceses added to this province yet.',
                            builder: (context, dioceses) => Column(
                              children: dioceses.map((d) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.account_balance, color: AppColors.brass, size: 20),
                                title: Text(d['name'] ?? ''),
                                subtitle: Text(d['type'] ?? 'Diocese'),
                                trailing: const Icon(Icons.chevron_right, size: 18),
                                onTap: () => Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => DioceseDetailScreen(dioceseId: d['id']),
                                )),
                              )).toList(),
                            ),
                          ),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'II', title: 'Parochial Notices'),
                          NoticesSummarySection(future: FirestoreService().getProvinceNotices(provinceId), tagKey: 'dioceseName'),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'III', title: 'Prayers'),
                          PrayersSummarySection(future: FirestoreService().getProvincePrayers(provinceId), tagKey: 'dioceseName'),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'IV', title: 'Courses'),
                          CoursesSummarySection(future: FirestoreService().getProvinceCourses(provinceId), tagKey: 'dioceseName'),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'V', title: 'Gallery'),
                          GallerySummarySection(future: FirestoreService().getProvinceApprovedMedia(provinceId)),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'VI', title: 'Marketplace'),
                          ProductsSummarySection(future: FirestoreService().getProvinceProducts(provinceId), tagKey: 'dioceseName'),

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
