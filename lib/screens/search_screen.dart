import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import 'church_detail_screen.dart';
import 'course_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  /// Optional - when search is opened from within a specific parish (e.g.
  /// a "Search this parish" icon on ParishDetailScreen), passing these
  /// lets the scope default to "just here" instead of nationwide. Both
  /// null means the only option is national (opened from Browse).
  final String? scopeParishId;
  final String? scopeParishName;
  final String initialTab;
  const SearchScreen({super.key, this.scopeParishId, this.scopeParishName, this.initialTab = 'churches'});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _queryCtrl = TextEditingController();
  final _minPriceCtrl = TextEditingController();
  final _maxPriceCtrl = TextEditingController();
  late String _tab; // churches | courses | products
  late SearchScope _scope;
  bool _loading = false;
  bool _showFilters = false;
  double _minRating = 0;
  String? _fulfillmentFilter; // null | 'pickup' | 'courier'
  List<Map<String, dynamic>> _results = [];
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _scope = widget.scopeParishId != null ? SearchScope.parish : SearchScope.national;
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    _minPriceCtrl.dispose();
    _maxPriceCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _queryCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() { _loading = true; _searched = true; });
    final scopeId = _scope == SearchScope.parish ? widget.scopeParishId : null;
    List<Map<String, dynamic>> results;
    switch (_tab) {
      case 'courses':
        results = await FirestoreService().searchCourses(
          q, scope: _scope, scopeId: scopeId,
          minRating: _minRating > 0 ? _minRating : null,
        );
        break;
      case 'products':
        results = await FirestoreService().searchProducts(
          q, scope: _scope, scopeId: scopeId,
          minPrice: double.tryParse(_minPriceCtrl.text.trim()),
          maxPrice: double.tryParse(_maxPriceCtrl.text.trim()),
          fulfillmentMethod: _fulfillmentFilter,
        );
        break;
      default:
        results = await FirestoreService().searchChurches(q, scope: _scope, scopeId: scopeId);
    }
    if (mounted) setState(() { _results = results; _loading = false; });
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(padding: EdgeInsets.zero, icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                      const Text('Search', style: TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _queryCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.1),
                      suffixIcon: IconButton(icon: const Icon(Icons.search, color: Colors.white), onPressed: _search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ],
              ),
            ),

            if (widget.scopeParishId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    const Text('Where:', style: TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('Just ${widget.scopeParishName ?? "here"}', style: const TextStyle(fontSize: 12)),
                      selected: _scope == SearchScope.parish,
                      selectedColor: AppColors.brass,
                      onSelected: (_) => setState(() => _scope = SearchScope.parish),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('Everywhere', style: TextStyle(fontSize: 12)),
                      selected: _scope == SearchScope.national,
                      selectedColor: AppColors.brass,
                      onSelected: (_) => setState(() => _scope = SearchScope.national),
                    ),
                  ],
                ),
              ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Churches', style: TextStyle(fontSize: 12)),
                    selected: _tab == 'churches',
                    selectedColor: AppColors.brass,
                    onSelected: (_) { setState(() { _tab = 'churches'; _searched = false; }); },
                  ),
                  ChoiceChip(
                    label: const Text('Courses', style: TextStyle(fontSize: 12)),
                    selected: _tab == 'courses',
                    selectedColor: AppColors.brass,
                    onSelected: (_) { setState(() { _tab = 'courses'; _searched = false; }); },
                  ),
                  ChoiceChip(
                    label: const Text('Store', style: TextStyle(fontSize: 12)),
                    selected: _tab == 'products',
                    selectedColor: AppColors.brass,
                    onSelected: (_) { setState(() { _tab = 'products'; _searched = false; }); },
                  ),
                  if (_tab != 'churches')
                    ActionChip(
                      label: Text(_showFilters ? 'Hide Filters' : 'Filters', style: const TextStyle(fontSize: 12)),
                      avatar: const Icon(Icons.tune, size: 14),
                      onPressed: () => setState(() => _showFilters = !_showFilters),
                    ),
                ],
              ),
            ),

            if (_showFilters && _tab == 'products')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: TextField(controller: _minPriceCtrl, decoration: const InputDecoration(labelText: 'Min price', prefixText: 'R '), keyboardType: TextInputType.number)),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: _maxPriceCtrl, decoration: const InputDecoration(labelText: 'Max price', prefixText: 'R '), keyboardType: TextInputType.number)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      ChoiceChip(label: const Text('Any delivery', style: TextStyle(fontSize: 12)), selected: _fulfillmentFilter == null, onSelected: (_) => setState(() => _fulfillmentFilter = null)),
                      ChoiceChip(label: const Text('Pickup', style: TextStyle(fontSize: 12)), selected: _fulfillmentFilter == 'pickup', onSelected: (_) => setState(() => _fulfillmentFilter = 'pickup')),
                      ChoiceChip(label: const Text('Courier', style: TextStyle(fontSize: 12)), selected: _fulfillmentFilter == 'courier', onSelected: (_) => setState(() => _fulfillmentFilter = 'courier')),
                    ]),
                    const SizedBox(height: 8),
                  ],
                ),
              ),

            if (_showFilters && _tab == 'courses')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Minimum rating: ${_minRating == 0 ? "Any" : _minRating.toStringAsFixed(1)}', style: const TextStyle(fontSize: 12)),
                    Slider(value: _minRating, min: 0, max: 5, divisions: 10, activeColor: AppColors.brass, onChanged: (v) => setState(() => _minRating = v)),
                  ],
                ),
              ),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : !_searched
                      ? const Center(child: Text('Type something and search.', style: TextStyle(color: Colors.black45)))
                      : _results.isEmpty
                          ? const Center(child: Text('No results.', style: TextStyle(color: Colors.black45)))
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _results.length,
                              itemBuilder: (context, i) {
                                final r = _results[i];
                                return _resultTile(context, r);
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultTile(BuildContext context, Map<String, dynamic> r) {
    if (_tab == 'churches') {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: AppColors.paperDark,
        elevation: 0,
        child: ListTile(
          leading: const Icon(Icons.church, color: AppColors.brass),
          title: Text(r['name'] ?? ''),
          subtitle: Text(r['address'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => ChurchDetailScreen(parishId: r['parishId'], churchId: r['id']),
          )),
        ),
      );
    }
    if (_tab == 'courses') {
      final rating = r['averageRating'] as double?;
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: AppColors.paperDark,
        elevation: 0,
        child: ListTile(
          leading: const Icon(Icons.school_outlined, color: AppColors.brass),
          title: Text(r['title'] ?? ''),
          subtitle: Text(r['catechistName'] ?? ''),
          trailing: rating != null
              ? Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.star, size: 14, color: AppColors.brass), const SizedBox(width: 2), Text(rating.toStringAsFixed(1), style: const TextStyle(fontSize: 12))])
              : null,
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => CourseDetailScreen(parishId: r['parishId'], churchId: r['churchId'], courseId: r['id']),
          )),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppColors.paperDark,
      elevation: 0,
      child: ListTile(
        leading: r['imageUrl'] != null
            ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(r['imageUrl'], width: 40, height: 40, fit: BoxFit.cover))
            : const Icon(Icons.shopping_bag_outlined, color: AppColors.brass),
        title: Text(r['title'] ?? ''),
        subtitle: Text('R${(r['price'] as num?)?.toStringAsFixed(2) ?? '0.00'} · ${r['sellerName'] ?? ''}'),
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => ChurchDetailScreen(parishId: r['parishId'], churchId: r['churchId']),
        )),
      ),
    );
  }
}