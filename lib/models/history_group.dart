
class HistoryGroup {
  final String id;
  String name;
  final DateTime createdAt;

  HistoryGroup({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory HistoryGroup.fromJson(Map<String, dynamic> json) {
    return HistoryGroup(
      id: json['id'],
      name: json['name'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}
