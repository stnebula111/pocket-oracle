import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flip_card/flip_card.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'models/tarot_card.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  try {
    await FirebaseAuth.instance.signInAnonymously();
  } catch (e) {
    debugPrint("Auth Error: $e");
  }
  runApp(const TarotApp());
}

class TarotSpread {
  final String title;
  final String description;
  final List<String> labels;
  final int count;
  TarotSpread({required this.title, required this.description, required this.labels, required this.count});
}

class TarotApp extends StatelessWidget {
  const TarotApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pocket Oracle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.deepPurple,
        fontFamily: 'Metamorphous',
        scaffoldBackgroundColor: const Color(0xFF0F0C29),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, centerTitle: true),
      ),
      home: const MainNavigation(),
    );
  }
}

// --- PARTICLE BACKGROUND ---
class StarfieldBackground extends StatefulWidget {
  final Widget child;
  const StarfieldBackground({super.key, required this.child});
  @override
  State<StarfieldBackground> createState() => _StarfieldBackgroundState();
}

class _StarfieldBackgroundState extends State<StarfieldBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<math.Point> stars = List.generate(45, (i) => math.Point(math.Random().nextDouble(), math.Random().nextDouble()));

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 25))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0F0C29), Color(0xFF302B63), Color(0xFF24243E)],
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(painter: StarPainter(stars, _controller.value), size: Size.infinite);
          },
        ),
        widget.child,
      ],
    );
  }
}

class StarPainter extends CustomPainter {
  final List<math.Point> stars;
  final double animationValue;
  StarPainter(this.stars, this.animationValue);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    for (var star in stars) {
      double x = star.x * size.width;
      double y = (star.y * size.height + (animationValue * 80)) % size.height;
      double opacity = (math.sin(animationValue * math.pi * 4 + star.x * 20) + 1) / 2;
      paint.color = Colors.white.withValues(alpha: opacity * 0.3);
      canvas.drawCircle(Offset(x, y), 1.2 * star.x + 0.5, paint);
    }
  }
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

// --- MAIN HUB ---
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;
  String _selectedCardBack = 'assets/images/card_back.jpg';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedCardBack = prefs.getString('card_back') ?? 'assets/images/card_back.jpg';
    });
  }

  _updateCardBack(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('card_back', path);
    setState(() => _selectedCardBack = path);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      DeckScreen(cardBack: _selectedCardBack),
      DailyCardScreen(cardBack: _selectedCardBack),
      const LibraryScreen(),
      const JournalScreen(),
      SettingsScreen(currentBack: _selectedCardBack, onBackChanged: _updateCardBack),
    ];

    return StarfieldBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: IndexedStack(index: _selectedIndex, children: screens),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          backgroundColor: const Color(0xFF16213E).withValues(alpha: 0.9),
          selectedItemColor: Colors.amberAccent,
          unselectedItemColor: Colors.white54,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: "Oracle"),
            BottomNavigationBarItem(icon: Icon(Icons.today), label: "Daily"),
            BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: "Library"),
            BottomNavigationBarItem(icon: Icon(Icons.history_edu), label: "Journal"),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Settings"),
          ],
        ),
      ),
    );
  }
}

// --- TAB 1: ORACLE ---
class DeckScreen extends StatefulWidget {
  final String cardBack;
  const DeckScreen({super.key, required this.cardBack});
  @override
  State<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends State<DeckScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ScreenshotController _screenshotController = ScreenshotController();
  List<TarotCard> deck = [];
  List<TarotCard> currentSpread = [];
  List<bool> isRevealed = [];
  List<bool> orientationIsReversed = [];
  List<GlobalKey<FlipCardState>> cardKeys = [];
  TarotSpread? activeSpread;
  bool isLoading = true;
  bool isSaving = false;
  final PageController _pageController = PageController(viewportFraction: 0.85);

  final List<TarotSpread> spreads = [
    TarotSpread(title: "DAILY PULL", description: "Single card guidance", labels: ["GUIDANCE"], count: 1),
    TarotSpread(title: "3-CARD SPREAD", description: "Past, Present, and Future", labels: ["PAST", "PRESENT", "FUTURE"], count: 3),
    TarotSpread(title: "HORSESHOE", description: "7-card deep dive", labels: ["PAST", "PRESENT", "HIDDEN", "OBSTACLE", "EXTERNAL", "ADVICE", "OUTCOME"], count: 7),
    TarotSpread(title: "CELTIC CROSS", description: "10-card classic reading", labels: ["PRESENT", "CHALLENGE", "PAST", "FUTURE", "CONSCIOUS", "SUB-CON", "ADVICE", "EXTERNAL", "HOPES/FEARS", "OUTCOME"], count: 10),
    TarotSpread(title: "BIRTH CARD", description: "Numerology path", labels: [], count: 0),
  ];

