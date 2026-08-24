import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'async_section.dart';

/// The kinds of form fields the generic builder knows how to render.
/// Deliberately small - covers what every admin section built so far has
/// actually needed (Devotions, Notices, Events, Courses, Songs, Prayers,
/// Associations all reduce to some mix of these). Add a new case here only
/// when a genuinely new input shape is needed, not per-collection.
enum AdminFieldType { text, multiline, dropdown, switchBool, stringList }

/// Describes one field in a manageable collection's form.
class AdminFieldSpec {
  final String key;
  final String label;
  final AdminFieldType type;
  final List<String>? options; // required for dropdown
  final String? hint;
  final bool required;
  final dynamic defaultValue;

  const AdminFieldSpec({
    required this.key,
    required this.label,
    this.type = AdminFieldType.text,
    this.options,
    this.hint,
    this.required = false,
    this.defaultValue,
  });
}

/// Describes an entire manageable collection: what its fields are, how to
/// summarise an item in a list, and the four operations that make it a
/// real admin UI rather than a static list. Everything collection-specific
/// lives in one of these - the widget below never changes per use case.
///
/// Whether this points at `saints` (global), `parishes/{id}/churches/{id}/
/// events` (church-scoped), or something three levels deep doesn't matter
/// to this spec at all - that scoping is entirely the caller's problem,
/// baked into the fetchAll/onAdd/onEdit/onDelete closures passed in.
class AdminCollectionSpec {
  final String title;
  final IconData icon;
  final List<AdminFieldSpec> fields;
  final String Function(Map<String, dynamic> item) titleBuilder;
  final String Function(Map<String, dynamic> item)? subtitleBuilder;
  final Future<List<Map<String, dynamic>>> Function() fetchAll;
  final Future<void> Function(Map<String, dynamic> data) onAdd;
  final Future<void> Function(String id, Map<String, dynamic> data) onEdit;
  final Future<void> Function(String id) onDelete;
  final String Function(Map<String, dynamic> item) idOf;

  const AdminCollectionSpec({
    required this.title,
    required this.icon,
    required this.fields,
    required this.titleBuilder,
    this.subtitleBuilder,
    required this.fetchAll,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.idOf,
  });
}

/// The actual reusable widget. Give it a spec, get a working list +
/// add/edit/delete UI. Nothing in here knows or cares what it's managing.
class GenericAdminCrudSection extends StatefulWidget {
  final AdminCollectionSpec spec;
  const GenericAdminCrudSection({super.key, required this.spec});

  @override
  State<GenericAdminCrudSection> createState() => _GenericAdminCrudSectionState();
}

class _GenericAdminCrudSectionState extends State<GenericAdminCrudSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.spec.fetchAll();
  }

  void _refresh() => setState(() { _future = widget.spec.fetchAll(); });

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    final values = <String, dynamic>{};
    for (final f in widget.spec.fields) {
      values[f.key] = existing?[f.key] ?? f.defaultValue ?? (f.type == AdminFieldType.switchBool ? false : '');
    }
    final controllers = <String, TextEditingController>{
      for (final f in widget.spec.fields)
        if (f.type == AdminFieldType.text || f.type == AdminFieldType.multiline)
          f.key: TextEditingController(text: values[f.key]?.toString() ?? '')
        else if (f.type == AdminFieldType.stringList)
          f.key: TextEditingController(text: (values[f.key] is List) ? (values[f.key] as List).join(', ') : ''),
    };

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.paper,
          title: Text(existing == null ? 'Add ${widget.spec.title}' : 'Edit ${widget.spec.title}', style: const TextStyle(fontFamily: appSerif, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.spec.fields.map((f) {
                switch (f.type) {
                  case AdminFieldType.text:
                  case AdminFieldType.stringList:
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: controllers[f.key],
                        decoration: InputDecoration(
                          labelText: f.label + (f.required ? ' *' : ''),
                          hintText: f.type == AdminFieldType.stringList ? (f.hint ?? 'Comma-separated') : f.hint,
                        ),
                      ),
                    );
                  case AdminFieldType.multiline:
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: controllers[f.key],
                        maxLines: 4,
                        decoration: InputDecoration(labelText: f.label + (f.required ? ' *' : ''), hintText: f.hint),
                      ),
                    );
                  case AdminFieldType.dropdown:
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DropdownButton<String>(
                        value: values[f.key]?.toString().isNotEmpty == true ? values[f.key] : f.options?.first,
                        isExpanded: true,
                        items: (f.options ?? []).map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                        onChanged: (v) => setDialogState(() => values[f.key] = v),
                      ),
                    );
                  case AdminFieldType.switchBool:
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: AppColors.brass,
                      title: Text(f.label, style: const TextStyle(fontSize: 13)),
                      value: values[f.key] == true,
                      onChanged: (v) => setDialogState(() => values[f.key] = v),
                    );
                }
              }).toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
              onPressed: () async {
                final result = <String, dynamic>{};
                for (final f in widget.spec.fields) {
                  if (f.type == AdminFieldType.stringList) {
                    final raw = controllers[f.key]!.text.trim();
                    result[f.key] = raw.isEmpty ? <String>[] : raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
                  } else if (f.type == AdminFieldType.text || f.type == AdminFieldType.multiline) {
                    result[f.key] = controllers[f.key]!.text.trim();
                  } else {
                    result[f.key] = values[f.key];
                  }
                }
                if (existing == null) {
                  await widget.spec.onAdd(result);
                } else {
                  await widget.spec.onEdit(widget.spec.idOf(existing), result);
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _refresh();
              },
              child: Text(existing == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
    for (final c in controllers.values) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AsyncSection<List<Map<String, dynamic>>>(
          future: _future,
          isEmpty: (l) => l.isEmpty,
          emptyMessage: 'Nothing here yet.',
          builder: (context, items) => Column(
            children: items.map((item) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(widget.spec.icon, size: 20, color: AppColors.brass),
              title: Text(widget.spec.titleBuilder(item)),
              subtitle: widget.spec.subtitleBuilder != null ? Text(widget.spec.subtitleBuilder!(item)) : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _openForm(existing: item)),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          backgroundColor: AppColors.paper,
                          title: Text('Delete ${widget.spec.title}?', style: const TextStyle(fontFamily: appSerif, fontSize: 17)),
                          content: Text(
                            '"${widget.spec.titleBuilder(item)}" will be permanently removed. This can\'t be undone.',
                            style: const TextStyle(fontSize: 13),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                              onPressed: () => Navigator.pop(dialogContext, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await widget.spec.onDelete(widget.spec.idOf(item));
                        _refresh();
                      }
                    },
                  ),
                ],
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
          onPressed: () => _openForm(),
          icon: const Icon(Icons.add, size: 16),
          label: Text('Add ${widget.spec.title}'),
        ),
      ],
    );
  }
}