import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import 'messaging/chat_screen.dart';

/// A user's own profile, opened by tapping them in the Users list - the
/// project owner's own framing: "when you click one... you will see all
/// the churches he has checked in at, increasing his streak... what
/// position do they have, what position they had before, which courses
/// have they done... even in comments you can trust this user is giving
/// the right information." Every section here reads data that's either
/// already public on `users/{uid}` (courses, XP, current roles via the
/// admins subcollection) or was deliberately made public by the person
/// themselves (check-in streak/churches - a summary, not an exact log;
/// favourite churches - only if they opted in). Nothing here required a
/// firestore.rules change - see church_checkin_service.dart and
/// community_search_service.dart's setFavouritesPublic for why.
class UserProfileScreen extends StatelessWidget {
  final String uid;
  const UserProfileScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final service = FirestoreService();
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: FutureBuilder(
          future: Future.wait([
            service.getUserDoc(uid),
            service.getParishesUserAdministers(uid),
            // Not getMyProducts - that one's only safe to call for your
            // OWN uid (see its own doc comment for the permission-denied
            // bug this fixes: it used to be called here for whichever
            // profile was open, which broke for anyone who isn't a
            // super admin viewing someone else's page).
            service.getApprovedProductsForSeller(uid),
            service.getUserCheckInSummary(uid),
          ]),
          builder: (context, snap) {
            if (snap.hasError) {
              // The success path below starts with its own back button
              // (it's part of the header Row, not the Scaffold) - without
              // repeating it here, hitting an error on this screen left
              // no way back except the OS back gesture/button.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
                  Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: ${snap.error}', textAlign: TextAlign.center)))),
                ],
              );
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());

            final user = snap.data![0] as Map<String, dynamic>?;
            final currentRoles = snap.data![1] as List<Map<String, dynamic>>;
            final products = snap.data![2] as List<Map<String, dynamic>>;
            final checkIns = snap.data![3] as Map<String, dynamic>;

            if (user == null) {
              return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('This user could not be found.')));
            }

            final roleHistory = List<Map<String, dynamic>>.from(
              (user['roleHistory'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? [],
            )..sort((a, b) {
              final at = a['at'];
              final bt = b['at'];
              if (at == null || bt == null) return 0;
              return bt.compareTo(at);
            });
            // "Previously" should only list roles not currently held, so
            // a long-serving admin's one "granted" entry years ago doesn't
            // show up a second time as its own "previous" line.
            final currentKeys = currentRoles.map((r) => '${r['parishId']}_${r['role']}').toSet();
            final priorRoles = roleHistory.where((h) => h['action'] == 'revoked' && !currentKeys.contains('${h['parishId']}_${h['role']}')).toList();

            final favouritesPublic = user['favouritesPublic'] == true;
            final favouriteChurches = List<Map<String, dynamic>>.from(
              (user['publicFavouriteChurches'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? [],
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
                      const SizedBox(width: 4),
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.paperDark,
                        backgroundImage: user['photoUrl'] != null ? NetworkImage(user['photoUrl']) : null,
                        child: user['photoUrl'] == null ? const Icon(Icons.person, size: 26, color: AppColors.stone) : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user['displayName'] ?? '(no name)', style: const TextStyle(fontFamily: appSerif, fontSize: 20)),
                            Text(user['email'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => ChatScreen(otherUid: uid, otherName: user['displayName'] ?? 'this user'),
                        )),
                        icon: const Icon(Icons.chat_bubble_outline, size: 16),
                        label: const Text('Message'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  _SectionHeading('Church Attendance'),
                  _StatRow(icon: Icons.local_fire_department, label: 'Current streak', value: '${checkIns['streak']} week${checkIns['streak'] == 1 ? '' : 's'}'),
                  _StatRow(icon: Icons.check_circle_outline, label: 'Total check-ins', value: '${checkIns['totalCheckIns']}'),
                  const SizedBox(height: 8),
                  if ((checkIns['churches'] as List).isEmpty)
                    const Text('No churches checked into yet.', style: TextStyle(fontSize: 12, color: Colors.black45))
                  else
                    ...(checkIns['churches'] as List<Map<String, dynamic>>).map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(children: [
                        const Icon(Icons.church, size: 14, color: AppColors.stone),
                        const SizedBox(width: 6),
                        Expanded(child: Text(c['churchName'] ?? '', style: const TextStyle(fontSize: 13))),
                        Text('${c['count']}x', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ]),
                    )),

                  const SizedBox(height: 24),
                  _SectionHeading('Roles'),
                  if (currentRoles.isEmpty)
                    const Text('Not currently an admin of any parish.', style: TextStyle(fontSize: 12, color: Colors.black45))
                  else
                    ...currentRoles.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(children: [
                        const Icon(Icons.verified_outlined, size: 14, color: AppColors.brass),
                        const SizedBox(width: 6),
                        Expanded(child: Text('${r['role']} — ${r['parishName']}', style: const TextStyle(fontSize: 13))),
                      ]),
                    )),
                  if (priorRoles.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('Previously:', style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic)),
                    ...priorRoles.map((r) {
                      final at = r['at'];
                      final dateStr = at != null ? DateFormat('MMM yyyy').format(at.toDate()) : '';
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('${r['role']} — ${r['parishName']} ($dateStr)', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      );
                    }),
                  ],

                  const SizedBox(height: 24),
                  _SectionHeading('Learning'),
                  _StatRow(icon: Icons.school_outlined, label: 'Courses completed', value: '${(user['coursesCompleted'] as num?)?.toInt() ?? 0}'),
                  _StatRow(icon: Icons.bolt_outlined, label: 'XP', value: '${(user['xp'] as num?)?.toInt() ?? 0}'),

                  if (products.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _SectionHeading('What they sell'),
                    ...products.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(children: [
                        const Icon(Icons.sell_outlined, size: 14, color: AppColors.stone),
                        const SizedBox(width: 6),
                        Expanded(child: Text(p['title'] ?? p['name'] ?? '(untitled listing)', style: const TextStyle(fontSize: 13))),
                      ]),
                    )),
                  ],

                  if (favouritesPublic && favouriteChurches.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _SectionHeading('Favourite Churches'),
                    ...favouriteChurches.map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(children: [
                        const Icon(Icons.favorite, size: 14, color: Colors.redAccent),
                        const SizedBox(width: 6),
                        Expanded(child: Text(c['churchName'] ?? '', style: const TextStyle(fontSize: 13))),
                      ]),
                    )),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String text;
  const _SectionHeading(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: const TextStyle(fontFamily: appSerif, fontSize: 15, color: AppColors.stone)),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.brass),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
