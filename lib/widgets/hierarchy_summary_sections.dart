import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../screens/course_detail_screen.dart';
import '../screens/product_detail_screen.dart';
import '../screens/church_detail/photo_gallery.dart';
import 'async_section.dart';

/// The "tag" is whatever label makes sense at that level - churchName at
/// Parish level, parishName at Diocese level, dioceseName at Province
/// level, provinceName at National level. Same widget, same rendering,
/// just told what to label each item with.
class NoticesSummarySection extends StatelessWidget {
  final Future<List<Map<String, dynamic>>> future;
  final String tagKey;
  const NoticesSummarySection({super.key, required this.future, required this.tagKey});

  @override
  Widget build(BuildContext context) {
    return AsyncSection<List<Map<String, dynamic>>>(
      future: future,
      isEmpty: (l) => l.isEmpty,
      emptyMessage: 'No notices posted anywhere here yet.',
      builder: (context, notices) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: notices.map((n) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(n['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                Pill(n[tagKey] ?? '', tone: 'outline'),
              ]),
              const SizedBox(height: 2),
              Text(n['body'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.black87)),
            ],
          ),
        )).toList(),
      ),
    );
  }
}

class PrayersSummarySection extends StatelessWidget {
  final Future<List<Map<String, dynamic>>> future;
  final String tagKey;
  const PrayersSummarySection({super.key, required this.future, required this.tagKey});

  @override
  Widget build(BuildContext context) {
    return AsyncSection<List<Map<String, dynamic>>>(
      future: future,
      isEmpty: (l) => l.isEmpty,
      emptyMessage: 'No prayers added anywhere here yet.',
      builder: (context, prayers) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: prayers.map((p) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(p['title'] ?? '', style: const TextStyle(fontFamily: appSerif, fontSize: 15))),
                Pill(p[tagKey] ?? '', tone: 'outline'),
              ]),
              Text(p['text'] ?? '', style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        )).toList(),
      ),
    );
  }
}

class CoursesSummarySection extends StatelessWidget {
  final Future<List<Map<String, dynamic>>> future;
  final String tagKey;
  const CoursesSummarySection({super.key, required this.future, required this.tagKey});

  @override
  Widget build(BuildContext context) {
    return AsyncSection<List<Map<String, dynamic>>>(
      future: future,
      isEmpty: (l) => l.isEmpty,
      emptyMessage: 'No published courses anywhere here yet.',
      builder: (context, courses) => Column(
        children: courses.map((c) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.school_outlined, size: 20, color: AppColors.stone),
          title: Text(c['title'] ?? ''),
          subtitle: Text('${c['catechistName'] ?? ''} · ${c[tagKey] ?? ''}'),
          trailing: const Icon(Icons.chevron_right, size: 18),
          // A course always carries its own parishId/churchId regardless of
          // how many levels up the aggregation started - so the tap target
          // is identical no matter which summary screen this is used from.
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => CourseDetailScreen(parishId: c['parishId'], churchId: c['churchId'], courseId: c['id']),
          )),
        )).toList(),
      ),
    );
  }
}

class GallerySummarySection extends StatelessWidget {
  final Future<List<Map<String, String>>> future;
  const GallerySummarySection({super.key, required this.future});

  @override
  Widget build(BuildContext context) {
    return AsyncSection<List<Map<String, String>>>(
      future: future,
      isEmpty: (l) => l.isEmpty,
      emptyMessage: 'No approved photos or videos anywhere here yet.',
      builder: (context, media) => GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 8, mainAxisSpacing: 8,
        children: List.generate(media.length, (i) => PhotoTile(items: media, index: i)),
      ),
    );
  }
}

/// Phase 1 marketplace: shows what's listed, and lets a buyer reach the
/// seller directly to sort out payment and delivery themselves. No payment
/// collection here at all - see the Shop feature design conversation for
/// why that's a deliberate boundary, not a missing feature.
class ProductsSummarySection extends StatelessWidget {
  final Future<List<Map<String, dynamic>>> future;
  final String tagKey;
  // Only needed when the caller is at parish level specifically -
  // getParishProducts doesn't add parishId to each product the way
  // getDioceseProducts/getProvinceProducts/getNationalProducts do one
  // level further up, since at parish level it would just be
  // duplicating something the caller already knows directly.
  final String? parishId;
  const ProductsSummarySection({super.key, required this.future, required this.tagKey, this.parishId});

  @override
  Widget build(BuildContext context) {
    return AsyncSection<List<Map<String, dynamic>>>(
      future: future,
      isEmpty: (l) => l.isEmpty,
      emptyMessage: 'Nothing listed for sale anywhere here yet.',
      builder: (context, products) => Column(
        children: products.map((p) => InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => ProductDetailScreen(parishId: parishId ?? p['parishId'] ?? '', churchId: p['churchId'] ?? '', product: p),
          )),
          child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          color: AppColors.paperDark,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p['imageUrl'] != null)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(p['imageUrl'], width: 56, height: 56, fit: BoxFit.cover),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: Text(p['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                      Pill(p[tagKey] ?? '', tone: 'outline'),
                    ]),
                    const SizedBox(height: 2),
                    Text('R${(p['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}', style: const TextStyle(fontSize: 13, color: AppColors.brass, fontWeight: FontWeight.w600)),
                    if ((p['description'] as String?)?.isNotEmpty ?? false)
                      Text(p['description'], style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text('Seller: ${p['sellerName'] ?? ''}', style: const TextStyle(fontSize: 11, color: Colors.black45)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                onPressed: () => launchUrl(Uri.parse('https://wa.me/${(p['sellerContact'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '')}'), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.chat_bubble_outline, size: 14),
                label: const Text('Contact', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          ),
        )).toList(),
      ),
    );
  }
}