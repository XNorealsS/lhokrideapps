import 'package:hive_flutter/hive_flutter.dart';
import 'package:lhokride/models/menu.dart'; // Sesuaikan path jika diperlukan

part 'partner.g.dart'; // Nama file ini harus sesuai dengan @HiveType(typeId: 0)

@HiveType(typeId: 0)
class Partner extends HiveObject {
  @HiveField(0)
  final int id;

  @HiveField(1)
  final String namaToko;

  @HiveField(2)
  final String deskripsi;

  @HiveField(3)
  final String alamat;

  @HiveField(4)
  final String noTelepon;

  @HiveField(5)
  final double latitude;

  @HiveField(6)
  final double longitude;

  @HiveField(7)
  final String hariBuka;

  @HiveField(8)
  final String jamBuka;

  @HiveField(9)
  final String jamTutup;

  @HiveField(10)
  final String fotoToko;

  @HiveField(11)
  final DateTime createdAt;

  @HiveField(12)
  final List<Menu> menu;

  Partner({
    required this.id,
    required this.namaToko,
    required this.deskripsi,
    required this.alamat,
    required this.noTelepon,
    required this.latitude,
    required this.longitude,
    required this.hariBuka,
    required this.jamBuka,
    required this.jamTutup,
    required this.fotoToko,
    required this.createdAt,
    this.menu = const [],
  });

  factory Partner.fromJson(Map<String, dynamic> json) {
    var menuList = <Menu>[];
    if (json['menu'] != null) {
      menuList =
          (json['menu'] as List).map((item) => Menu.fromJson(item)).toList();
    }

    return Partner(
      id: json['id'],
      namaToko: json['nama_toko'],
      deskripsi: json['deskripsi'],
      alamat: json['alamat'],
      noTelepon: json['no_telepon'],
      latitude: double.tryParse(json['latitude'].toString()) ?? 0.0,
      longitude: double.tryParse(json['longitude'].toString()) ?? 0.0,
      hariBuka: json['hari_buka'],
      jamBuka: json['jam_buka'],
      jamTutup: json['jam_tutup'],
      fotoToko: json['foto_toko'] ?? 'https://via.placeholder.com/150',
      createdAt: DateTime.parse(json['created_at']),
      menu: menuList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nama_toko': namaToko,
      'deskripsi': deskripsi,
      'alamat': alamat,
      'no_telepon': noTelepon,
      'latitude': latitude,
      'longitude': longitude,
      'hari_buka': hariBuka,
      'jam_buka': jamBuka,
      'jam_tutup': jamTutup,
      'foto_toko': fotoToko,
      'created_at': createdAt.toIso8601String(),
      'menu': menu.map((menu) => menu.toJson()).toList(),
    };
  }
}
