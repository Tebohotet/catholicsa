import 'package:flutter/material.dart';
import 'super_admin_panel_screen.dart';
import '../widgets/super_admin_menu_widgets.dart';
import '../theme/app_theme.dart';
import '../widgets/profile_menu_button.dart';

/// Countries and Provinces - the top of the whole administrative
/// hierarchy (every diocese, parish, and church sits under one of
/// these). Both sections already existed as real, working widgets
/// (CountryManagementSection, ProvinceManagementSection in
/// super_admin_panel_screen.dart) - they just had no home of their own
/// in the newer five-category hub, only reachable by scrolling all the
/// way down the old Roles screen. This screen gives them a focused home,
/// the same way System/Store/Designer already did for their sections.
class SuperAdminDirectoryScreen extends StatelessWidget {
  const SuperAdminDirectoryScreen({super.key});

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
                  const Text('Directory', style: TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                  const Spacer(),
                  const ProfileMenuButton(embedded: true),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AdminMenuCard(
                    icon: Icons.flag_outlined,
                    title: 'Countries',
                    subtitle: 'Added above provinces, ready for whenever this app expands beyond South Africa.',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminSectionHost(
                      title: 'Countries',
                      child: CountryManagementSection(),
                    ))),
                  ),
                  const SizedBox(height: 8),
                  AdminMenuCard(
                    icon: Icons.public,
                    title: 'Provinces',
                    subtitle: 'The top of the hierarchy every diocese, parish, and church sits under.',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminSectionHost(
                      title: 'Provinces',
                      // No sibling Create-Parish/Diocese section on this standalone
                      // page to tell about a change, unlike the old Roles screen -
                      // so this is a no-op rather than wiring up unrelated state.
                      child: ProvinceManagementSection(onProvinceChanged: () {}),
                    ))),
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
