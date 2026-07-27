import 'package:flutter/material.dart';

/// 个人标签，多对多挂到电影上。
class MovieTag {
  final String id;
  final String name;

  /// 颜色，存为 ARGB int。
  final int colorValue;

  final DateTime createdAt;

  MovieTag({
    required this.id,
    required this.name,
    required this.colorValue,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Color get color => Color(colorValue);

  /// 标签可选调色板。
  static const List<int> palette = [
    0xFFE94560, // accent red
    0xFFFF8C42, // orange
    0xFFFCC419, // yellow
    0xFF51CF66, // green
    0xFF22B8CF, // cyan
    0xFF4DABF7, // blue
    0xFF845EF7, // purple
    0xFFF06595, // pink
  ];

  MovieTag copyWith({
    String? id,
    String? name,
    int? colorValue,
    DateTime? createdAt,
  }) {
    return MovieTag(
      id: id ?? this.id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'colorValue': colorValue,
    'createdAt': createdAt.toIso8601String(),
  };

  factory MovieTag.fromJson(Map<String, dynamic> json) => MovieTag(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    colorValue: json['colorValue'] is num
        ? (json['colorValue'] as num).toInt()
        : MovieTag.palette.first,
    createdAt: json['createdAt'] != null
        ? DateTime.parse(json['createdAt'])
        : DateTime.now(),
  );
}
