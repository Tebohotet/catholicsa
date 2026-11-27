import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/profile_menu_button.dart';
import 'admin_panel_screen.dart';

/// The project owner's own ask: "I want to see the parish, church, so
/// that I can turn them on, that the viewer will be able to see them on
/// the map, and it's times." Turning a parish/church on (the "Visible in
/// public Browse" / "Visible on public map" switches), Mass times,
/// Confession Bookings, and Mass Intention Requests already all exist in
/// the Admin Panel - but the only ways in were (a) browsing the full
/// Province -> Diocese -> Parish -> Church hierarchy to find the one you
/// want, or (b) the Account screen's "Admin Of" list, which only shows
/// parishes you're personally registered as admin of. The "Directory"
/// hub entry looked like it should be this, but it's deliberately scoped
/// to just Countries/Provinces (the very top of the hierarchy, see
/// super_admin_directory_screen.dart) - a dead end for anyone looking
/// for a specific parish or church. This screen is the direct path: pick
/// any parish, land straight in its Admin Panel.
class SuperAdminParishesScreen extends StatelessWidget {
  const SuperAdminParishesScreen({super.key});

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
                  const Text('Parishes & Churches', style: TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                  const Spacer(),
                  const ProfileMenuButton(embedded: true),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, String>>>(
                future: FirestoreService().getAllParishesFlat(),
                builder: (context, snap) {
                  if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final parishes = snap.data!;
                  if (parishes.isEmpty) {
                    return const Center(child: Text('No parishes yet.', style: TextStyle(color: Colors.black45)));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: parishes.length,
                    itemBuilder: (context, i) {
                      final p = parishes[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: AppColors.paperDark,
                        elevation: 0,
                        child: ListTile(
                          leading: const Icon(Icons.church, color: AppColors.brass),
                          title: Text(p['name'] ?? p['id'] ?? ''),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => AdminPanelScreen(parishId: p['id']!),
                          )),
                        ),
                      );
                    },
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
