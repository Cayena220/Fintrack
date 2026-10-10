import 'package:flutter/material.dart';

/// Icons are stored in the database by name so the same data renders on
/// every platform. Unknown names fall back to a generic icon.
const Map<String, IconData> appIcons = {
  'wallet': Icons.account_balance_wallet_outlined,
  'bank': Icons.account_balance_outlined,
  'card': Icons.credit_card,
  'phone': Icons.phone_android,
  'savings': Icons.savings_outlined,
  'restaurant': Icons.restaurant,
  'shopping_cart': Icons.shopping_cart_outlined,
  'directions_car': Icons.directions_car_outlined,
  'receipt': Icons.receipt_long_outlined,
  'home': Icons.home_outlined,
  'shopping_bag': Icons.shopping_bag_outlined,
  'medical': Icons.medical_services_outlined,
  'movie': Icons.movie_outlined,
  'school': Icons.school_outlined,
  'work': Icons.work_outline,
  'store': Icons.storefront_outlined,
  'gift': Icons.card_giftcard,
  'category': Icons.category_outlined,
  'coffee': Icons.local_cafe_outlined,
  'fuel': Icons.local_gas_station_outlined,
  'pets': Icons.pets,
  'fitness': Icons.fitness_center,
  'travel': Icons.flight_outlined,
  'phone_bill': Icons.wifi,
  'electricity': Icons.bolt,
  'water': Icons.water_drop_outlined,
  'baby': Icons.child_friendly_outlined,
  'insurance': Icons.shield_outlined,
  'investment': Icons.trending_up,
  'interest': Icons.percent,
  'subscription': Icons.subscriptions_outlined,
  'laptop': Icons.laptop,
  'beach': Icons.beach_access_outlined,
  'emergency': Icons.health_and_safety_outlined,
  'car': Icons.directions_car_filled_outlined,
  'house': Icons.house_outlined,
};

IconData iconFor(String name) => appIcons[name] ?? Icons.category_outlined;

/// ARGB colors offered in pickers (stored as ints in the database).
const List<int> appColors = [
  0xFF059669, 0xFF10B981, 0xFF0EA5E9, 0xFF2563EB, 0xFF4F46E5, 0xFF7C3AED,
  0xFFC026D3, 0xFFDB2777, 0xFFE11D48, 0xFFEA580C, 0xFFF59E0B, 0xFF65A30D,
  0xFF0D9488, 0xFF475569, 0xFF78716C, 0xFF9CA3AF,
];
