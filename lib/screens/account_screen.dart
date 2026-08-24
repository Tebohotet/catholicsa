import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/engagement_service.dart';
import '../providers/auth_provider.dart';
import '../providers/view_as_role_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/async_section.dart';
import '../models/church.dart';
import 'church_detail_screen.dart';
import 'settings_screen.dart';
import 'admin_panel_screen.dart';
import 'super_admin_hub_screen.dart';
import 'my_orders_screen.dart';
import 'my_sales_screen.dart';
import 'my_donations_screen.dart';
import 'my_listings_screen.dart';
import 'my_bible_bookmarks_screen.dart';
import 'hymns_screen.dart';
import 'server_driven_page_screen.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final viewAs = ref.watch(viewAsRoleProvider);
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: authState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Sign-in error: $err')),
        data: (user) {
          // Simulating Logged Out means genuinely logged out, for real -
          // not just an inner banner change while still showing the
          // real signed-in account underneath.
          final effectiveUser = viewAs == 'loggedOut' ? null : user;
          return SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  color: AppColors.stone,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: const Text('Account', style: TextStyle(fontFamily: appSerif, fontSize: 26, color: Colors.white)),
                ),
                Expanded(
                  child: effectiveUser == null
                      ? const _SignedOutView()
                      : _SignedInView(user: effectiveUser),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SignedOutView extends StatefulWidget {
  const _SignedOutView();

  @override
  State<_SignedOutView> createState() => _SignedOutViewState();
}

class _SignedOutViewState extends State<_SignedOutView> {
  bool _signingIn = false;
  bool _showEmailForm = false;
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  // The google_sign_in package genuinely has no Windows implementation -
  // confirmed directly from the Flutter team - so Windows routes Google
  // sign-in through AuthService.signInWithGoogleWindows() instead (see
  // _signInWithGoogle below). kIsWeb/defaultTargetPlatform are safe to
  // check on every platform (from foundation.dart, not dart:io), same
  // pattern already used for the hymn conversion feature.
  bool get _isWindowsDesktop => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _signingIn = true);
    try {
      // Windows has no google_sign_in implementation at all, so it goes
      // through the google_sign_in_all_platforms-backed path instead -
      // everywhere else keeps using the original.
      if (_isWindowsDesktop) {
        await AuthService().signInWithGoogleWindows();
      } else {
        await AuthService().signInWithGoogle();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _signInWithEmail() async {
    if (_emailCtrl.text.trim().isEmpty || _passwordCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter both email and password.')));
      return;
    }
    setState(() => _signingIn = true);
    try {
      await AuthService().signInWithEmailAndPassword(
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Sign-in failed [${e.code}]: ${e.message ?? 'no message provided'}'),
          duration: const Duration(seconds: 8),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    var email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      // Nothing typed yet - ask for the address directly rather than
      // just complaining the field is empty, since this link is often
      // the first thing tapped by someone who's forgotten everything.
      final entered = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          final ctrl = TextEditingController();
          return AlertDialog(
            backgroundColor: AppColors.paper,
            title: const Text('Reset Password', style: TextStyle(fontFamily: appSerif, fontSize: 17)),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                onPressed: () => Navigator.pop(dialogContext, ctrl.text.trim()),
                child: const Text('Send Reset Link'),
              ),
            ],
          );
        },
      );
      if (entered == null || entered.isEmpty) return;
      email = entered;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Password reset email sent to $email. Check your inbox.')),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not send reset email [${e.code}]: ${e.message ?? 'no message provided'}'),
          duration: const Duration(seconds: 8),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send reset email: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Both platforms now have a real Google Sign-In path (Windows via
    // google_sign_in_all_platforms), so which form shows first is just
    // _showEmailForm same as everywhere else - no more forcing Windows
    // into email-only.
    final useEmailAuth = _showEmailForm;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.church, size: 48, color: AppColors.stone),
            const SizedBox(height: 16),
            const Text('Sign in to CatholicSA', style: TextStyle(fontFamily: appSerif, fontSize: 20)),
            const SizedBox(height: 8),
            const Text(
              'Save favourite churches, leave comments, book confessions, and manage your parish if you\'re an admin.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            if (useEmailAuth) ...[
              SizedBox(
                width: 280,
                child: Column(
                  children: [
                    TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
                    const SizedBox(height: 10),
                    TextField(controller: _passwordCtrl, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _signingIn ? null : _sendPasswordReset,
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                        child: const Text('Forgot password?', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.brass, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
                      onPressed: _signingIn ? null : _signInWithEmail,
                      icon: _signingIn
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.login),
                      label: const Text('Sign In'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() => _showEmailForm = false),
                child: const Text('Use Google Sign-In instead'),
              ),
            ] else ...[
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.brass, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
                onPressed: _signingIn ? null : _signInWithGoogle,
                icon: _signingIn
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.login),
                label: const Text('Sign in with Google'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() => _showEmailForm = true),
                child: const Text('Use email and password instead'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SignedInView extends ConsumerWidget {
  final User user;
  const _SignedInView({required this.user});

  static const _knownParishId = 'st-jude-parish';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: CenteredContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.paperDark,
                backgroundImage: user.photoURL != null ? NetworkImage(user.photoURL!) : null,
                child: user.photoURL == null
                    ? Text((user.displayName ?? '?').substring(0, 1).toUpperCase(), style: const TextStyle(fontFamily: appSerif, fontSize: 20, color: AppColors.stone))
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.displayName ?? 'Signed in', style: const TextStyle(fontFamily: appSerif, fontSize: 18)),
                    Text(user.email ?? '', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _MyProgressCard(),
          const SizedBox(height: 24),

          FutureBuilder<bool>(
            future: AuthService().isAdminForParish(_knownParishId),
            builder: (context, snap) {
              final viewAs = ref.watch(viewAsRoleProvider);
              final isAdmin = viewAs != null
                  ? ['secretary', 'priest', 'superAdmin'].contains(viewAs)
                  : snap.data == true;
              if (!isAdmin) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(14),
                color: AppColors.paperDark,
                child: Row(
                  children: [
                    const Icon(Icons.admin_panel_settings_outlined, color: AppColors.sage),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('You\'re a parish admin for St Jude Parish.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                    TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const AdminPanelScreen(parishId: _knownParishId),
                      )),
                      child: const Text('Admin Panel'),
                    ),
                  ],
                ),
              );
            },
          ),

          FutureBuilder<Map<String, dynamic>?>(
            future: FirestoreService().getUserDoc(user.uid),
            builder: (context, snap) {
              final viewAs = ref.watch(viewAsRoleProvider);
              final isSuperAdmin = viewAs != null ? viewAs == 'superAdmin' : snap.data?['isSuperAdmin'] == true;
              if (!isSuperAdmin) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(14),
                color: AppColors.paperDark,
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: AppColors.brass),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('You\'re a super admin.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                    TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const SuperAdminHubScreen(),
                      )),
                      child: const Text('Super Admin'),
                    ),
                  ],
                ),
              );
            },
          ),

          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyOrdersScreen())),
            icon: const Icon(Icons.shopping_bag_outlined, size: 16),
            label: const Text('My Orders'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MySalesScreen())),
            icon: const Icon(Icons.storefront_outlined, size: 16),
            label: const Text('My Sales'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyListingsScreen())),
            icon: const Icon(Icons.sell_outlined, size: 16),
            label: const Text('My Listings'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyDonationsScreen())),
            icon: const Icon(Icons.volunteer_activism_outlined, size: 16),
            label: const Text('My Donations'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyBibleBookmarksScreen())),
            icon: const Icon(Icons.bookmark_outline, size: 16),
            label: const Text('My Bible Bookmarks'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HymnsScreen())),
            icon: const Icon(Icons.library_music_outlined, size: 16),
            label: const Text('Hymns'),
          ),
          const SizedBox(height: 20),

          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
            onPressed: () => showDialog(context: context, builder: (_) => const _CatechistApplicationDialog()),
            icon: const Icon(Icons.school_outlined, size: 16),
            label: const Text('Apply to be a Catechist'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
            onPressed: () => showDialog(context: context, builder: (_) => const _TrustedSellerApplicationDialog()),
            icon: const Icon(Icons.verified_outlined, size: 16),
            label: const Text('Apply to be a Trusted Seller'),
          ),
          const SizedBox(height: 10),

          FutureBuilder<List<Map<String, dynamic>>>(
            future: FirestoreService().getCustomPages(),
            builder: (context, snap) {
              final pages = (snap.data ?? []).where((p) => p['visible'] == true).toList();
              if (pages.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...pages.map((p) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.dashboard_customize_outlined, color: AppColors.brass, size: 20),
                        title: Text(p['title'] ?? ''),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => ServerDrivenPageScreen(pageId: p['id']),
                        )),
                      )),
                  const SizedBox(height: 10),
                ],
              );
            },
          ),

          const SectionLabel(numeral: 'I', title: 'My Favourites'),
          AsyncSection<List<Church>>(
            future: FirestoreService().getFavouriteChurches(),
            isEmpty: (list) => list.isEmpty,
            emptyMessage: 'No favourites yet — tap the heart on a church page to save it here.',
            builder: (context, churches) => Column(
              children: churches.map((c) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.favorite, color: Colors.redAccent, size: 20),
                title: Text(c.name),
                subtitle: Text(c.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ChurchDetailScreen(parishId: c.parishId, churchId: c.id),
                )),
              )).toList(),
            ),
          ),

          const SizedBox(height: 28),
          const SectionLabel(numeral: 'II', title: 'Account'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Sign out', style: TextStyle(color: Colors.redAccent)),
            onTap: () async {
              try {
                await AuthService().signOut();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign out failed: $e')));
                }
              }
            },
          ),
        ],
      ),
      ),
    );
  }
}

