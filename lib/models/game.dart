class Game {
  final String id;
  final String title;
  final String coverUrl;
  final String size;
  final String? originalSize;
  final String? repackSize;
  final String? companies;
  final String? languages;
  final String? genre;
  final String? timeAgo;
  final String? version;
  final String? uploadDate; // Added this line

  final String? description;
  final String? magnetLink;
  final String? torrentUrl;
  final Map<String, String> mirrors;
  final List<String> screenshots;
  final String url;
  final List<String> tags;

  Game({
    required this.id,
    required this.title,
    required this.url,
    required this.coverUrl,
    required this.size,
    this.originalSize,
    this.repackSize,
    this.companies,
    this.languages,
    this.genre,
    this.timeAgo,
    this.version,
    this.uploadDate, // Added this line
    this.tags = const [],
    this.description,
    this.magnetLink,
    this.torrentUrl,
    this.mirrors = const {},
    this.screenshots = const [],
  });

  // CopyWith method
  Game copyWith({
    String? id,
    String? title,
    String? url,
    String? coverUrl,
    String? size,
    String? originalSize,
    String? repackSize,
    String? companies,
    String? languages,
    String? genre,
    String? timeAgo,
    String? version,
    String? uploadDate,
    String? description,
    String? magnetLink,
    String? torrentUrl,
    Map<String, String>? mirrors,
    List<String>? screenshots,
    List<String>? tags,
  }) {
    return Game(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      coverUrl: coverUrl ?? this.coverUrl,
      size: size ?? this.size,
      originalSize: originalSize ?? this.originalSize,
      repackSize: repackSize ?? this.repackSize,
      companies: companies ?? this.companies,
      languages: languages ?? this.languages,
      genre: genre ?? this.genre,
      timeAgo: timeAgo ?? this.timeAgo,
      version: version ?? this.version,
      uploadDate: uploadDate ?? this.uploadDate,
      description: description ?? this.description,
      magnetLink: magnetLink ?? this.magnetLink,
      torrentUrl: torrentUrl ?? this.torrentUrl,
      mirrors: mirrors ?? this.mirrors,
      screenshots: screenshots ?? this.screenshots,
    );
  }

  // To JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'url': url,
      'coverUrl': coverUrl,
      'size': size,
      'originalSize': originalSize,
      'repackSize': repackSize,
      'companies': companies,
      'languages': languages,
      'genre': genre,
      'timeAgo': timeAgo,
      'version': version,
      'uploadDate': uploadDate,
      'description': description,
      'magnetLink': magnetLink,
      'torrentUrl': torrentUrl,
      'mirrors': mirrors,
      'screenshots': screenshots,
      'tags': tags,
    };
  }

  // From JSON
  factory Game.fromJson(Map<String, dynamic> json) {
    return Game(
      id: json['id'],
      title: json['title'],
      url: json['url'],
      coverUrl: json['coverUrl'],
      size: json['size'],
      originalSize: json['originalSize'],
      repackSize: json['repackSize'],
      companies: json['companies'],
      languages: json['languages'],
      genre: json['genre'],
      timeAgo: json['timeAgo'],
      version: json['version'],
      uploadDate: json['uploadDate'],
      description: json['description'],
      magnetLink: json['magnetLink'],
      torrentUrl: json['torrentUrl'],
      mirrors: Map<String, String>.from(json['mirrors'] ?? {}),
      screenshots: List<String>.from(json['screenshots'] ?? []),
      tags: List<String>.from(json['tags'] ?? []),
    );
  }
}

