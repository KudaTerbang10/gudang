import 'package:hive/hive.dart';

part 'product.g.dart';

@HiveType(typeId: 0)
class Product extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  int stock;

  @HiveField(3)
  final String location;

  @HiveField(4)
  final DateTime updatedAt;

  @HiveField(5)
  final bool isSynced;

  Product({
    required this.id,
    required this.name,
    required this.stock,
    required this.location,
    required this.updatedAt,
    required this.isSynced,
  });

  Product copyWith({
    String? id,
    String? name,
    int? stock,
    String? location,
    DateTime? updatedAt,
    bool? isSynced,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      stock: stock ?? this.stock,
      location: location ?? this.location,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'name': name,
      'stock': stock,
      'location': location,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['_id'] as String? ?? json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      stock: json['stock'] as int? ?? 0,
      location: json['location'] as String? ?? '',
      updatedAt: json['updatedAt'] is DateTime
          ? json['updatedAt'] as DateTime
          : DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      isSynced: true,
    );
  }

  @override
  String toString() =>
      'Product(id: $id, name: $name, stock: $stock, location: $location)';
}
