import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/firestore_service.dart';
import '../models/church.dart';
import '../models/parish.dart';

import '../theme/app_theme.dart';
import '../widgets/share_button.dart';
import '../widgets/async_section.dart';
import 'parish_detail_screen.dart';
import 'course_list_screen.dart';
import 'church_detail/map_popup.dart';
import 'church_detail/horarium_section.dart';
import 'church_detail/confessions_section.dart';
import 'church_detail/mass_intentions_section.dart';
import 'church_detail/marketplace_section.dart';
import 'church_detail/devotions_section.dart';
import 'church_detail/clergy_section.dart';
import 'church_detail/associations_section.dart';
import 'church_detail/photo_gallery.dart';
import 'church_detail/finances_section.dart';
import 'church_detail/comments_section.dart';
import 'church_detail/favourite_button.dart';
import 'church_detail/notices_section.dart';
import 'church_detail/song_book_dialog.dart';
import 'church_detail/prayers_dialog.dart';


IconData _buildingIcon(String type) {
  switch (type) {
    case 'Cathedral':
    case 'Basilica':
      return Icons.account_balance;
    case 'Convent':
    case 'Chapel':
      return Icons.home_work;
    default:
      return Icons.church;
  }
}

class ChurchDetailScreen extends StatefulWidget {
  final String parishId;
  final String churchId;
  final String? parishName;
  final String backLabel;
  const ChurchDetailScreen({super.key, required this.parishId, required this.churchId, this.parishName, this.backLabel = 'Home'});

  @override
  State<ChurchDetailScreen> createState() => _ChurchDetailScreenState();
}

class _ChurchDetailScreenState extends State<ChurchDetailScreen> {
  bool _previewPhotos = false;

  // Placeholder images purely to preview layout - real churches show clean
  // gradient/icon placeholders by default until an admin uploads real photos.
  static const _sampleBanner = 'https://picsum.photos/seed/catholicsa-banner/800/400';
  static const _sampleLogo = 'https://picsum.photos/seed/catholicsa-logo/200/200';
  static const _samplePhotos = [
    {'url': 'https://picsum.photos/seed/catholicsa-1/400/400', 'caption': 'Sunday Mass, Feast of St Jude', 'date': '20 Jul 2026', 'uploadedBy': 'Fr Jan Mostert OSFS', 'kind': 'image', 'isSample': 'true'},
    {'url': 'https://picsum.photos/seed/catholicsa-2/400/400', 'caption': 'Parish Feast Day procession', 'date': '15 Jun 2026', 'uploadedBy': 'Marilyn C.', 'kind': 'image', 'isSample': 'true'},
    {'url': 'https://picsum.photos/seed/catholicsa-3/400/400', 'caption': 'First Holy Communion', 'date': '10 May 2026', 'uploadedBy': 'Parish Office', 'kind': 'image', 'isSample': 'true'},
    {'url': 'https://picsum.photos/seed/catholicsa-1/400/400', 'caption': 'Adoration, Thursday evening', 'date': '18 Jul 2026', 'uploadedBy': 'Parish Office', 'kind': 'video', 'isSample': 'true'},
  ];