// Mock Data matching the React app
final List<Game> popularGames = [
  Game(
    id: '1',
    url: '1',
    title: 'Cyberpunk 2077: Phantom Liberty',
    coverUrl:
        'https://lh3.googleusercontent.com/aida-public/AB6AXuCn5Z6jBH_8KHljYsLrbtBy6fpl0NpABIDnPKSPfbPYPd_xGDSD_suhcHgK2SeSarwv2o4gvdLyzGLI463fpZKn7JdhxIQEDbnpuE8rl0O9Li21yO_ZahsiwJnIDGsE48S9YlgJW5dNQW8Ri07diLb-dbyxEXz1K1cSGJRwCObPu5022g298TDHDF0fi8nMaZ-yldWAfYAyNU8Qcl4cxZvTHa8nV-57tl1VSPdjHosN-fJ3s3Yo0KQCPbJUDNHwpEGKfoo8yWMREj1p',
    size: '35.4 GB',
    genre: 'RPG',
  ),
  Game(
    id: '2',
    url: '2',
    title: 'Elden Ring: Shadow of the Erdtree',
    coverUrl:
        'https://lh3.googleusercontent.com/aida-public/AB6AXuB5gENW51CFIqk4GaxIiZ-UkqXU2cPfYlCQ9t7bwdsimQlX3_OWETTDqQE-02GmQm4ClBdeGUE3DcbL5bACQtBLNxfyuzgmFFWdLuhuZTldjfHw1ZZ_FT_cPNyLlt4-yPHrC6Kmb7cZQm7iP2rdju-8Uh994HhHpDJWnWxjWUzwUZHsvF_UsMF9EAvqWHAOCd8RK1pyS1QdsojlQROs-gDh0O7ifSStwD9VFAsv3-gofbZmMLePPHx8afdGSDonohans1V9FpKnPVMA',
    size: '42.1 GB',
    genre: 'Action',
  ),
  Game(
    id: '3',
    url: '3',
    title: "Baldur's Gate 3",
    coverUrl:
        'https://lh3.googleusercontent.com/aida-public/AB6AXuAw8YRT0zjVHuLGiar9cskGIN4aOmipv_jnJ8OgkKGTCQskxd2LVciu8sK_NeW_gPmclIBsLkmWiNd9ReExvy7dquAnPtEphNjsUd9lnjd2LwiaAfFCINIk8MCePOoKRXIi_yOpsDxCtPhmCbQ0n6X_J_7274ug0823UeDTg_e9bHQgp2Sxb4FNa0G7nmVtNIANj379iAl8U57VC6tfDooKKSOsS8EA7S7h8BAvCOXUSMbFGN8Ws_JFnSvDt4XMleum6kWtMfA5msL_',
    size: '50.5 GB',
    genre: 'Strategy',
  ),
  Game(
    id: '8',
    url: '8',
    title: 'God of War Ragnarök',
    coverUrl:
        'https://lh3.googleusercontent.com/aida-public/AB6AXuDBX3L42CvbVwHh6qfVd6Xw20E_yq7yZz1X1q5z8X9Z1X2X3X4X5X6X7X8X9X0X1X2X3X4X5X6X7X8X9X0X1X2X3X4X5X6X7X8X9X0X1X2X3X4X5X6X7', // Mock URL
    size: '84 GB',
    genre: 'Action-Adventure',
  ),
  Game(
    id: '9',
    url: '9',
    title: 'Hades',
    coverUrl:
        'https://lh3.googleusercontent.com/aida-public/AB6AXuBSf62Djv4sgR-xq9YOnJhPCM78ff0FgqhyMSbk8JI0tb_znbTw-_iRseXWW6BCI0XqqHiX08hGM5fX1Ir8lGOzOIQbC667vz3AreXhR24erwSFASSGHoJKpMZjJOgWS-BRidywYkVCPs9f56acBIYdgXawPRH-4mw4wd97V5Vx_XeENYJ7AcHlVLwVadgwTAaBoQzete2jemNhxvJuVIBRjfNCtsOj7vNjNQudi_80pWMUgbBBFe-TBTKiuOnfEdm1nyRB9tCACq_W',
    size: '11 GB',
    genre: 'Roguelike',
  ),
  Game(
    id: '10',
    url: '10',
    title: 'The Witcher 3: Wild Hunt',
    coverUrl:
        'https://lh3.googleusercontent.com/aida-public/AB6AXuD5yZ6jBH_8KHljYsLrbtBy6fpl0NpABIDnPKSPfbPYPd_xGDSD_suhcHgK2SeSarwv2o4gvdLyzGLI463fpZKn7JdhxIQEDbnpuE8rl0O9Li21yO_ZahsiwJnIDGsE48S9YlgJW5dNQW8Ri07diLb-dbyxEXz1K1cSGJRwCObPu5022g298TDHDF0fi8nMaZ-yldWAfYAyNU8Qcl4cxZvTHa8nV-57tl1VSPdjHosN-fJ3s3Yo0KQCPbJUDNHwpEGKfoo8yWMREj1p', // Reusing Cyberpunk URL for mock
    size: '35 GB',
    genre: 'RPG',
  ),
];

