import 'package:flutter/material.dart';

/// 合集图标键 -> const IconData 映射（避免动态 IconData 被 tree-shaking 移除）。
IconData collectionIcon(String key) {
  switch (key) {
    case 'favorite':
      return Icons.favorite;
    case 'star':
      return Icons.star;
    case 'bolt':
      return Icons.bolt;
    case 'nights_stay':
      return Icons.nights_stay;
    case 'local_movies':
      return Icons.local_movies;
    case 'theaters':
      return Icons.theaters;
    case 'whatshot':
      return Icons.whatshot;
    case 'mood':
      return Icons.mood;
    case 'auto_awesome':
      return Icons.auto_awesome;
    case 'public':
      return Icons.public;
    case 'collections':
    default:
      return Icons.collections_bookmark;
  }
}
