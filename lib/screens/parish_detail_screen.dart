import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../models/parish.dart';
import '../models/church.dart';
import '../theme/app_theme.dart';
import '../widgets/async_section.dart';
import '../widgets/church_form_dialogs.dart';
import 'church_detail_screen.dart';
import '../widgets/hierarchy_summary_sections.dart';
import 'search_screen.dart';
import 'admin_panel_screen.dart' show ParishVisibilitySection;

/// One level up from ChurchDetailScreen - same shape (header, quick actions,
/// section list) but everything below the header is aggregated from every
/// church in this parish rather than being this page's own data. That
/// aggregation pattern (loop over children, tag each result with which
/// child it came from) is exactly what a future DioceseDetailScreen would
/// reuse, just looping over parishes instead of churches.
class ParishDetailScreen extends StatefulWidget {
  final String parishId;
  const ParishDetailScreen({super.key, required this.parishId});

  @override
  State<ParishDetailScreen> createState() => _ParishDetailScreenState();
}

class _ParishDetailScreenState extends State<ParishDetailScreen> {
  // Gates the inline "+" next to Churches below - whether this account
  // can add a church/venue to THIS parish (a registered admin there,
  // or Super Admin/Developer). See AuthService.canManageParish for why
  // this exists: so an admin looking at their own parish page doesn't
  // have to leave it and go hunting for the separate Admin Panel.
  bool _canManage = false;

  @override
  void initState() {
    super.initState();
    AuthService().canManageParish(widget.parishId).then((v) {
      if (mounted) setState(() => _canManage = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: FutureBuilder<Parish>(
        future: FirestoreService().getParish(widget.parishId),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: ${snap.error}')));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final parish = snap.data!;

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
                            Row(
                              children: [
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                                  onPressed: () => Navigator.pop(context),
                                ),
                                const Spacer(),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(Icons.search, color: Colors.white, size: 20),
                                  onPressed: () => Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => SearchScreen(scopeParishId: widget.parishId, scopeParishName: parish.name),
                                  )),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(parish.name, style: const TextStyle(fontFamily: appSerif, fontSize: 26, color: Colors.white)),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10, runSpacing: 10,
                              children: [
                                if (parish.contactPhone.isNotEmpty)
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                                    onPressed: () => launchUrl(Uri.parse('tel:${parish.contactPhone}')),
                                    icon: const Icon(Icons.phone, size: 15),
                                    label: Text(parish.contactPhone),
                                  ),
                                if (parish.contactEmail.isNotEmpty)
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                                    onPressed: () => launchUrl(Uri.parse('mailto:${parish.contactEmail}')),
                                    icon: const Icon(Icons.email_outlined, size: 15),
                                    label: const Text('Email'),
                                  ),
                                if (parish.socialLinks['facebook'] != null)
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                                    onPressed: () => launchUrl(Uri.parse(parish.socialLinks['facebook']!), mode: LaunchMode.externalApplication),
                                    icon: const Icon(Icons.facebook, size: 15),
                                    label: const Text('Facebook'),
                                  ),
                              ],
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
                          // The only reachable place a Super Admin who
                          // isn't personally registered as this parish's
                          // own admin can flip "Visible in public
                          // Browse" - the Admin Panel screen that also
                          // has this switch is only linked from the
                          // Account screen's own "Admin Of" list, which
                          // a Super Admin visiting someone else's parish
                          // wouldn't be on. _canManage already covers
                          // Super Admin/Developer for ANY parish (see
                          // AuthService.canManageParish), not just one
                          // you're personally an admin of.
                          if (_canManage) ...[
                            ParishVisibilitySection(parishId: widget.parishId),
                            const SizedBox(height: 20),
                          ],
                          SectionLabel(
                            numeral: 'I',
                            title: 'Churches',
                            trailing: _canManage
                                ? PopupMenuButton<String>(
                                    tooltip: 'Add a church or Mass venue',
                                    icon: const Icon(Icons.add_circle_outline, size: 20, color: AppColors.brass),
                                    padding: EdgeInsets.zero,
                                    onSelected: (v) {
                                      if (v == 'church') {
                                        showChurchFormDialog(context, parishId: widget.parishId, onSaved: (_) => setState(() {}));
                                      } else {
                                        showVenueFormDialog(context, parishId: widget.parishId, onSaved: (_) => setState(() {}));
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'church', child: Text('Add Church')),
                                      PopupMenuItem(value: 'venue', child: Text('Add Mass Venue')),
                                    ],
                                  )
                                : null,
                          ),
                          AsyncSection<List<Church>>(
                            future: FirestoreService().getChurches(widget.parishId).then((l) => l.where((c) => c.isActive).toList()),
                            isEmpty: (l) => l.isEmpty,
                            emptyMessage: 'No churches added to this parish yet.',
                            builder: (context, churches) => Column(
                              children: churches.map((c) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.church, color: AppColors.brass, size: 20),
                                title: Text(c.name),
                                subtitle: Text(c.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: const Icon(Icons.chevron_right, size: 18),
                                onTap: () => Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => ChurchDetailScreen(parishId: widget.parishId, churchId: c.id, backLabel: parish.name),
                                )),
                              )).toList(),
                            ),
                          ),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'II', title: 'Parochial Notices'),
                          NoticesSummarySection(future: FirestoreService().getParishNotices(widget.parishId), tagKey: 'churchName'),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'III', title: 'Prayers'),
                          PrayersSummarySection(future: FirestoreService().getParishPrayers(widget.parishId), tagKey: 'churchName'),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'IV', title: 'Courses'),
                          CoursesSummarySection(future: FirestoreService().getParishCourses(widget.parishId), tagKey: 'churchName'),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'V', title: 'Gallery'),
                          GallerySummarySection(future: FirestoreService().getParishApprovedMedia(widget.parishId)),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'VI', title: 'Marketplace'),
                          ProductsSummarySection(future: FirestoreService().getParishProducts(widget.parishId), tagKey: 'churchName', parishId: widget.parishId),

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