final List<Game> newlyAddedGames = [
  Game(
    id: '4',
    url: '4',
    title: 'Hollow Knight',
    coverUrl:
        'https://lh3.googleusercontent.com/aida-public/AB6AXuC0_kEtOTm31GrYAR1oymAB2koHix10EFHAoq7XagOhMdHPK1IUxUDkDufbmwOUJHUpJk_wIEVx1HmghGmA1QUfMCnVhf2JI9IVc6pErpeB8CVIk9I3r_noNtvYnOb19LNoqh_vqU1OkiyMgoADn_hW0T7zWbLvUpLSz7oY80qSB9s8RydgvM_skmExpW1dvz2aM07ZIPdqwAeuDYIhybqbm05apupkFlJta0ZUcLeWZQT8N3wVOCfZ73Ms5j5FkQkWppkxJy2ynGyz',
    size: '2.1 GB',
    genre: 'Metroidvania',
    timeAgo: '2h ago',
  ),
  Game(
    id: '5',
    url: '5',
    title: 'Stardew Valley',
    coverUrl:
        'https://lh3.googleusercontent.com/aida-public/AB6AXuDgDf-oByV9a1_CtMOAnWnPzCL50ARPsJ9ZdlWM7SnDEqpEEuqrOX1hE-TbQHUwECrEzJUYjHZdC16LJ9jpSf9s9_RYAaAvKSzym2v6b_hgPFEnqy2eKK84BRuEX4bE9Y966anlBlozg_sE6QLeoLTRyjUpAMeE248bsMSJJp1nTR3n3RuvN0bCulYsJVkmB7PWmFM6-VBntNpSA-WJsOcUsdQ7FK-BAahqos5Oe91zvwo5tEfQxBjuA2MP2bHeXtrQA6po0HUSiZ7e',
    size: '500 MB',
    genre: 'Sim',
    timeAgo: '5h ago',
  ),
  Game(
    id: '6',
    url: '6',
    title: 'Hades II',
    coverUrl:
        'https://lh3.googleusercontent.com/aida-public/AB6AXuBSf62Djv4sgR-xq9YOnJhPCM78ff0FgqhyMSbk8JI0tb_znbTw-_iRseXWW6BCI0XqqHiX08hGM5fX1Ir8lGOzOIQbC667vz3AreXhR24erwSFASSGHoJKpMZjJOgWS-BRidywYkVCPs9f56acBIYdgXawPRH-4mw4wd97V5Vx_XeENYJ7AcHlVLwVadgwTAaBoQzete2jemNhxvJuVIBRjfNCtsOj7vNjNQudi_80pWMUgbBBFe-TBTKiuOnfEdm1nyRB9tCACq_W',
    size: '15 GB',
    genre: 'Roguelike',
    timeAgo: '1d ago',
  ),
  Game(
    id: '7',
    url: '7',
    title: 'Celeste',
    coverUrl:
        'https://lh3.googleusercontent.com/aida-public/AB6AXuANaKxrJu3Y-LfZZGNYnvzeWwuoyw0-9oFKGxRDwWIrOsJJAKE40GkW0qZ9UbQHdh_-cd0xRx72dldq98g-727in5EOmR2z8l7-stkm_wgOB5N-UF6tmvFiSlESuifF6ljBC5EeGKoCMb4TCiCMP0jBiCFdU-WRXNrLlfFFtLsDlOghIYuZ5k_bQVoFHzSts8G5U0i4yx8QB1b5m9Ep4jVKaPWXnah7Bk5BiQWiQqMZhPpZkXuXbDkdWiJd8hLAjcNZKK_bw37eI9YD',
    size: '1.2 GB',
    genre: 'Platformer',
    timeAgo: '2d ago',
  ),
];
