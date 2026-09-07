/// قاموس ترجمة أسماء الدوريات والفرق الإنجليزية (كما ترد من مصدر البيانات)
/// إلى العربية. أي اسم غير موجود هنا يُعرض كما ورد من المصدر (إنجليزي)
/// بدل ما يختفي أو يظهر فارغاً.
///
/// ملاحظة: هذا القاموس محلي (يُشحن مع التطبيق). لاحقاً يمكن تحويله لقراءة
/// إضافات من Firestore (settings/football_translations) بنفس أسلوب باقي
/// الإعدادات، حتى تضيف/تعدّل ترجمات من لوحة التحكم بدون تحديث التطبيق —
/// [FootballTranslations.applyRemoteOverrides] جاهزة لهذا الغرض.
class FootballTranslations {
  FootballTranslations._();

  static final Map<String, String> _leagues = {
    'Saudi Professional League': 'الدوري السعودي للمحترفين',
    'Saudi Pro League': 'الدوري السعودي للمحترفين',
    'Saudi King Cup': 'كأس الملك السعودي',
    'Egyptian Premier League': 'الدوري المصري الممتاز',
    'UAE Arabian Gulf League': 'دوري الخليج العربي الإماراتي',
    'UAE Pro League': 'دوري المحترفين الإماراتي',
    'Qatar Stars League': 'دوري نجوم قطر',
    'Iraqi Premier League': 'الدوري العراقي الممتاز',
    'Kuwaiti Premier League': 'الدوري الكويتي الممتاز',
    'Moroccan Botola Pro': 'البطولة المغربية المحترفة',
    'Tunisian Ligue 1': 'الرابطة التونسية المحترفة الأولى',
    'Algerian Ligue Professionnelle 1': 'الرابطة الجزائرية المحترفة الأولى',
    'CAF Champions League': 'دوري أبطال أفريقيا',
    'AFC Champions League': 'دوري أبطال آسيا',
    'AFC Champions League Elite': 'دوري أبطال آسيا للنخبة',
    'English Premier League': 'الدوري الإنجليزي الممتاز',
    'Spanish La Liga': 'الدوري الإسباني',
    'Italian Serie A': 'الدوري الإيطالي',
    'German Bundesliga': 'الدوري الألماني',
    'French Ligue 1': 'الدوري الفرنسي',
    'UEFA Champions League': 'دوري أبطال أوروبا',
    'UEFA Europa League': 'الدوري الأوروبي',
    'UEFA Europa Conference League': 'دوري المؤتمر الأوروبي',
    'FIFA World Cup': 'كأس العالم',
    'FIFA Club World Cup': 'كأس العالم للأندية',
    'World Cup Qualification CAF': 'تصفيات كأس العالم الأفريقية',
    'World Cup Qualification AFC': 'تصفيات كأس العالم الآسيوية',
    'Africa Cup of Nations': 'كأس الأمم الأفريقية',
    'AFC Asian Cup': 'كأس آسيا',

    // ملاحظة: أفريقيا مقصورة عمداً على الدول الناطقة بالعربية (مصر،
    // المغرب، تونس، الجزائر) + البطولتين القاريتين (أبطال أفريقيا
    // والكونفدرالية) — أي دوري أفريقي آخر (جنوب أفريقيا، نيجيريا...)
    // مُستبعد عمداً حسب طلب المستخدم، وليس نسياناً.

    // كؤوس محلية مشهورة (الدول الخمس الكبرى + كأس الملك السعودي) — تمت
    // إضافتها بناءً على طلب المستخدم، رغم أنها كانت مستبعدة عمداً سابقاً.
    'FA Cup': 'كأس الاتحاد الإنجليزي',
    'Copa del Rey': 'كأس ملك إسبانيا',
    'Coppa Italia': 'كأس إيطاليا',
    'DFB Pokal': 'كأس ألمانيا',
    'DFB-Pokal': 'كأس ألمانيا',
    'Coupe de France': 'كأس فرنسا',
    'EFL Cup': 'كأس رابطة الأندية الإنجليزية',
    'Carabao Cup': 'كأس رابطة الأندية الإنجليزية',

    // أسماء API-Football القصيرة (بدون بادئة اسم الدولة) — API-Football
    // يرجع "Premier League" وليس "English Premier League" مثلاً، فبدون
    // هذه الأسطر كانت أشهر 5 دوريات أوروبية تُستبعد بالكامل من شاشة
    // النتائج لعدم تطابق النص حرفياً مع القاموس القديم (المبني على
    // تسمية TheSportsDB السابقة).
    'Premier League': 'الدوري الإنجليزي الممتاز',
    'La Liga': 'الدوري الإسباني',
    'Serie A': 'الدوري الإيطالي',
    'Bundesliga': 'الدوري الألماني',
    'Ligue 1': 'الدوري الفرنسي',
    'World Cup': 'كأس العالم',
    'World Cup - Qualification Africa': 'تصفيات كأس العالم الأفريقية',
    'World Cup - Qualification Asia': 'تصفيات كأس العالم الآسيوية',
    'Club World Cup': 'كأس العالم للأندية',
    'CAF Confederation Cup': 'كأس الكونفدرالية الأفريقية',

    // ملاحظة: عمداً لم تُضَف دوريات أخرى (هولندي/برتغالي/تركي/أرجنتيني/
    // برازيلي/أمريكي...) ولا كأس أمم أوروبا (Nations League) ولا
    // الأولمبياد — حصراً الدرجة الأولى من الدوريات الخمس الكبرى + كؤوسها
    // المحلية المشهورة + الدوريات العربية والأفريقية المذكورة + البطولات
    // القارية/الدولية الكبرى فقط، حسب الطلب.
  };

