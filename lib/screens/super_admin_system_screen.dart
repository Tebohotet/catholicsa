import 'package:flutter/material.dart';
import 'super_admin_panel_screen.dart';
import 'hymns_admin_section.dart';
import '../widgets/super_admin_menu_widgets.dart';
import '../services/firestore_service.dart';
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
      _SystemMenuItem('Churches', Icons.church_outlined, 'Hide every church from the public map at once while details get confirmed in person.', (ctx) => const AdminSectionHost(title: 'Churches', child: _ChurchesSection())),
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

/// A single, platform-wide "take it all down while I check it in
/// person" switch - meant for the specific moment real data is still
/// being collected church by church, not an everyday toggle. Turning
/// individual churches back on happens from each parish's own Admin
/// Panel, one at a time, once it's actually been confirmed.
class _ChurchesSection extends StatefulWidget {
  const _ChurchesSection();

  @override
  State<_ChurchesSection> createState() => _ChurchesSectionState();
}

class _ChurchesSectionState extends State<_ChurchesSection> {
  bool _working = false;
  String? _result;

  Future<void> _hideAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Hide every church?', style: TextStyle(fontFamily: appSerif, fontSize: 17)),
        content: const Text(
          'This takes every church, in every parish, off the public map and out of every "Churches in this Parish" list right now. '
          'Nothing is deleted - each one can be switched back on individually from its own parish\'s Admin Panel once you\'ve confirmed it in person.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hide All'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() { _working = true; _result = null; });
    try {
      final count = await FirestoreService().hideAllChurches();
      if (mounted) setState(() => _result = 'Done - $count church(es) hidden from the public.');
    } catch (e) {
      if (mounted) setState(() => _result = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Hides every church from the public map and parish pages all at once - for when churches are listed but not yet confirmed in person. Parishes themselves stay visible.',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: _working ? null : _hideAll,
            icon: _working
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.visibility_off_outlined),
            label: Text(_working ? 'Hiding...' : 'Hide All Churches From Public'),
          ),
          if (_result != null) ...[
            const SizedBox(height: 12),
            Text(_result!, style: const TextStyle(fontSize: 13)),
          ],
          const SizedBox(height: 20),
          const Text(
            'To bring a church back once it\'s confirmed: open that parish\'s Admin Panel, select the church, and switch "Visible on public map" back on.',
            style: TextStyle(fontSize: 12, color: Colors.black45, fontStyle: FontStyle.italic),
          ),
        ],
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