  @override
  void initState() { super.initState(); _loadDeck(); }

  _loadDeck() async {
    final String response = await rootBundle.loadString('assets/tarot_data.json');
    final List<dynamic> data = json.decode(response);
    if (!mounted) return;
    setState(() {
      deck = data.map((cardJson) => TarotCard.fromJson(cardJson)).toList();
      isLoading = false;
    });
  }

  void _drawCards(TarotSpread spread) async {
    if (spread.count == 0) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => BirthCardScreen(allCards: deck)));
      return;
    }
    HapticFeedback.mediumImpact();
    await _audioPlayer.play(AssetSource('sounds/shuffle.wav'));
    setState(() {
      activeSpread = spread;
      isRevealed = List.generate(spread.count, (_) => false);
      orientationIsReversed = List.generate(spread.count, (_) => math.Random().nextBool());
      currentSpread = [];
    });
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() {
      deck.shuffle();
      currentSpread = deck.take(spread.count).toList();
      cardKeys = List.generate(spread.count, (_) => GlobalKey<FlipCardState>());
    });
  }

  void _shareSpread() async {
    final image = await _screenshotController.capture();
    if (image != null) {
      final directory = await getApplicationDocumentsDirectory();
      final imagePath = await File('${directory.path}/tarot_reading.png').create();
      await imagePath.writeAsBytes(image);
      await Share.shareXFiles([XFile(imagePath.path)], text: 'My reading from Pocket Oracle ✨');
    }
  }

  Future<void> _saveReading() async {
    setState(() => isSaving = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    List<String> entries = currentSpread.asMap().entries.map((e) => "${e.value.name} ${orientationIsReversed[e.key] ? '(R)' : '(U)'}").toList();
    await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('readings').add({
      'timestamp': FieldValue.serverTimestamp(),
      'spreadTitle': activeSpread?.title,
      'cardNames': entries,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reading Saved!")));
    setState(() => isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text("POCKET ORACLE", style: TextStyle(letterSpacing: 4)),
        actions: [
          if (currentSpread.isNotEmpty) IconButton(icon: const Icon(Icons.share), onPressed: _shareSpread),
          if (currentSpread.isNotEmpty) IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState(() => currentSpread = [])),
        ],
      ),
      body: isLoading ? const Center(child: CircularProgressIndicator()) :
      currentSpread.isEmpty ? _buildSelection() : _buildReading(),
    );
  }

  Widget _buildSelection() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: spreads.map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(width: 320, child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16213E).withValues(alpha: 0.8), padding: const EdgeInsets.all(18), side: const BorderSide(color: Colors.amberAccent, width: 0.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              onPressed: () => _drawCards(s),
              child: Column(children: [Text(s.title, style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)), Text(s.description, style: const TextStyle(fontSize: 10, color: Colors.white38))]),
            )),
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildReading() {
    return Column(
      children: [
        Expanded(
          child: Screenshot(
            controller: _screenshotController,
            child: Container(
              color: const Color(0xFF0F0C29),
              child: PageView.builder(
                controller: _pageController,
                itemCount: currentSpread.length,
                itemBuilder: (context, index) => _buildCardPage(index),
              ),
            ),
          ),
        ),
        if (isRevealed.isNotEmpty && isRevealed.every((r) => r == true))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                  onPressed: isSaving ? null : _saveReading,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, padding: const EdgeInsets.all(15)),
                  child: Text(isSaving ? "SAVING..." : "SAVE TO JOURNAL")
              ),
            ),
          ),
        TextButton.icon(onPressed: () => setState(() => currentSpread = []), icon: const Icon(Icons.close), label: const Text("EXIT")),
      ],
    );
  }

  Widget _buildCardPage(int index) {
    final card = currentSpread[index];
    final rev = orientationIsReversed[index];
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 10),
          Text(activeSpread!.labels[index], style: const TextStyle(color: Colors.amberAccent, letterSpacing: 4, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          FlipCard(
            key: cardKeys[index],
            onFlip: () { HapticFeedback.lightImpact(); _audioPlayer.play(AssetSource('sounds/flip.wav')); },
            onFlipDone: (isFront) => setState(() => isRevealed[index] = !isFront),
            front: _cardImg(widget.cardBack, Colors.black54),
            back: Transform.rotate(angle: rev ? math.pi : 0, child: _cardImg(card.imagePath, Colors.amberAccent)),
          ),
          const SizedBox(height: 20),
          AnimatedOpacity(
            opacity: isRevealed[index] ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 500),
            child: Column(children: [
              Text(card.name + (rev ? " (REV)" : ""), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10), child: Text(rev ? card.meaningReversed : card.meaningUpright, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Colors.white70))),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _cardImg(String path, Color shadow) {
    return Container(
      decoration: BoxDecoration(boxShadow: [BoxShadow(color: shadow.withValues(alpha: 0.3), blurRadius: 30)]),
      child: ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.asset(path, height: 400, fit: BoxFit.contain)),
    );
  }

  @override
  void dispose() { _audioPlayer.dispose(); _pageController.dispose(); super.dispose(); }
}