  /// أسماء دوريات يرجعها API-Football **بنفس الشكل بالضبط لأكثر من دولة**
  /// (بدون أي بادئة تميّزها) — أشهر مثال: مصر وإنجلترا كلاهما "Premier
  /// League". بدون هذه الطبقة، القاموس العادي أعلاه كان يترجم أي "Premier
  /// League" مباشرة للإنجليزي بغض النظر عن الدولة الحقيقية، فتظهر فرق
  /// مصرية داخل مجموعة "الدوري الإنجليزي الممتاز".
  ///
  /// المفتاح الخارجي: اسم الدوري مُطبَّعاً (lowercase). المفتاح الداخلي:
  /// اسم الدولة كما يرد من المصدر، مُطبَّعاً أيضاً.
  /// أي دولة غير مذكورة هنا لاسم متضارب تُستبعد بالكامل من العرض (isSupportedLeague
  /// يرجع false لها) — أسلم من عرضها بتصنيف قد يكون خاطئاً.
  static final Map<String, Map<String, String>> _ambiguousLeaguesByCountry = {
    'premier league': {
      'england': 'الدوري الإنجليزي الممتاز',
      'egypt': 'الدوري المصري الممتاز',
    },
    'serie a': {
      'italy': 'الدوري الإيطالي',
      'brazil': 'الدوري البرازيلي',
    },
    'bundesliga': {
      'germany': 'الدوري الألماني',
      'austria': 'الدوري النمساوي',
    },
  };

  /// نفس مفاتيح `_ambiguousLeaguesByCountry` لكن مربوطة بمفتاح ترتيب
  /// الأولوية المناسب في `_leaguePriorityOrder` (اسم/دولة) — يُستخدم فقط
  /// داخل `leaguePriority` أدناه.
  static String? _ambiguousPriorityKey(String normalizedLeague, String normalizedCountry) {
    if (normalizedLeague == 'premier league') {
      if (normalizedCountry == 'england') return 'English Premier League';
      if (normalizedCountry == 'egypt') return 'Egyptian Premier League';
    }
    if (normalizedLeague == 'serie a' && normalizedCountry == 'italy') {
      return 'Italian Serie A';
    }
    if (normalizedLeague == 'bundesliga' && normalizedCountry == 'germany') {
      return 'German Bundesliga';
    }
    return null;
  }

  /// الدوريات المدعومة فقط (عربية + عالمية معروفة) — أي دوري غير موجود هنا
  /// يُستبعد بالكامل من شاشة النتائج بدل عرضه بالإنجليزية، لأن غالب الدوريات
  /// الصغيرة/المحلية غير المعروفة عالمياً (دوريات درجة ثانية وثالثة مثلاً)
  /// ليست ضمن اهتمام المستخدم أصلاً.
  ///
  /// [countryEn] اختياري للتوافق مع الاستدعاءات القديمة، لكن يجب تمريره
  /// دائماً من الآن فصاعداً حتى تُفلتَر أسماء الدوريات المتضاربة (راجع
  /// `_ambiguousLeaguesByCountry`) بشكل صحيح حسب الدولة الفعلية.
  static bool isSupportedLeague(String en, [String? countryEn]) {
    final key = _normalize(en);
    final byCountry = _ambiguousLeaguesByCountry[key];
    if (byCountry != null) {
      return byCountry.containsKey(_normalize(countryEn ?? ''));
    }
    return _leagues.containsKey(en.trim()) || _leaguesNormalized.containsKey(key);
  }

