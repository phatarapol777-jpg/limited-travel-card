import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../theme.dart';

class HotelDetailScreen extends StatefulWidget {
  final HotelOffer offer;
  const HotelDetailScreen({super.key, required this.offer});

  @override
  State<HotelDetailScreen> createState() => _HotelDetailScreenState();
}

class _HotelDetailScreenState extends State<HotelDetailScreen> {
  final _nameCtrl = TextEditingController();
  bool _requesting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _openInBooking() async {
    final url = widget.offer.bookingUrl;
    if (url == null) return;
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('เปิดลิงก์ไม่สำเร็จ')));
    }
  }

  Future<void> _confirmRequest() async {
    setState(() => _requesting = true);
    try {
      await apiClient.post('/booking/request', {
        'offer_id': widget.offer.offerId,
        'guest_name': _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ส่งคำขอจอง "${widget.offer.hotelName}" สำเร็จ')));
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: offer.largePhotoUrl != null
                  ? Image.network(
                      offer.largePhotoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, st) => Container(color: AppColors.navy, child: const Icon(Icons.hotel, color: Colors.white54, size: 64)),
                    )
                  : Container(color: AppColors.navy, child: const Icon(Icons.hotel, color: Colors.white54, size: 64)),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(offer.hotelName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  if (offer.starClass != null && offer.starClass! > 0) ...[
                    Row(
                      children: List.generate(offer.starClass!, (_) => const Icon(Icons.star, size: 16, color: Colors.amber)),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (offer.address != null) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on, size: 18, color: AppColors.navy),
                        const SizedBox(width: 6),
                        Expanded(child: Text(offer.address!, style: const TextStyle(color: Colors.black87))),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (offer.distanceToCenter != null)
                    Row(
                      children: [
                        const Icon(Icons.directions_walk, size: 18, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text('ห่างจากใจกลางเมือง ${offer.distanceToCenter}', style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  const SizedBox(height: 16),
                  if (offer.reviewScore != null)
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(8)),
                          child: Text(offer.reviewScore!.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 10),
                        if (offer.reviewScoreWord != null) Text(offer.reviewScoreWord!, style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (offer.reviewCount != null) Text(' (${offer.reviewCount} รีวิว)', style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        offer.priceAmount != null ? offer.priceAmount!.toStringAsFixed(0) : 'ราคาไม่ระบุ',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 28, color: AppColors.navy),
                      ),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(offer.priceCurrency ?? '', style: const TextStyle(color: Colors.grey)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('ราคารวมต่อการเข้าพัก (โดยประมาณ)', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 20),
                  TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'ชื่อผู้เข้าพัก', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: _requesting
                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check),
                    label: const Text('ยืนยันคำขอจอง'),
                    onPressed: _requesting ? null : _confirmRequest,
                  ),
                  if (offer.bookingUrl != null) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('ดูรายละเอียดเต็มใน Booking.com'),
                      onPressed: _openInBooking,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
