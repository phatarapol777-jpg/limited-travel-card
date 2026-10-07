import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme.dart';
import '../utils/icon_map.dart';

class RarityBadge extends StatelessWidget {
  final String rarity;
  final bool large;
  const RarityBadge({super.key, required this.rarity, this.large = false});

  @override
  Widget build(BuildContext context) {
    final label = rarity == 'special' ? 'SPECIAL' : (rarity == 'rare' ? 'RARE' : 'NORMAL');
    final color = rarity == 'special' ? AppColors.gold : (rarity == 'rare' ? const Color(0xFF6FA8DC) : Colors.white70);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 10 : 6, vertical: large ? 4 : 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.8)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: large ? 11 : 8, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
    );
  }
}

/// The face of a collectible card (portrait 5:7): artwork when there is one, otherwise a coloured icon,
/// with the name, serial number and rarity on top.
class CardFace extends StatelessWidget {
  final TravelCard card;
  final bool large;
  const CardFace({super.key, required this.card, this.large = false});

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(card.colorHex);
    final special = card.rarity == 'special';
    final border = special ? AppColors.gold : (card.rarity == 'rare' ? const Color(0xFF6FA8DC) : Colors.white24);
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color, Color.lerp(color, Colors.black, 0.4)!]),
      ),
      child: Center(child: Icon(iconFor(card.icon), color: Colors.white.withValues(alpha: 0.85), size: large ? 96 : 34)),
    );
    final radius = BorderRadius.circular(large ? 20 : 14);
    return AspectRatio(
      aspectRatio: 5 / 7,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: border, width: special ? 2.5 : 1.5),
          boxShadow: [BoxShadow(color: (special ? AppColors.gold : color).withValues(alpha: 0.35), blurRadius: large ? 24 : 8, offset: const Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (card.imageUrl != null)
                Image.network(card.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback, loadingBuilder: (c, child, p) => p == null ? child : fallback)
              else
                fallback,
              // darken the bottom so the text stays readable on any artwork
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.center, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xCC000000)]),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(large ? 14 : 7),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        RarityBadge(rarity: card.rarity, large: large),
                        if (card.isLocked) Icon(Icons.lock, color: Colors.white, size: large ? 22 : 14),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          card.name,
                          maxLines: large ? 3 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: large ? 22 : 11, height: 1.15),
                        ),
                        if (card.serialLabel != null) ...[
                          SizedBox(height: large ? 4 : 1),
                          Text(card.serialLabel!, style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: large ? 15 : 9)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tilts its child in 3D following a finger drag or the mouse pointer, and settles back when released.
class TiltCard extends StatefulWidget {
  final Widget child;
  const TiltCard({super.key, required this.child});

  @override
  State<TiltCard> createState() => _TiltCardState();
}

class _TiltCardState extends State<TiltCard> {
  Offset _tilt = Offset.zero; // x: rotation around the vertical axis, y: around the horizontal one (radians)
  bool _active = false;

  void _update(Offset local, Size size) {
    final dx = (local.dx / size.width - 0.5) * 2; // -1..1
    final dy = (local.dy / size.height - 0.5) * 2;
    setState(() {
      _active = true;
      _tilt = Offset(dx.clamp(-1.0, 1.0) * 0.35, -dy.clamp(-1.0, 1.0) * 0.35);
    });
  }

  void _reset() => setState(() {
        _active = false;
        _tilt = Offset.zero;
      });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth.isFinite ? box.maxWidth : 300, box.maxHeight.isFinite ? box.maxHeight : 420);
      return MouseRegion(
        onHover: (e) => _update(e.localPosition, size),
        onExit: (_) => _reset(),
        child: GestureDetector(
          onPanStart: (d) => _update(d.localPosition, size),
          onPanUpdate: (d) => _update(d.localPosition, size),
          onPanEnd: (_) => _reset(),
          onPanCancel: _reset,
          child: TweenAnimationBuilder<Offset>(
            tween: Tween(begin: Offset.zero, end: _tilt),
            duration: Duration(milliseconds: _active ? 80 : 350),
            curve: Curves.easeOut,
            builder: (context, t, child) => Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateX(t.dy)
                ..rotateY(t.dx),
              child: child,
            ),
            child: widget.child,
          ),
        ),
      );
    });
  }
}
