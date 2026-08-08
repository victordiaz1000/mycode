class Translation {
  final String id;
  final String name;
  final String language;
  final String source;
  final String? url;

  const Translation({
    required this.id,
    required this.name,
    required this.language,
    required this.source,
    this.url,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'language': language,
        'source': source,
        if (url != null) 'url': url,
      };

  static Translation fromJson(Map<String, dynamic> json) => Translation(
        id: json['id'] as String,
        name: json['name'] as String,
        language: json['language'] as String? ?? '',
        source: json['source'] as String? ?? 'getbible',
        url: json['url'] as String?,
      );
}