class _CatechistApplicationDialog extends StatefulWidget {
  const _CatechistApplicationDialog();

  @override
  State<_CatechistApplicationDialog> createState() => _CatechistApplicationDialogState();
}

class _CatechistApplicationDialogState extends State<_CatechistApplicationDialog> {
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  String _level = 'parish';
  final String _parishId = 'st-jude-parish';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final user = AuthService().currentUser;
    if (user != null) _nameCtrl.text = user.displayName ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty || _contactCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill in your name and contact number.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await FirestoreService().submitCatechistApplication(
        level: _level,
        parishId: _level == 'parish' ? _parishId : null,
        applicantName: _nameCtrl.text.trim(),
        applicantContact: _contactCtrl.text.trim(),
      );
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(const SnackBar(content: Text('Application submitted — you\'ll see a verified tick on your name once approved.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not submit: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.paper,
      title: const Text('Apply to be a Catechist', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Level', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          RadioGroup<String>(
            groupValue: _level,
            onChanged: (v) => setState(() => _level = v!),
            child: const Column(
              children: [
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'parish',
                  title: Text('This parish', style: TextStyle(fontSize: 13)),
                  subtitle: Text('Reviewed by that parish\'s priest', style: TextStyle(fontSize: 11)),
                ),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'national',
                  title: Text('Platform-wide', style: TextStyle(fontSize: 13)),
                  subtitle: Text('Reviewed by a Super Admin - usable at any parish', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Your name')),
          const SizedBox(height: 10),
          TextField(controller: _contactCtrl, decoration: const InputDecoration(labelText: 'Contact number'), keyboardType: TextInputType.phone),
        ],
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
          onPressed: _submitting ? null : _submit,
          child: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Submit'),
        ),
      ],
    );
  }
}

class _TrustedSellerApplicationDialog extends StatefulWidget {
  const _TrustedSellerApplicationDialog();

