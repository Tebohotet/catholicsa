import 'package:flutter/material.dart';
import 'super_admin_panel_screen.dart';
import '../widgets/super_admin_menu_widgets.dart';
import '../theme/app_theme.dart';

class SuperAdminDesignerScreen extends StatelessWidget {
  const SuperAdminDesignerScreen({super.key});

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
                  const Text('Designer', style: TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AdminMenuCard(
                    icon: Icons.palette_outlined,
                    title: 'Design Tokens',
                    subtitle: 'Corner radius and accent colour for the app\'s default theme.',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminSectionHost(title: 'Design Tokens', child: DesignTokensSection()))),
                  ),
                  const SizedBox(height: 8),
                  AdminMenuCard(
                    icon: Icons.badge_outlined,
                    title: 'App Branding',
                    subtitle: 'App name and description shown throughout the app.',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminSectionHost(title: 'App Branding', child: BrandingSection()))),
                  ),
                  const SizedBox(height: 8),
                  AdminMenuCard(
                    icon: Icons.dashboard_customize_outlined,
                    title: 'Custom Pages',
                    subtitle: 'Server-driven pages assembled from blocks - no app update needed to publish one.',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminSectionHost(title: 'Custom Pages', child: CustomPagesSection()))),
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