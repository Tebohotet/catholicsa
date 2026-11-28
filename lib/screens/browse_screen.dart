import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firestore_service.dart';
import '../models/church.dart';
import '../theme/app_theme.dart';
import '../providers/view_as_role_provider.dart';
import 'church_detail_screen.dart';
import 'parish_detail_screen.dart';
import 'diocese_detail_screen.dart';
import 'province_detail_screen.dart';
import 'search_screen.dart';
import '../widgets/hierarchy_summary_sections.dart';
import '../widgets/quick_nav_icons.dart';
import '../widgets/profile_menu_button.dart';

IconData _buildingIcon(String type) {
  switch (type) {
    case 'Cathedral':
    case 'Basilica':
      return Icons.account_balance;
    case 'Convent':
    case 'Chapel':
      return Icons.home_work;
    default:
      return Icons.church;
  }
}

/// A flat header block - stone gradient, serif title, optional back button.
/// Not pinned/collapsing, just scrolls with the page like the prototype.
class _StoneHeader extends StatelessWidget {
  final String title;
  final List<String> breadcrumb;
  final Widget? trailing;
  const _StoneHeader({required this.title, this.breadcrumb = const [], this.trailing});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        color: AppColors.stone,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (Navigator.canPop(context))
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                if (breadcrumb.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Expanded(
                    child: Wrap(
                      spacing: 6, runSpacing: 4,
                      children: breadcrumb.map((b) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(border: Border.all(color: Colors.white38), borderRadius: BorderRadius.circular(3)),
                        child: Text(b, style: const TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 0.3)),
                      )).toList(),
                    ),
                  ),
                ],
                if (trailing != null) ...[const Spacer(), trailing!],
              ],
            ),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontFamily: appSerif, fontSize: 26, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _FlatListCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  const _FlatListCard({required this.title, this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.paperDark,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(subtitle!, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                      ],
                    ],
                  ),
                ),
                if (onTap != null) const Icon(Icons.chevron_right, size: 18, color: Colors.black45),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full South Africa -> Province -> Diocese -> Parish hierarchy, same as
/// before - but only an admin sees it by default. For everyone else,
/// while there's genuinely only one parish with real data entered
/// (`isActive` - see _ParishVisibilitySection in admin_panel_screen.dart),
/// browsing straight into Province/Diocese/Parish lists to find the one
/// real entry isn't useful - it's just extra taps to reach the only
/// thing actually there. The moment a second parish goes active, this
/// naturally falls back to the full hierarchy on its own, no code change
/// needed.
class BrowseScreen extends ConsumerWidget {
  const BrowseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isRealSuperAdminProvider).maybeWhen(data: (v) => v, orElse: () => false);
    if (!isAdmin) {
      return FutureBuilder<List<Map<String, dynamic>>>(
        future: FirestoreService().getActiveParishes(),
        builder: (context, activeSnap) {
          if (!activeSnap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          final active = activeSnap.data!;
          if (active.length == 1) {
            return ParishDetailScreen(parishId: active.first['id'] as String);
          }
          return _BrowseHierarchy(isAdmin: isAdmin);
        },
      );
    }
    return _BrowseHierarchy(isAdmin: isAdmin);
  }
}

class _BrowseHierarchy extends StatelessWidget {
  final bool isAdmin;
  const _BrowseHierarchy({required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StoneHeader(
              title: 'South Africa',
              // Same uniform-header icon set Readings/Hymns already have,
              // plus this page's own existing search icon and a real
              // embedded profile button - this tab root previously relied
              // on HomeShell's floating profile button instead (fine on
              // its own, but inconsistent with Readings/Hymns, which both
              // embed it directly in their header for the same reason:
              // see home_screen.dart's own index exclusion list, updated
              // alongside this change).
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.search, color: Colors.white),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
                  ),
                  const QuickNavIcons(),
                  const ProfileMenuButton(embedded: true),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: CenteredContent(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: FirestoreService().getProvinces(),
                builder: (context, snap) {
                  if (snap.hasError) return Text('Error: ${snap.error}');
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  // Same isActive-defaults-to-true convention as Parish/
                  // Church - a Super Admin sees every province regardless
                  // (same "admin sees everything" rule already applied to
                  // the Province->Diocese->Parish hierarchy itself), an
                  // ordinary visitor only sees ones not explicitly hidden.
                  // Toggle lives in Super Admin -> Directory -> Provinces.
                  final allProvinces = snap.data!;
                  final provinces = isAdmin ? allProvinces : allProvinces.where((p) => (p['isActive'] as bool?) ?? true).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel(numeral: 'I', title: 'Ecclesiastical Provinces'),
                      ...provinces.map((p) => _FlatListCard(
                            title: p['name'],
                            onTap: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => ProvinceDetailScreen(provinceId: p['id']),
                            )),
                          )),

                      const SizedBox(height: 28),
                      const SectionLabel(numeral: 'II', title: 'Parochial Notices'),
                      NoticesSummarySection(future: FirestoreService().getNationalNotices(includeHidden: isAdmin), tagKey: 'provinceName'),

                      const SizedBox(height: 28),
                      const SectionLabel(numeral: 'III', title: 'Prayers'),
                      PrayersSummarySection(future: FirestoreService().getNationalPrayers(includeHidden: isAdmin), tagKey: 'provinceName'),

                      const SizedBox(height: 28),
                      const SectionLabel(numeral: 'IV', title: 'Courses'),
                      CoursesSummarySection(future: FirestoreService().getNationalCourses(includeHidden: isAdmin), tagKey: 'provinceName'),

                      const SizedBox(height: 28),
                      const SectionLabel(numeral: 'V', title: 'Gallery'),
                      GallerySummarySection(future: FirestoreService().getNationalApprovedMedia(includeHidden: isAdmin)),

                      const SizedBox(height: 28),
                      const SectionLabel(numeral: 'VI', title: 'Marketplace'),
                      ProductsSummarySection(future: FirestoreService().getNationalProducts(includeHidden: isAdmin), tagKey: 'provinceName'),
                    ],
                  );
                },
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }
}