  @override
  Widget build(BuildContext context) {
    final parishId = widget.parishId;
    final churchId = widget.churchId;
    final service = FirestoreService();
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: FutureBuilder(
        future: Future.wait([service.getChurch(parishId, churchId), service.getParish(parishId)]),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: ${snap.error}')));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final church = snap.data![0] as Church;
          final parish = snap.data![1] as Parish;

          final phone = church.contactPhone.isNotEmpty ? church.contactPhone : parish.contactPhone;
          final email = church.contactEmail.isNotEmpty ? church.contactEmail : parish.contactEmail;
          final facebook = church.socialLinks['facebook'] ?? parish.socialLinks['facebook'];
          final whatsapp = church.socialLinks['whatsapp'] ?? parish.socialLinks['whatsapp'];

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SafeArea(
                  bottom: false,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    decoration: BoxDecoration(
                      gradient: _previewPhotos ? null : const LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [AppColors.stone, AppColors.stoneDark],
                      ),
                    ),
                    child: Stack(
                      children: [
                        if (_previewPhotos)
                          Positioned.fill(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(_sampleBanner, fit: BoxFit.cover),
                                Container(color: Colors.black.withValues(alpha: 0.35)),
                              ],
                            ),
                          )
                        else
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.topRight,
                              child: Icon(_buildingIcon(church.buildingType), size: 40, color: Colors.white.withValues(alpha: 0.12)),
                            ),
                          ),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 960),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                                      onPressed: () => Navigator.pop(context),
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(child: Text('Back to ${widget.backLabel}', style: const TextStyle(color: Colors.white70, fontSize: 12))),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 56, height: 56,
                                      decoration: BoxDecoration(
                                        color: AppColors.paperDark, shape: BoxShape.circle,
                                        border: Border.all(color: AppColors.brass, width: 2),
                                      ),
                                      child: ClipOval(
                                        child: _previewPhotos
                                            ? Image.network(_sampleLogo, fit: BoxFit.cover, width: 56, height: 56)
                                            : Icon(_buildingIcon(church.buildingType), color: AppColors.stone, size: 24),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          InkWell(
                                            onTap: () => _openParish(context, parish),
                                            child: Container(
                                              margin: const EdgeInsets.only(bottom: 6),
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(border: Border.all(color: Colors.white38), borderRadius: BorderRadius.circular(3)),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(parish.name.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 9, letterSpacing: 0.5)),
                                                  const SizedBox(width: 3),
                                                  const Icon(Icons.chevron_right, size: 11, color: Colors.white54),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Text(church.name, style: const TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white),
                                              maxLines: 2, overflow: TextOverflow.ellipsis),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(Icons.location_on, size: 12, color: Colors.white70),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: InkWell(
                                                  onTap: () => _showMapPopup(context, church),
                                                  child: Text(church.address,
                                                      style: const TextStyle(color: Colors.white70, fontSize: 12, decoration: TextDecoration.underline, decorationColor: Colors.white38),
                                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                                ),
                                              ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 10, runSpacing: 10,
                            children: [
                              FilledButton.icon(
                                style: FilledButton.styleFrom(backgroundColor: AppColors.brass, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11)),
                                onPressed: () => _openDirections(church),
                                icon: const Icon(Icons.directions, size: 17),
                                label: const Text('Get Directions'),
                              ),
                              if (phone.isNotEmpty)
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.ink, side: BorderSide(color: AppColors.ink.withValues(alpha: 0.3)), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11)),
                                  onPressed: () => launchUrl(Uri.parse('tel:$phone')),
                                  icon: const Icon(Icons.phone, size: 17),
                                  label: Text(phone),
                                ),
                              if (email.isNotEmpty)
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.ink, side: BorderSide(color: AppColors.ink.withValues(alpha: 0.3)), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11)),
                                  onPressed: () => launchUrl(Uri.parse('mailto:$email')),
                                  icon: const Icon(Icons.email_outlined, size: 17),
                                  label: const Text('Email'),
                                ),
                              if (whatsapp != null)
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.ink, side: BorderSide(color: AppColors.ink.withValues(alpha: 0.3)), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11)),
                                  onPressed: () => launchUrl(Uri.parse(whatsapp), mode: LaunchMode.externalApplication),
                                  icon: const Icon(Icons.chat, size: 17),
                                  label: const Text('WhatsApp'),
                                ),
                              if (facebook != null)
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.ink, side: BorderSide(color: AppColors.ink.withValues(alpha: 0.3)), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11)),
                                  onPressed: () => launchUrl(Uri.parse(facebook), mode: LaunchMode.externalApplication),
                                  icon: const Icon(Icons.facebook, size: 17),
                                  label: const Text('Facebook'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              FavouriteButton(churchId: church.id, parishId: parishId),
                              ShareButton(title: church.name, url: 'https://catholicsa.co.za/church/$parishId/${church.id}'),
                              IconButton(
                                tooltip: 'Show QR code',
                                icon: const Icon(Icons.qr_code_2, size: 20, color: AppColors.ink),
                                onPressed: () => _showQrDialog(context, parishId, church.id, church.name),
                              ),
                              NoticesBellButton(parishId: parishId, churchId: church.id),
                              IconButton(
                                tooltip: 'Song Book — look up by number',
                                icon: const Icon(Icons.music_note_outlined, size: 20, color: AppColors.ink),
                                onPressed: () => showDialog(
                                  context: context,
                                  builder: (dialogContext) => SongBookDialog(parishId: parishId, churchId: church.id),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Prayers',
                                icon: const Icon(Icons.auto_stories_outlined, size: 20, color: AppColors.ink),
                                onPressed: () => showDialog(
                                  context: context,
                                  builder: (dialogContext) => PrayersDialog(parishId: parishId, churchId: church.id),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Courses',
                                icon: const Icon(Icons.school_outlined, size: 20, color: AppColors.ink),
                                onPressed: () => Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => CourseListScreen(parishId: parishId, churchId: church.id, churchName: church.name),
                                )),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () => _showReportDialog(context, parishId, church.id),
                                icon: const Icon(Icons.flag_outlined, size: 15, color: Colors.black45),
                                label: const Text('Report incorrect info', style: TextStyle(fontSize: 11, color: Colors.black45)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          const SectionLabel(numeral: 'I', title: 'The Horarium — Mass Times'),
                          HorariumSection(parishId: parishId, churchId: churchId),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'II', title: 'Confessions'),
                          ConfessionsSection(parishId: parishId, churchId: churchId, churchName: church.name),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'III', title: 'Mass Intentions'),
                          MassIntentionsSection(parishId: parishId, churchId: churchId, churchName: church.name),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'IV', title: 'Devotions'),
                          DevotionsSection(parishId: parishId, churchId: churchId),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'V', title: 'Clergy'),
                          ClergySection(parishId: parishId),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'VI', title: 'Associations & Societies'),
                          AssociationsSection(parishId: parishId, churchId: churchId),

                          const SizedBox(height: 28),
                          const Row(
                            children: [
                              Expanded(child: SectionLabel(numeral: 'VII', title: 'Photos & Videos')),
                            ],
                          ),
                          AsyncSection<List<Map<String, dynamic>>>(
                            future: FirestoreService().getMedia(parishId, churchId, onlyApproved: true),
                            builder: (context, realMedia) {
                              if (realMedia.isNotEmpty) {
                                final items = realMedia.map((m) {
                                  final uploadedAt = (m['uploadedAt'] as Timestamp?)?.toDate();
                                  return {
                                    'url': m['url'] as String,
                                    'caption': m['caption'] as String? ?? '',
                                    'date': uploadedAt != null ? DateFormat('d MMM yyyy').format(uploadedAt) : '',
                                    'uploadedBy': m['uploadedByName'] as String? ?? 'Parish Office',
                                    'kind': m['kind'] as String? ?? 'image',
                                    'isSample': 'false',
                                  };
                                }).toList();
                                return GridView.count(
                                  crossAxisCount: 3,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  crossAxisSpacing: 8, mainAxisSpacing: 8,
                                  children: List.generate(items.length, (i) => PhotoTile(items: items, index: i)),
                                );
                              }
                              // Nothing real yet - offer the sample preview so the intended
                              // layout is still visible before any admin has uploaded anything.
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    color: AppColors.paperDark,
                                    child: Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            'No approved photos yet — preview with sample images to see the layout:',
                                            style: TextStyle(fontSize: 11, color: Colors.black54),
                                          ),
                                        ),
                                        Switch(
                                          value: _previewPhotos,
                                          activeThumbColor: AppColors.brass,
                                          onChanged: (v) => setState(() => _previewPhotos = v),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_previewPhotos)
                                    GridView.count(
                                      crossAxisCount: 3,
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      crossAxisSpacing: 8, mainAxisSpacing: 8,
                                      children: List.generate(_samplePhotos.length, (i) => PhotoTile(items: _samplePhotos, index: i)),
                                    )
                                  else
                                    const Text('Turn on the preview above to see how a photo/video grid would look.',
                                        style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic)),
                                ],
                              );
                            },
                          ),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'VIII', title: 'Finances'),
                          FinancesSection(parish: parish, churchId: churchId),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'IX', title: 'Comments'),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 28),
                            child: CommentsSection(parishId: parishId, churchId: churchId),
                          ),

                          const SectionLabel(numeral: 'X', title: 'Parochial Notice'),
                          NoticesSection(parishId: parishId, churchId: churchId),

                          const SizedBox(height: 28),
                          const SectionLabel(numeral: 'XI', title: 'Marketplace'),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 40),
                            child: MarketplaceSection(parishId: parishId, churchId: churchId),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openDirections(Church church) async {
    final url = 'https://www.google.com/maps/dir/?api=1&destination=${church.geopoint.latitude},${church.geopoint.longitude}';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _showMapPopup(BuildContext context, Church church) {
    showDialog(context: context, builder: (_) => MapPopupDialog(church: church));
  }

  void _openParish(BuildContext context, Parish parish) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ParishDetailScreen(parishId: parish.id),
    ));
  }
}


