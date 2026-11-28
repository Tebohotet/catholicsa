import 'package:flutter/material.dart';
import 'super_admin_panel_screen.dart';
import 'super_admin_users_screen.dart';
import 'super_admin_system_screen.dart';
import 'super_admin_store_screen.dart';
import 'super_admin_development_screen.dart';
import 'super_admin_designer_screen.dart';
import 'super_admin_directory_screen.dart';
import 'super_admin_parishes_screen.dart';
import 'logs_section.dart';
import '../widgets/super_admin_menu_widgets.dart';
import '../theme/app_theme.dart';
import '../widgets/profile_menu_button.dart';

/// The real landing menu for Super Admin - focused categories instead
/// of one long scroll through seventeen sections. Role grants/revokes
/// (the existing Super Admin - Roles screen) stay reachable from here
/// too, since granting a Super Admin/Developer role is a distinct,
/// highest-stakes action from everything else on this hub. Directory
/// and Audit Log were the last two sections still only reachable by
/// scrolling that old Roles screen rather than having a focused home of
/// their own - added here for the same reason System/Store/Designer
/// already had one.
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
                  const SizedBox(height: 8),
                  AdminMenuCard(
                    icon: Icons.map_outlined,
                    title: 'Directory',
                    subtitle: 'Countries and Provinces - the top of the administrative hierarchy.',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuperAdminDirectoryScreen())),
                  ),
                  const SizedBox(height: 8),
                  AdminMenuCard(
                    icon: Icons.church,
                    title: 'Parishes & Churches',
                    subtitle: 'Jump straight into any parish\'s Admin Panel - turn a parish/church on for public Browse/Map, Mass times, Confession Bookings, Mass Intentions.',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuperAdminParishesScreen())),
                  ),
                  const SizedBox(height: 8),
                  AdminMenuCard(
                    icon: Icons.history,
                    title: 'Audit Log',
                    subtitle: 'Read-only record of every Super Admin / Developer / Designer / Auditor role grant and revoke.',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminSectionHost(
                      title: 'Audit Log',
                      child: AuditLogSection(),
                    ))),
                  ),
                  const SizedBox(height: 8),
                  AdminMenuCard(
                    icon: Icons.bug_report_outlined,
                    title: 'Logs',
                    subtitle: 'Every crash and error the app itself caught, signed in or not - the project owner\'s own "just go to the logs and see if all went well" ask.',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminSectionHost(
                      title: 'Logs',
                      child: LogsSection(),
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