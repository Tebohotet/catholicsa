import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/hierarchy_summary_sections.dart';
import 'search_screen.dart';

/// Browses the marketplace across every parish, not just one church's
/// page. Reuses getNationalProducts() and ProductsSummarySection - the
/// same rollup already powering the national Marketplace section on the
/// Browse screen - rather than building a second version of the same
/// listing logic. Search (typed, scoped) is one tap away via the
/// existing SearchScreen, deep-linked straight to its Store tab.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getNationalProducts();
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Shop', style: TextStyle(fontFamily: appSerif, fontSize: 26, color: Colors.white)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search, color: Colors.white),
                    tooltip: 'Search the marketplace',
                    onPressed: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const SearchScreen(initialTab: 'products'),
                    )),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                'Listed for sale across parishes nationwide - tap Search to narrow it down.',
                style: TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CenteredContent(
                  child: SingleChildScrollView(
                    child: ProductsSummarySection(future: _future, tagKey: 'provinceName'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}