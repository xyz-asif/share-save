import 'package:flutter/material.dart';

class AnchorModel {
  final String id;
  final String name;
  final String? description;
  final int colorValue;
  final DateTime createdAt;
  int itemCount;

  AnchorModel({
    required this.id,
    required this.name,
    this.description,
    required this.colorValue,
    required this.createdAt,
    this.itemCount = 0,
  });

  Color get color => Color(colorValue);

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'color_value': colorValue,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory AnchorModel.fromMap(Map<String, dynamic> map) => AnchorModel(
    id: map['id'] as String,
    name: map['name'] as String,
    description: map['description'] as String?,
    colorValue: map['color_value'] as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    itemCount: map['item_count'] as int? ?? 0,
  );
}