// --- TAB 2: DAILY CARD ---
class DailyCardScreen extends StatefulWidget {
  final String cardBack;
  const DailyCardScreen({super.key, required this.cardBack});
  @override
  State<DailyCardScreen> createState() => _DailyCardScreenState();
}
class _DailyCardScreenState extends State<DailyCardScreen> {
  TarotCard? dailyCard;
  bool revealed = false;
  @override
  void initState() { super.initState(); _loadDaily(); }
  _loadDaily() async {
    final String res = await rootBundle.loadString('assets/tarot_data.json');
    final List<dynamic> data = json.decode(res);
    final now = DateTime.now();
    final seed = now.year * 10000 + now.month * 100 + now.day;
    final r = math.Random(seed);
    setState(() => dailyCard = TarotCard.fromJson(data[r.nextInt(data.length)]));
  }
  @override
  Widget build(BuildContext context) {
    return Center(
      child: dailyCard == null ? const CircularProgressIndicator() : Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("TODAY'S ENERGY", style: TextStyle(letterSpacing: 2, color: Colors.white38)),
          const SizedBox(height: 30),
          FlipCard(
            onFlipDone: (isFront) => setState(() => revealed = !isFront),
            front: _cardImg(widget.cardBack, Colors.black),
            back: _cardImg(dailyCard!.imagePath, Colors.amberAccent),
          ),
          const SizedBox(height: 30),
          if (revealed) Text(dailyCard!.name.toUpperCase(), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
          if (revealed) Padding(padding: const EdgeInsets.symmetric(horizontal: 40), child: Text(dailyCard!.meaningUpright, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
  Widget _cardImg(String path, Color shadow) {
    return Container(decoration: BoxDecoration(boxShadow: [BoxShadow(color: shadow.withValues(alpha: 0.2), blurRadius: 30)]), child: ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.asset(path, height: 400)));
  }
}

// --- TAB 3: LIBRARY (FIXED FILTERING) ---
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}
class _LibraryScreenState extends State<LibraryScreen> {
  List<TarotCard> all = [];
  List<TarotCard> display = [];
  String query = "";
  String selectedSuit = "All";
  final List<String> suits = ["All", "Major Arcana", "Cups", "Swords", "Wands", "Pentacles"];

  @override
  void initState() { super.initState(); _load(); }

  _load() async {
    final String res = await rootBundle.loadString('assets/tarot_data.json');
    final List<dynamic> data = json.decode(res);
    setState(() {
      all = data.map((c) => TarotCard.fromJson(c)).toList();
      display = all;
    });
  }

  void _filter() {
    setState(() {
      display = all.where((c) {
        final matchesSearch = c.name.toLowerCase().contains(query.toLowerCase());
        // FIXED: Case-insensitive comparison for arcana/suit field
        final matchesSuit = (selectedSuit == "All") ||
            (c.arcana.toLowerCase() == selectedSuit.toLowerCase()) ||
            (selectedSuit == "Major Arcana" && c.arcana.toLowerCase().contains("major"));
        return matchesSearch && matchesSuit;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const SizedBox(height: 50),
      Padding(padding: const EdgeInsets.all(12), child: TextField(onChanged: (v) { query = v; _filter(); }, decoration: InputDecoration(hintText: "Search cards...", prefixIcon: const Icon(Icons.search), filled: true, fillColor: const Color(0xFF16213E).withValues(alpha: 0.8), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)))),
      SizedBox(height: 40, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: suits.length, itemBuilder: (context, i) => Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: ChoiceChip(label: Text(suits[i]), selected: selectedSuit == suits[i], onSelected: (s) { setState(() { selectedSuit = suits[i]; _filter(); }); })))),
      Expanded(child: GridView.builder(padding: const EdgeInsets.all(15), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.6, crossAxisSpacing: 10, mainAxisSpacing: 10), itemCount: display.length, itemBuilder: (context, i) => GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => CardDetailScreen(card: display[i]))), child: Hero(tag: 'lib_${display[i].id}', child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.asset(display[i].imagePath, fit: BoxFit.cover)))))),
    ]);
  }
}