  /// ترتيب أولوية ظهور الدوريات في شاشة النتائج (الأصغر = يظهر أولاً)،
  /// تنازلياً من الأكثر أهمية/شعبية إلى الأقل. أي دوري غير مذكور هنا يظهر
  /// بعد كل هذي القائمة، بترتيب ورودها من المصدر.
  ///
  /// ملاحظة مقصودة: الدوريات الأفريقية (المصري والمغربي والجزائري
  /// والتونسي + البطولتين القاريتين) مُتعمَّد وضعها في آخر القائمة —
  /// طلب صريح من المستخدم، وليس ترتيباً تلقائياً بحت.
  static const List<String> _leaguePriorityOrder = [
    // الدوري الإنجليزي، ثم السعودي (الجمهور الأساسي للتطبيق).
    'Premier League', 'English Premier League',
    'Saudi Pro League', 'Saudi Professional League',
    'Saudi King Cup',

    // بقية الدوريات الأوروبية الخمسة الكبرى + بطولاتها القارية.
    'La Liga', 'Spanish La Liga',
    'UEFA Champions League',
    'Serie A', 'Italian Serie A',
    'Bundesliga', 'German Bundesliga',
    'Ligue 1', 'French Ligue 1',
    'UEFA Europa League',
    'UEFA Europa Conference League',

    // البطولات الدولية الكبرى.
    'FIFA World Cup', 'World Cup',
    'FIFA Club World Cup', 'Club World Cup',

    // كؤوس محلية أوروبية مشهورة.
    'FA Cup', 'Copa del Rey', 'Coppa Italia', 'DFB Pokal', 'DFB-Pokal',
    'Coupe de France', 'EFL Cup', 'Carabao Cup',

    // الدوريات الآسيوية العربية + دوري أبطال آسيا.
    'AFC Champions League Elite', 'AFC Champions League',
    'Qatar Stars League',
    'UAE Pro League', 'UAE Arabian Gulf League',
    'Iraqi Premier League',
    'Kuwaiti Premier League',
    'AFC Asian Cup',
    'World Cup Qualification AFC', 'World Cup - Qualification Asia',

    // الدوريات الأفريقية الناطقة بالعربية + بطولات القارة الأفريقية —
    // مُتعمَّد وضعها هنا في الأسفل (انظر الملاحظة أعلاه).
    'Egyptian Premier League',
    'Moroccan Botola Pro',
    'Algerian Ligue Professionnelle 1',
    'Tunisian Ligue 1',
    'CAF Champions League', 'CAF Confederation Cup',
    'Africa Cup of Nations',
    'World Cup Qualification CAF', 'World Cup - Qualification Africa',
  ];

  static int leaguePriority(String en, [String? countryEn]) {
    final resolvedKey = _ambiguousPriorityKey(_normalize(en), _normalize(countryEn ?? '')) ?? en.trim();
    final index = _leaguePriorityOrder.indexOf(resolvedKey);
    return index == -1 ? _leaguePriorityOrder.length : index;
  }