void _showQrDialog(BuildContext context, String parishId, String churchId, String name) {
  final url = 'https://catholicsa.co.za/church/$parishId/$churchId';
  final qrImageUrl = 'https://api.qrserver.com/v1/create-qr-code/?size=220x220&data=${Uri.encodeComponent(url)}';
  showDialog(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: AppColors.paper,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name, style: const TextStyle(fontFamily: appSerif, fontSize: 16), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Image.network(qrImageUrl, width: 200, height: 200),
            const SizedBox(height: 8),
            Text(url, style: const TextStyle(fontSize: 11, color: Colors.black54)),
            const SizedBox(height: 12),
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
          ],
        ),
      ),
    ),
  );
}

void _showReportDialog(BuildContext context, String parishId, String churchId) {
  final ctrl = TextEditingController();
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.paper,
      title: const Text('Report Incorrect Info', style: TextStyle(fontFamily: appSerif, fontSize: 16)),
      content: TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(hintText: "What looks wrong?")),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
          onPressed: () async {
            if (ctrl.text.trim().isEmpty) return;
            await FirestoreService().submitReport(parishId: parishId, churchId: churchId, text: ctrl.text.trim());
            if (dialogContext.mounted) {
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks — the parish office has been notified.')));
            }
          },
          child: const Text('Send'),
        ),
      ],
    ),
  );
}

/// Collapsed by default so this doesn't clutter the page - matches the
/// "Parochial Notices" section from the printed bulletin.