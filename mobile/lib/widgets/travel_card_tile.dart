import 'package:flutter/material.dart';
import '../models/models.dart';
import 'card_widgets.dart';

/// A card in a grid: the portrait card face, tappable.
class TravelCardTile extends StatelessWidget {
  final TravelCard card;
  final VoidCallback? onTap;
  const TravelCardTile({super.key, required this.card, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Center(child: CardFace(card: card)),
    );
  }
}