  static final Map<String, String> _teams = {
    // السعودية
    'Al Hilal': 'الهلال', 'Al-Hilal': 'الهلال',
    'Al Nassr': 'النصر', 'Al-Nassr': 'النصر',
    'Al Ittihad': 'الاتحاد', 'Al-Ittihad': 'الاتحاد',
    'Al Ahli': 'الأهلي', 'Al-Ahli': 'الأهلي',
    'Al Shabab': 'الشباب', 'Al-Shabab': 'الشباب',
    'Al Taawoun': 'التعاون', 'Al-Taawoun': 'التعاون',
    'Al Fateh': 'الفتح', 'Al-Fateh': 'الفتح',
    'Al Ettifaq': 'الاتفاق', 'Al-Ettifaq': 'الاتفاق',
    'Al Fayha': 'الفيحاء', 'Al-Fayha': 'الفيحاء',
    'Damac': 'ضمك',
    'Al Riyadh': 'الرياض', 'Al-Riyadh': 'الرياض',
    'Al Khaleej': 'الخليج', 'Al-Khaleej': 'الخليج',
    'Al Okhdood': 'الأخدود',
    'Al Wehda': 'الوحدة', 'Al-Wehda': 'الوحدة',
    'Al Raed': 'الرائد', 'Al-Raed': 'الرائد',
    'Al Qadsiah': 'القادسية', 'Al-Qadsiah': 'القادسية',
    'Al Kholood': 'الخلود', 'Al-Kholood': 'الخلود',
    'Al Diriyah': 'الدرعية', 'Al-Diriyah': 'الدرعية',
    'Neom': 'نيوم', 'Neom SC': 'نيوم',

    // مصر (الدوري المصري الممتاز)
    'Al Ahly': 'الأهلي المصري', 'Al Ahly SC': 'الأهلي المصري',
    'Zamalek': 'الزمالك',
    'Pyramids': 'بيراميدز', 'Pyramids FC': 'بيراميدز',
    'Al Ittihad Alexandria': 'الاتحاد السكندري',
    'Ismaily': 'الإسماعيلي',
    'ENPPI': 'إنبي',
    'Ceramica Cleopatra': 'سيراميكا كليوباترا',
    'Future FC': 'المستقبل',
    'Smouha': 'سموحة',
    'National Bank of Egypt': 'بنك الأهلي المصري', 'National Bank': 'بنك الأهلي المصري',
    'Al Masry': 'المصري البورسعيدي',
    'ZED FC': 'زد',
    'Modern Sport': 'مودرن سبورت',
    'Ghazl El Mahalla': 'غزل المحلة',
    'Haras El Hodoud': 'حرس الحدود',
    'El Gouna': 'الجونة',
    'Pharco': 'فاركو',
    "Tala'ea El Gaish": 'طلائع الجيش', 'Talaea El Gaish': 'طلائع الجيش',

    // الإمارات (دوري المحترفين الإماراتي)
    'Al Ain': 'العين',
    'Al Wahda': 'الوحدة الإماراتي',
    'Al Wasl': 'الوصل',
    'Al Jazira': 'الجزيرة',
    'Sharjah': 'الشارقة',
    'Al Nasr': 'النصر الإماراتي',
    'Shabab Al Ahli': 'شباب الأهلي',
    'Ajman': 'عجمان',
    'Baniyas': 'بني ياس',
    'Al Ittihad Kalba': 'اتحاد كلباء',
    'Khor Fakkan': 'خورفكان',
    'Al Bataeh': 'البطائح',
    'Dibba Al Fujairah': 'ديبا الفجيرة',
    'Hatta': 'حتا',

    // قطر (دوري نجوم قطر)
    'Al Sadd': 'السد',
    'Al Duhail': 'الدحيل',
    'Al Rayyan': 'الريان',
    'Al Gharafa': 'الغرافة',
    'Al Arabi': 'العربي',
    'Qatar SC': 'قطر',
    'Al Wakrah': 'الوكرة',
    'Umm Salal': 'أم صلال',
    // ملاحظة: "Al Ahli" وحدها محجوزة أعلاه للأهلي السعودي (أشيع استخداماً)
    // — أهلي الدوحة نادراً ما يرد بنفس الاسم المجرد من API-Football.
    'Al Ahli Doha': 'الأهلي الدوحة',
    'Al Shahania': 'الشحانية',
    'Al Markhiya': 'المرخية',

    // العراق (الدوري العراقي الممتاز)
    'Al Shorta': 'الشرطة العراقي',
    'Al Zawraa': 'الزوراء',
    'Al Quwa Al Jawiya': 'القوة الجوية',
    'Naft Al Wasat': 'نفط الوسط',
    'Erbil': 'أربيل',
    'Duhok': 'دهوك',
    'Newroz': 'نوروز',
    'Karbalaa': 'كربلاء',
    'Naft Maysan': 'نفط ميسان',
    'Al Talaba': 'الطلبة',
    'Al Karkh': 'الكرخ',
    'Nineveh': 'نينوى',
    'Al Hudood': 'الحدود',
    'Diyala': 'ديالى',
    'Naft Al Basra': 'نفط البصرة',
    'Zakho': 'زاخو',

    // الكويت (الدوري الكويتي الممتاز)
    'Al Kuwait': 'الكويت',
    'Al Arabi Kuwait': 'العربي الكويتي',
    'Kazma': 'كاظمة',
    'Al Qadsia Kuwait': 'القادسية الكويتي',
    'Al Salmiya': 'الصليبيخات', 'Salmiya': 'السالمية',
    'Al Jahra': 'الجهراء',
    'Al Fahaheel': 'الفحيحيل',
    'Al Yarmouk': 'اليرموك',
    'Al Naser': 'النصر الكويتي',
    'Kuwait SC': 'الكويت',

    // المغرب (البطولة المغربية المحترفة)
    'Raja Casablanca': 'الرجاء البيضاوي',
    'Wydad Casablanca': 'الوداد البيضاوي',
    'FAR Rabat': 'الجيش الملكي',
    'RS Berkane': 'نهضة بركان',
    'Hassania Agadir': 'حسنية أكادير',
    'Moghreb Tetouan': 'المغرب التطواني',
    'Difaa El Jadidi': 'الدفاع الحسني الجديدي',
    'Ittihad Tanger': 'اتحاد طنجة',

    // تونس (الرابطة التونسية المحترفة الأولى)
    'Esperance Tunis': 'الترجي التونسي',
    'Etoile du Sahel': 'النجم الساحلي',
    'Club Africain': 'النادي الإفريقي',
    'CS Sfaxien': 'النادي الصفاقسي',

    // الجزائر (الرابطة الجزائرية المحترفة الأولى)
    'ES Setif': 'وفاق سطيف',
    'CR Belouizdad': 'شباب بلوزداد',
    'MC Alger': 'مولودية الجزائر',
    'USM Alger': 'اتحاد العاصمة',
    'JS Kabylie': 'شبيبة القبائل',

    // منتخبات
    'Saudi Arabia': 'السعودية',
    'Egypt': 'مصر',
    'Morocco': 'المغرب',
    'Tunisia': 'تونس',
    'Algeria': 'الجزائر',
    'Qatar': 'قطر',
    'United Arab Emirates': 'الإمارات',
    'Iraq': 'العراق',
    'Jordan': 'الأردن',
    'Kuwait': 'الكويت',
    'Bahrain': 'البحرين',
    'Oman': 'عمان',
    'Lebanon': 'لبنان',
    'Palestine': 'فلسطين',
    'Syria': 'سوريا',
    'Brazil': 'البرازيل',
    'Argentina': 'الأرجنتين',
    'France': 'فرنسا',
    'Germany': 'ألمانيا',
    'Spain': 'إسبانيا',
    'England': 'إنجلترا',
    'Italy': 'إيطاليا',
    'Portugal': 'البرتغال',
    'Netherlands': 'هولندا',
    'Belgium': 'بلجيكا',
    'Croatia': 'كرواتيا',
    'Uruguay': 'الأوروغواي',
    // أندية عالمية كبرى
    'Real Madrid': 'ريال مدريد',
    'Barcelona': 'برشلونة',
    'Atletico Madrid': 'أتلتيكو مدريد',
    'Manchester United': 'مانشستر يونايتد',
    'Manchester City': 'مانشستر سيتي',
    'Liverpool': 'ليفربول',
    'Chelsea': 'تشيلسي',
    'Arsenal': 'آرسنال',
    'Tottenham': 'توتنهام',
    'Tottenham Hotspur': 'توتنهام',
    'Bayern Munich': 'بايرن ميونخ',
    'Borussia Dortmund': 'بوروسيا دورتموند',
    'Paris Saint-Germain': 'باريس سان جيرمان',
    'Juventus': 'يوفنتوس',
    'AC Milan': 'ميلان',
    'Inter Milan': 'إنتر ميلان',
    'Napoli': 'نابولي',
    'AS Roma': 'روما',
    // أرجنتين
    'River Plate': 'ريفر بليت',
    'Boca Juniors': 'بوكا جونيورز',
    'Racing Club': 'راسينغ كلوب',
    'Independiente': 'إندبندينتي',
    'San Lorenzo': 'سان لورينزو',
    // البرازيل
    'Flamengo': 'فلامنغو',
    'Palmeiras': 'بالميراس',
    'Corinthians': 'كورينثيانز',
    'Sao Paulo': 'ساو باولو',
    'Fluminense': 'فلومينينسي',
    // أمريكا (MLS)
    'LA Galaxy': 'إل إيه غالاكسي',
    'Inter Miami': 'إنتر ميامي',
    'LAFC': 'لوس أنجلوس إف سي',
    'Seattle Sounders': 'سياتل ساوندرز',

    // الدوري الإنجليزي (بقية الفرق)
    'Newcastle United': 'نيوكاسل يونايتد', 'Newcastle': 'نيوكاسل يونايتد',
    'Aston Villa': 'أستون فيلا',
    'Nottingham Forest': 'نوتنغهام فورست',
    'Brighton & Hove Albion': 'برايتون', 'Brighton and Hove Albion': 'برايتون', 'Brighton': 'برايتون',
    'Bournemouth': 'بورنموث', 'AFC Bournemouth': 'بورنموث',
    'Brentford': 'برينتفورد',
    'Fulham': 'فولهام',
    'Crystal Palace': 'كريستال بالاس',
    'Everton': 'إيفرتون',
    'Leeds United': 'ليدز يونايتد', 'Leeds': 'ليدز يونايتد',
    'Sunderland': 'سندرلاند',
    'Coventry City': 'كوفنتري سيتي',
    'Ipswich Town': 'إبسويتش تاون',
    'Hull City': 'هال سيتي',

    // الدوري الإسباني (بقية الفرق)
    'Athletic Bilbao': 'أتلتيك بيلباو', 'Athletic Club': 'أتلتيك بيلباو',
    'Villarreal': 'فياريال',
    'Real Betis': 'ريال بيتيس',
    'Real Sociedad': 'ريال سوسيداد',
    'Sevilla': 'إشبيلية',
    'Valencia': 'فالنسيا',
    'Celta Vigo': 'سلتا فيغو',
    'Rayo Vallecano': 'رايو فاليكانو',
    'Osasuna': 'أوساسونا',
    'Getafe': 'خيتافي',
    'Espanyol': 'إسبانيول',
    'Alaves': 'ألافيس', 'Deportivo Alaves': 'ألافيس',
    'Levante': 'ليفانتي',
    'Elche': 'إلتشي',
    'Racing Santander': 'راسينغ سانتاندير', 'Racing de Santander': 'راسينغ سانتاندير',
    'Deportivo La Coruna': 'ديبورتيفو لاكورونيا', 'Deportivo La Coruña': 'ديبورتيفو لاكورونيا',
    'Las Palmas': 'لاس بالماس', 'UD Las Palmas': 'لاس بالماس',

    // الدوري الإيطالي (بقية الفرق)
    'Lazio': 'لاتسيو',
    'Atalanta': 'أتالانتا',
    'Fiorentina': 'فيورنتينا',
    'Bologna': 'بولونيا',
    'Torino': 'تورينو',
    'Udinese': 'أودينيزي',
    'Genoa': 'جنوى',
    'Cagliari': 'كالياري',
    'Parma': 'بارما',
    'Como': 'كومو',
    'Verona': 'فيرونا', 'Hellas Verona': 'فيرونا',
    'Lecce': 'ليتشي',
    'Cremonese': 'كريمونيزي',
    'Pisa': 'بيزا',
    'Sassuolo': 'ساسولو',
    'Monza': 'مونزا',
    'Frosinone': 'فروزينوني',

    // الدوري الألماني (بقية الفرق)
    'RB Leipzig': 'آر بي لايبزيغ',
    'Bayer Leverkusen': 'باير ليفركوزن',
    'Eintracht Frankfurt': 'آينتراخت فرانكفورت',
    'VfB Stuttgart': 'شتوتغارت', 'Stuttgart': 'شتوتغارت',
    'Borussia Monchengladbach': 'بوروسيا مونشنغلادباخ', "Borussia M'gladbach": 'بوروسيا مونشنغلادباخ',
    'Werder Bremen': 'فيردر بريمن',
    'SC Freiburg': 'فرايبورغ', 'Freiburg': 'فرايبورغ',
    'Mainz 05': 'ماينز', 'Mainz': 'ماينز',
    'Union Berlin': 'يونيون برلين',
    'Augsburg': 'أوغسبورغ',
    'Hoffenheim': 'هوفنهايم', 'TSG Hoffenheim': 'هوفنهايم',
    'FC Koln': 'كولن', 'Cologne': 'كولن',
    'Schalke 04': 'شالكه',
    'SV Elversberg': 'إلفرسبيرغ',
    'SC Paderborn': 'بادربورن', 'Paderborn': 'بادربورن',

    // الدوري الفرنسي (بقية الفرق)
    'Marseille': 'مارسيليا', 'Olympique Marseille': 'مارسيليا',
    'Monaco': 'موناكو', 'AS Monaco': 'موناكو',
    'Lyon': 'ليون', 'Olympique Lyonnais': 'ليون',
    'Lille': 'ليل',
    'Nice': 'نيس',
    'Rennes': 'رين',
    'Lens': 'لانس',
    'Strasbourg': 'ستراسبورغ',
    'Toulouse': 'تولوز',
    'Reims': 'ريمس',
    'Auxerre': 'أوكسير',
    'Angers': 'أنجيه',
    'Le Havre': 'لوهافر',
    'Brest': 'بريست',
    'Troyes': 'تروا',
    'Le Mans': 'لومان',
    'Paris FC': 'باريس إف سي',
  };

