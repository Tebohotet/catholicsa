import 'package:flutter/material.dart';
import 'super_admin_panel_screen.dart';
import 'super_admin_users_screen.dart';
import 'super_admin_system_screen.dart';
import 'super_admin_store_screen.dart';
import 'super_admin_development_screen.dart';
import 'super_admin_designer_screen.dart';
import '../widgets/super_admin_menu_widgets.dart';
import '../theme/app_theme.dart';

/// The real landing menu for Super Admin - five focused categories
/// instead of one long scroll through seventeen sections. Role
/// grants/revokes (the existing Super Admin - Roles screen) stay
/// reachable from here too, since granting a Super Admin/Developer role
/// is a distinct, highest-stakes action from everything else on this
/// hub.
class SuperAdminHubScreen extends StatelessWidget {
  const SuperAdminHubScreen({super.key});

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
                  const Text('Super Admin', style: TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AdminMenuCard(
                    icon: Icons.people_outline,
                    title: 'Users',
                    subtitle: 'Search any user, edit their profile, and see every parish they administer.',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuperAdminUsersScreen())),
                  ),
                  const SizedBox(height: 8),
                  AdminMenuCard(
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'Roles',
                    subtitle: 'Grant or revoke Super Admin, Developer, Designer, and Auditor access.',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuperAdminPanelScreen())),
                  ),
                  const SizedBox(height: 8),
                  AdminMenuCard(
                    icon: Icons.public,
                    title: 'System',
                    subtitle: 'Saints, Bible, Cross-References, Liturgical Readings, Feast Calendar.',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuperAdminSystemScreen())),
                  ),
                  const SizedBox(height: 8),
                  AdminMenuCard(
                    icon: Icons.storefront_outlined,
                    title: 'Store',
                    subtitle: 'Marketplace fee, item groups, deliveries, and payments.',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuperAdminStoreScreen())),
                  ),
                  const SizedBox(height: 8),
                  AdminMenuCard(
                    icon: Icons.code,
                    title: 'Development',
                    subtitle: 'Dev flags - features gated to Off, Preview, or Live.',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuperAdminDevelopmentScreen())),
                  ),
                  const SizedBox(height: 8),
                  AdminMenuCard(
                    icon: Icons.brush_outlined,
                    title: 'Designer',
                    subtitle: 'Design tokens, app branding, and custom pages.',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuperAdminDesignerScreen())),
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