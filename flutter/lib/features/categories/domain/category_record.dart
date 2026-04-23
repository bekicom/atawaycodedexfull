class CategoryRecord {
  const CategoryRecord({required this.id, required this.name});

  final String id;
  final String name;

  factory CategoryRecord.fromJson(Map<String, dynamic> json) {
    return CategoryRecord(
      id: json['_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }
}