  /// يحوّل وقت المباراة إلى صيغة 12 ساعة بالعربي (مثال: "10:00 م").
  static String formatTime12(DateTime dt) {
    final hour24 = dt.hour;
    final isPm = hour24 >= 12;
    var hour12 = hour24 % 12;
    if (hour12 == 0) hour12 = 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = isPm ? 'م' : 'ص';
    return '$hour12:$minute $suffix';
  }

  // مطابقة متساهلة: تتجاهل فروقات بسيطة (مسافات زائدة، حالة الأحرف،
  // شرطة "-" بدل مسافة) بين اسم الفريق/الدوري القادم من API-Football
  // والمفتاح المخزّن في القاموس أعلاه — كثير من حالات "اسم إنجليزي ظهر
  // رغم وجود ترجمة له" سببها فرق شكلي بسيط في النص وليس غياب الترجمة
  // فعلاً.
  static String _normalize(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'[\s\-]+'), ' ');

  static final Map<String, String> _leaguesNormalized = {
    for (final entry in _leagues.entries) _normalize(entry.key): entry.value,
  };

  static final Map<String, String> _teamsNormalized = {
    for (final entry in _teams.entries) _normalize(entry.key): entry.value,
  };

  /// يجهّز نسخة مطبَّعة (normalized) من أي ترجمات إضافية، بنفس أسلوب
  /// القاموسين الأساسيين أعلاه — يُستدعى من applyRemoteOverrides أدناه.
  static void _mergeNormalized(Map<String, String> target, Map<String, String> extra) {
    for (final entry in extra.entries) {
      target[_normalize(entry.key)] = entry.value;
    }
  }

  static String league(String en) =>
      _leagues[en.trim()] ?? _leaguesNormalized[_normalize(en)] ?? en;

  /// نفس `league` لكن يفكّ التضارب أولاً حسب الدولة إذا كان اسم الدوري
  /// من ضمن `_ambiguousLeaguesByCountry` (مثال: "Premier League" لمصر
  /// مقابل إنجلترا). استخدم هذه الدالة دائماً بدل `league` عند وجود
  /// leagueCountryEn متاح (شاشة النتائج وتفاصيل المباراة).
  static String leagueWithCountry(String en, String? countryEn) {
    final key = _normalize(en);
    final byCountry = _ambiguousLeaguesByCountry[key];
    if (byCountry != null) {
      return byCountry[_normalize(countryEn ?? '')] ?? en;
    }
    return league(en);
  }

  static String team(String en) =>
      _teams[en.trim()] ?? _teamsNormalized[_normalize(en)] ?? en;

  /// يدمج ترجمات إضافية (مثلاً قادمة من Firestore) فوق القاموس المحلي —
  /// تُستخدم لاحقاً لو رُبط هذا الملف بمصدر أونلاين قابل للتعديل من لوحة
  /// التحكم بدون تحديث التطبيق.
  static void applyRemoteOverrides({
    Map<String, String>? leagues,
    Map<String, String>? teams,
  }) {
    if (leagues != null) {
      _leagues.addAll(leagues);
      _mergeNormalized(_leaguesNormalized, leagues);
    }
    if (teams != null) {
      _teams.addAll(teams);
      _mergeNormalized(_teamsNormalized, teams);
    }
  }
}
