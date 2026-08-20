import 'package:flutter/material.dart';

IconData iconFor(String name) {
  switch (name) {
    case 'temple_buddhist':
      return Icons.temple_buddhist;
    case 'landscape':
      return Icons.landscape;
    case 'beach_access':
      return Icons.beach_access;
    case 'account_balance':
      return Icons.account_balance;
    case 'train':
      return Icons.train;
    case 'terrain':
      return Icons.terrain;
    case 'restaurant':
      return Icons.restaurant;
    case 'local_cafe':
      return Icons.local_cafe;
    case 'store':
      return Icons.store;
    case 'checkroom':
      return Icons.checkroom;
    case 'pedal_bike':
      return Icons.pedal_bike;
    case 'star':
      return Icons.star;
    case 'auto_awesome':
      return Icons.auto_awesome;
    default:
      return Icons.place;
  }
}

Color colorFromHex(String hex) {
  final cleaned = hex.replaceAll('#', '');
  return Color(int.parse('FF$cleaned', radix: 16));
}
