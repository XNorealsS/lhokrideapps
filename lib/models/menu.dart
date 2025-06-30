import 'package:hive/hive.dart';

part 'menu.g.dart'; // Generated file dari Hive

@HiveType(typeId: 1)
class Menu extends HiveObject {
  @HiveField(0)
  final int id;

  @HiveField(1)
  final int partnerId;

  @HiveField(2)
  final String name;

  @HiveField(3)
  final String description;

  @HiveField(4)
  final double price;

  @HiveField(5)
  final String category;

  @HiveField(6)
  final String image;

  Menu({
    required this.id,
    required this.partnerId,
    required this.name,
    required this.description,
    required this.price,
    required this.category,
    required this.image,
  });

  factory Menu.fromJson(Map<String, dynamic> json) {
    return Menu(
      id: json['id'],
      partnerId: json['mitra_toko_id'],
      name: json['nama_menu'],
      description: json['deskripsi'],
      price: double.tryParse(json['harga'].toString()) ?? 0.0,
      category: json['kategori'],
      image: json['foto_menu'] ?? 'https://via.placeholder.com/150', 
    );
  }


  // ✅ Tambahkan metode toJson() di sini
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mitra_toko_id': partnerId,
      'nama_menu': name,
      'deskripsi': description,
      'harga': price,
      'kategori': category,
      'foto_menu': image,
    };
  }
}