class DioceseListScreen extends StatelessWidget {
  final String provinceId;
  final String provinceName;
  const DioceseListScreen({super.key, required this.provinceId, required this.provinceName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StoneHeader(
              title: provinceName,
              breadcrumb: const ['South Africa'],
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [QuickNavIcons(), ProfileMenuButton(embedded: true)],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: CenteredContent(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: FirestoreService().getDioceses(provinceId),
                builder: (context, snap) {
                  if (snap.hasError) return Text('Error: ${snap.error}');
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final dioceses = snap.data!;
                  if (dioceses.isEmpty) {
                    return const Text('No dioceses added here yet.', style: TextStyle(color: Colors.black45));
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel(numeral: 'I', title: 'Archdiocese & Dioceses'),
                      ...dioceses.map((d) => _FlatListCard(
                            title: d['name'],
                            subtitle: '${d['type'] ?? 'Diocese'}${d['bishopName'] != null ? ' · ${d['bishopTitle'] ?? 'Bishop'} ${d['bishopName']}' : ''}',
                            onTap: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => DioceseDetailScreen(dioceseId: d['id']),
                            )),
                          )),
                    ],
                  );
                },
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }
}

class ParishListScreen extends StatelessWidget {
  final String dioceseId;
  final String dioceseName;
  final String provinceName;
  const ParishListScreen({super.key, required this.dioceseId, required this.dioceseName, required this.provinceName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StoneHeader(
              title: dioceseName,
              breadcrumb: ['South Africa', provinceName],
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [QuickNavIcons(), ProfileMenuButton(embedded: true)],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: CenteredContent(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: FirestoreService().getParishes(dioceseId),
                builder: (context, snap) {
                  if (snap.hasError) return Text('Error: ${snap.error}');
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final parishes = snap.data!;
                  if (parishes.isEmpty) {
                    return const Text('No parishes added here yet.', style: TextStyle(color: Colors.black45));
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel(numeral: 'I', title: 'Parishes'),
                      ...parishes.map((p) => _FlatListCard(
                            title: p['name'],
                            onTap: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => ParishDetailScreen(parishId: p['id']),
                            )),
                          )),
                    ],
                  );
                },
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The screen you referenced from the prototype - banner with an
/// overlapping logo circle, then a grid of church cards to select from.
class ChurchListScreen extends StatelessWidget {
  final String parishId;
  final String parishName;
  final String dioceseName;
  final String provinceName;
  const ChurchListScreen({
    super.key, required this.parishId, required this.parishName,
    required this.dioceseName, required this.provinceName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SafeArea(
              bottom: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [AppColors.stone, AppColors.stoneDark],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 4),
                        Wrap(
                          spacing: 6,
                          children: ['South Africa', provinceName, dioceseName].map((b) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(border: Border.all(color: Colors.white38), borderRadius: BorderRadius.circular(3)),
                            child: Text(b, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                          )).toList(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(
                            color: AppColors.paperDark, shape: BoxShape.circle,
                            border: Border.all(color: AppColors.brass, width: 2),
                          ),
                          child: Center(
                            child: Text(
                              parishName.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join(),
                              style: const TextStyle(fontFamily: appSerif, fontSize: 18, color: AppColors.stone),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(parishName, style: const TextStyle(fontFamily: appSerif, fontSize: 26, color: Colors.white)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CenteredContent(
                child: FutureBuilder(
                future: FirestoreService().getChurches(parishId).then((l) => l.where((c) => c.isActive).toList()),
                builder: (context, snap) {
                  if (snap.hasError) return Text('Error: ${snap.error}');
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final churches = snap.data!;
                  if (churches.isEmpty) {
                    return const Text('No churches added here yet.', style: TextStyle(color: Colors.black45));
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel(numeral: 'I', title: 'Churches in this Parish'),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.95,
                        ),
                        itemCount: churches.length,
                        itemBuilder: (context, i) {
                          final c = churches[i];
                          return _ChurchCard(
                            church: c,
                            onTap: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => ChurchDetailScreen(parishId: parishId, churchId: c.id, parishName: parishName, backLabel: parishName),
                            )),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                  );
                },
              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChurchCard extends StatelessWidget {
  final Church church;
  final VoidCallback onTap;
  const _ChurchCard({required this.church, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.paperDark,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BannerPlaceholder(height: 80, icon: _buildingIcon(church.buildingType)),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(church.name, style: const TextStyle(fontFamily: appSerif, fontSize: 14, fontWeight: FontWeight.bold),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 11, color: AppColors.ink),
                      const SizedBox(width: 3),
                      Expanded(child: Text(church.address, style: const TextStyle(fontSize: 10, color: Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
