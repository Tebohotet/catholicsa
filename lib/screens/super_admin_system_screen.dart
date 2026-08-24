import 'package:flutter/material.dart';
import 'super_admin_panel_screen.dart';
import 'hymns_admin_section.dart';
import '../widgets/super_admin_menu_widgets.dart';
import '../theme/app_theme.dart';

/// Content/data sections grouped under one "System" menu - each of these
/// already exists as a real, working widget (built and refined earlier
/// this session); this screen doesn't rebuild them, it hosts the same
/// widgets in a focused, single-purpose page instead of one long scroll.
class SuperAdminSystemScreen extends StatelessWidget {
  const SuperAdminSystemScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <_SystemMenuItem>[
      _SystemMenuItem('Saints Database', Icons.church_outlined, 'Feast dates, patronage, and biography for every saint in the app.', (ctx) => const AdminSectionHost(title: 'Saints Database', child: SaintsManagementSection())),
      _SystemMenuItem('Bible', Icons.menu_book_outlined, 'Translations, chapters, and the full-Bible sync tool.', (ctx) => const AdminSectionHost(title: 'Bible', child: BibleManagementSection())),
      _SystemMenuItem('Bible Cross-References', Icons.link, 'Link an Old Testament passage to its New Testament fulfilment.', (ctx) => const AdminSectionHost(title: 'Bible Cross-References', child: CrossReferencesSection())),
      _SystemMenuItem('Liturgical Readings', Icons.auto_stories_outlined, "Each day's Mass readings, antiphons, and Prayers of the Faithful.", (ctx) => const AdminSectionHost(title: 'Liturgical Readings', child: LiturgicalReadingsSection())),
      _SystemMenuItem('Feast Calendar Sync', Icons.sync, 'Pull a year of real feast data from the LitCal API.', (ctx) => const AdminSectionHost(title: 'Feast Calendar Sync', child: FeastCalendarSyncSection())),
      _SystemMenuItem('Hymns', Icons.library_music_outlined, '214 Catholic hymns from CMAA, each linking to real PDF sheet music.', (ctx) => const AdminSectionHost(title: 'Hymns', child: HymnsAdminSection())),
    ];

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
                  const Text('System', style: TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final item = items[i];
                  return AdminMenuCard(
                    icon: item.icon, title: item.title, subtitle: item.subtitle,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: item.builder)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemMenuItem {
  final String title;
  final IconData icon;
  final String subtitle;
  final WidgetBuilder builder;
  _SystemMenuItem(this.title, this.icon, this.subtitle, this.builder);
}