  @override
  State<_TrustedSellerApplicationDialog> createState() => _TrustedSellerApplicationDialogState();
}

class _TrustedSellerApplicationDialogState extends State<_TrustedSellerApplicationDialog> {
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final user = AuthService().currentUser;
    if (user != null) _nameCtrl.text = user.displayName ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty || _contactCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill in your name and contact number.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await FirestoreService().submitTrustedSellerApplication(
        applicantName: _nameCtrl.text.trim(), applicantContact: _contactCtrl.text.trim(),
      );
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(const SnackBar(content: Text('Application submitted — reviewed by a Super Admin.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not submit: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.paper,
      title: const Text('Apply to be a Trusted Seller', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Reviewed platform-wide by a Super Admin - shows a verified tick next to your name on any listing you sell.', style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 10),
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Your name')),
          const SizedBox(height: 10),
          TextField(controller: _contactCtrl, decoration: const InputDecoration(labelText: 'Contact number'), keyboardType: TextInputType.phone),
        ],
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
          onPressed: _submitting ? null : _submit,
          child: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Submit'),
        ),
      ],
    );
  }
}

/// Shows nothing at all if there's genuinely nothing to show yet (0 XP,
/// no streak) - an empty gamification card for a brand new account
/// looks like a bug, not encouragement.
class _MyProgressCard extends StatelessWidget {
  const _MyProgressCard();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: EngagementService().getMyStats(),
      builder: (context, snap) {
        final stats = snap.data;
        if (stats == null || (stats['xp'] ?? 0) == 0) return const SizedBox.shrink();
        final badges = List<String>.from(stats['badges'] ?? []);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          color: AppColors.paperDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StatChip(icon: Icons.star, label: '${stats['xp']} XP', color: AppColors.brass),
                  const SizedBox(width: 12),
                  if ((stats['streak'] ?? 0) > 0)
                    _StatChip(icon: Icons.local_fire_department, label: '${stats['streak']} day streak', color: Colors.deepOrange),
                ],
              ),
              if (badges.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: badges.map((b) => Chip(
                    label: Text(EngagementService.badgeName(b), style: const TextStyle(fontSize: 11)),
                    avatar: const Icon(Icons.emoji_events, size: 14, color: AppColors.brass),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.brass),
                  )).toList(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}