import 'package:flutter/material.dart';
import 'super_admin_panel_screen.dart';
import '../widgets/super_admin_menu_widgets.dart';
import '../theme/app_theme.dart';

class SuperAdminDevelopmentScreen extends StatelessWidget {
  const SuperAdminDevelopmentScreen({super.key});

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
                  const Text('Development', style: TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AdminMenuCard(
                    icon: Icons.flag_outlined,
                    title: 'Dev Flags',
                    subtitle: 'Off / Preview / Live gating for features not ready for everyone yet.',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminSectionHost(title: 'Dev Flags', child: DevFlagsSection()))),
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