class CardDetailScreen extends StatelessWidget {
  final TarotCard card;
  const CardDetailScreen({super.key, required this.card});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(card.name)),
      body: SingleChildScrollView(child: Column(children: [
        const SizedBox(height: 20),
        Hero(tag: 'lib_${card.id}', child: Center(child: ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.asset(card.imagePath, height: 400)))),
        Padding(padding: const EdgeInsets.all(30), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(card.arcana.toUpperCase(), style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, letterSpacing: 2)),
          Text(card.name, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const Divider(height: 40),
          const Text("UPRIGHT", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
          Text(card.meaningUpright, style: const TextStyle(fontSize: 16, height: 1.5)),
          const SizedBox(height: 30),
          const Text("REVERSED", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          Text(card.meaningReversed, style: const TextStyle(fontSize: 16, height: 1.5)),
        ])),
      ])),
    );
  }
}

// --- TAB 4: JOURNAL ---
class JournalScreen extends StatelessWidget {
  const JournalScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text("MY JOURNAL")),
      body: user == null ? const Center(child: CircularProgressIndicator()) : StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('readings').orderBy('timestamp', descending: true).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData || snap.data!.docs.isEmpty) return const Center(child: Text("Empty Journal."));
          return ListView.builder(
            itemCount: snap.data!.docs.length,
            itemBuilder: (context, i) {
              var doc = snap.data!.docs[i];
              var data = doc.data() as Map<String, dynamic>;
              DateTime date = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: const Color(0xFF16213E).withValues(alpha: 0.8),
                child: ListTile(
                  title: Text(data['spreadTitle'] ?? "Reading", style: const TextStyle(color: Colors.amberAccent)),
                  subtitle: Text("${(data['cardNames'] as List).join(', ')}\n${DateFormat('MMM dd, hh:mm a').format(date)}"),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// --- TAB 5: SETTINGS ---
class SettingsScreen extends StatelessWidget {
  final String currentBack;
  final Function(String) onBackChanged;
  const SettingsScreen({super.key, required this.currentBack, required this.onBackChanged});
  @override
  Widget build(BuildContext context) {
    final backs = ['assets/images/card_back.jpg', 'assets/images/card_back_alt1.jpg', 'assets/images/card_back_alt2.jpg', 'assets/images/card_back_alt3.jpg'];
    return Padding(padding: const EdgeInsets.all(20.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text("CHOOSE YOUR DECK BACK", style: TextStyle(color: Colors.amberAccent, letterSpacing: 2, fontWeight: FontWeight.bold)),
      const SizedBox(height: 40),
      SizedBox(height: 200, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: backs.length, itemBuilder: (context, i) => GestureDetector(
        onTap: () => onBackChanged(backs[i]),
        child: Container(margin: const EdgeInsets.only(right: 15), decoration: BoxDecoration(border: Border.all(color: currentBack == backs[i] ? Colors.amberAccent : Colors.white10, width: 2), borderRadius: BorderRadius.circular(10)), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset(backs[i], width: 120, fit: BoxFit.cover))),
      ))),
    ]));
  }
}

// --- BIRTH CARD ---
class BirthCardScreen extends StatefulWidget {
  final List<TarotCard> allCards;
  const BirthCardScreen({super.key, required this.allCards});
  @override
  State<BirthCardScreen> createState() => _BirthCardScreenState();
}
class _BirthCardScreenState extends State<BirthCardScreen> {
  TarotCard? res;
  _calc(DateTime d) {
    int sum = (d.year ~/ 100) + (d.year % 100) + d.month + d.day;
    int r = sum;
    while (r > 21) {
      int t = 0;
      for (var c in r.toString().split('')) { t += int.parse(c); }
      r = t;
    }
    setState(() => res = widget.allCards.firstWhere((c) => c.id == r));
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0C29),
      appBar: AppBar(title: const Text("BIRTH CARD")),
      body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (res == null) ElevatedButton(onPressed: () async {
          DateTime? p = await showDatePicker(context: context, initialDate: DateTime(2000), firstDate: DateTime(1900), lastDate: DateTime.now());
          if (p != null) _calc(p);
        }, child: const Text("SELECT BIRTHDAY"))
        else ...[
          Hero(tag: 'lib_${res!.id}', child: Image.asset(res!.imagePath, height: 350)),
          const SizedBox(height: 20),
          Text(res!.name.toUpperCase(), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
          Padding(padding: const EdgeInsets.all(20), child: Text(res!.meaningUpright, textAlign: TextAlign.center)),
          TextButton(onPressed: () => setState(() => res = null), child: const Text("RESET")),
        ]
      ])),
    );
  }
}