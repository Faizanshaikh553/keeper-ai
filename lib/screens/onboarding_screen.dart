import 'package:flutter/material.dart';
import 'login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _pages = [
    {
      'icon': Icons.auto_awesome_rounded,
      'title': 'Welcome to Keeper AI',
      'description': 'Never Lose Knowledge.\nBuild Your Future.',
    },
    {
      'icon': Icons.folder_copy_rounded,
      'title': 'Everything in One Place',
      'description':
          'Access your syllabus, timetable, notices, notes and previous papers instantly.',
    },
    {
      'icon': Icons.chat_bubble_rounded,
      'title': 'Ask Anything',
      'description':
          'Ask your college AI assistant and get answers from your institution’s trusted resources.',
    },
  ];

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  _pageController.animateToPage(
                    _pages.length - 1,
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeInOut,
                  );
                },
                child: const Text(
                  'Skip',
                  style: TextStyle(color: Color(0xFF9B98AA), fontSize: 15),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemBuilder: (context, index) {
                  final page = _pages[index];

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 118,
                          height: 118,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(34),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF766DFF), Color(0xFF4C43D6)],
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x55766DFF),
                                blurRadius: 38,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Icon(
                            page['icon'],
                            color: Colors.white,
                            size: 54,
                          ),
                        ),
                        const SizedBox(height: 48),
                        Text(
                          page['title'],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          page['description'],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFAAA8B8),
                            fontSize: 16,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 26 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? const Color(0xFF766DFF)
                        : const Color(0xFF2A2E3D),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 26),
              child: SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: _nextPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF766DFF),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    _currentPage == _pages.length - 1
                        ? 'Get Started'
                        : 'Continue',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
