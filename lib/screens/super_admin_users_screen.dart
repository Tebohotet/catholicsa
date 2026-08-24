import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

/// Search by name or email, pull up a real profile, edit it inline, and
/// see every parish the user actually administers right now - not just
/// the one parish the old single-parish picker on the Roles screen let
/// you check at a time. Role grants/revokes themselves stay on the
/// existing Roles screen rather than being duplicated here, since that
/// flow is already built and audit-logged; this screen links to it
/// instead of reimplementing it.
class SuperAdminUsersScreen extends StatefulWidget {
  const SuperAdminUsersScreen({super.key});

  @override
  State<SuperAdminUsersScreen> createState() => _SuperAdminUsersScreenState();
}

class _SuperAdminUsersScreenState extends State<SuperAdminUsersScreen> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  bool _searched = false;
  String? _expandedUid;

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() { _searching = true; _searched = true; _expandedUid = null; });
    final results = await FirestoreService().searchUsers(q);
    if (mounted) setState(() { _results = results; _searching = false; });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

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
                  const Text('Users', style: TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Search by name or email - matches a partial name too, not just an exact address, so you can find a group of similarly-named users at once.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            decoration: const InputDecoration(labelText: 'Name or email', hintText: 'e.g. Domkopo or someone@gmail.com'),
                            onSubmitted: (_) => _search(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                          onPressed: _searching ? null : _search,
                          child: _searching
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Search'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_searched && !_searching && _results.isEmpty)
                      const Text('No users matched that search.', style: TextStyle(fontSize: 13, color: Colors.black54)),
                    ..._results.map((u) => _UserResultTile(
                      user: u,
                      expanded: _expandedUid == u['uid'],
                      onToggle: () => setState(() => _expandedUid = _expandedUid == u['uid'] ? null : u['uid']),
                    )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserResultTile extends StatefulWidget {
  final Map<String, dynamic> user;
  final bool expanded;
  final VoidCallback onToggle;
  const _UserResultTile({required this.user, required this.expanded, required this.onToggle});

  @override
  State<_UserResultTile> createState() => _UserResultTileState();
}

class _UserResultTileState extends State<_UserResultTile> {
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  bool _saving = false;
  Future<List<Map<String, dynamic>>>? _adminOfFuture;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.user['displayName'] ?? '');
    _phoneCtrl = TextEditingController(text: widget.user['phone'] ?? '');
  }

  @override
  void didUpdateWidget(covariant _UserResultTile old) {
    super.didUpdateWidget(old);
    if (widget.expanded && !old.expanded) {
      _adminOfFuture = FirestoreService().getParishesUserAdministers(widget.user['uid']);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _saving = true; });
    try {
      await FirestoreService().updateUserProfile(widget.user['uid'], {
        'displayName': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved.')));
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppColors.paperDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: u['photoUrl'] != null
                ? CircleAvatar(backgroundImage: NetworkImage(u['photoUrl']))
                : const CircleAvatar(child: Icon(Icons.person, size: 18)),
            title: Text(u['displayName'] ?? '(no name)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(u['email'] ?? '', style: const TextStyle(fontSize: 12)),
            trailing: Icon(widget.expanded ? Icons.expand_less : Icons.expand_more),
            onTap: widget.onToggle,
          ),
          if (widget.expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Display name')),
                  const SizedBox(height: 8),
                  TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Phone (optional)')),
                  const SizedBox(height: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save Profile'),
                  ),
                  const SizedBox(height: 16),
                  const Text('Admin Of', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.stone)),
                  const SizedBox(height: 4),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _adminOfFuture,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
                      final parishes = snap.data ?? [];
                      if (parishes.isEmpty) {
                        return const Text('Not an admin of any parish.', style: TextStyle(fontSize: 12, color: Colors.black45));
                      }
                      return Column(
                        children: parishes.map((p) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(children: [
                            const Icon(Icons.church, size: 14, color: AppColors.stone),
                            const SizedBox(width: 6),
                            Expanded(child: Text('${p['parishName']}', style: const TextStyle(fontSize: 12))),
                            Text('${p['role']}', style: const TextStyle(fontSize: 11, color: Colors.black45)),
                          ]),
                        )).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Roles (Super Admin, Developer, Designer, Auditor) are granted from the Roles screen, not here - search this same email there to change platform-level access.',
                    style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}