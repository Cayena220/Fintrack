import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Icons are stored in the database by name so the same data renders on
/// every platform. Unknown names fall back to a generic icon. The glyphs are
/// Material Symbols Rounded; the keys and their order never change.
const Map<String, IconData> appIcons = {
  'wallet': Symbols.account_balance_wallet_rounded,
  'bank': Symbols.account_balance_rounded,
  'card': Symbols.credit_card_rounded,
  'phone': Symbols.smartphone_rounded,
  'savings': Symbols.savings_rounded,
  'restaurant': Symbols.restaurant_rounded,
  'shopping_cart': Symbols.shopping_cart_rounded,
  'directions_car': Symbols.directions_car_rounded,
  'receipt': Symbols.receipt_long_rounded,
  'home': Symbols.home_rounded,
  'shopping_bag': Symbols.shopping_bag_rounded,
  'medical': Symbols.medical_services_rounded,
  'movie': Symbols.movie_rounded,
  'school': Symbols.school_rounded,
  'work': Symbols.work_rounded,
  'store': Symbols.storefront_rounded,
  'gift': Symbols.card_giftcard_rounded,
  'category': Symbols.category_rounded,
  'coffee': Symbols.local_cafe_rounded,
  'fuel': Symbols.local_gas_station_rounded,
  'pets': Symbols.pets_rounded,
  'fitness': Symbols.fitness_center_rounded,
  'travel': Symbols.flight_rounded,
  'phone_bill': Symbols.wifi_rounded,
  'electricity': Symbols.bolt_rounded,
  'water': Symbols.water_drop_rounded,
  'baby': Symbols.child_friendly_rounded,
  'insurance': Symbols.shield_rounded,
  'investment': Symbols.trending_up_rounded,
  'interest': Symbols.percent_rounded,
  'subscription': Symbols.subscriptions_rounded,
  'laptop': Symbols.laptop_rounded,
  'beach': Symbols.beach_access_rounded,
  'emergency': Symbols.health_and_safety_rounded,
  'car': Symbols.directions_car_rounded,
  'house': Symbols.house_rounded,
};

IconData iconFor(String name) => appIcons[name] ?? Symbols.category_rounded;

/// ARGB colors offered in pickers (stored as ints in the database).
const List<int> appColors = [
  0xFF059669, 0xFF10B981, 0xFF0EA5E9, 0xFF2563EB, 0xFF4F46E5, 0xFF7C3AED,
  0xFFC026D3, 0xFFDB2777, 0xFFE11D48, 0xFFEA580C, 0xFFF59E0B, 0xFF65A30D,
  0xFF0D9488, 0xFF475569, 0xFF78716C, 0xFF9CA3AF,
];
