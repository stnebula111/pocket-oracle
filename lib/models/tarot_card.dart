class TarotCard {
  final int id;
  final String name;
  final String arcana;
  final String meaningUpright;
  final String meaningReversed;

  TarotCard({
    required this.id,
    required this.name,
    required this.arcana,
    required this.meaningUpright,
    required this.meaningReversed,
  });

  factory TarotCard.fromJson(Map<String, dynamic> json) {
    return TarotCard(
      // The ?? operator provides a fallback value if the JSON key is missing
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Unknown Card',
      arcana: json['suit'] ?? 'Unknown',
      meaningUpright: json['meaning_upright'] ?? 'No description available.',
      meaningReversed: json['meaning_reversed'] ?? 'No description available.',
    );
  }

  // UPDATE THIS LINE HERE:
  String get imagePath => "assets/images/card_$id.jpg";
}