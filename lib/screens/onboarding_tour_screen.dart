import 'package:flutter/material.dart';
import '../services/translation_service.dart';
import '../services/wizard_service.dart';

class OnboardingTourScreen extends StatefulWidget {
  const OnboardingTourScreen({super.key});

  @override
  State<OnboardingTourScreen> createState() => _OnboardingTourScreenState();
}

class _OnboardingTourScreenState extends State<OnboardingTourScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _totalPages = 5;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finishTour();
    }
  }

  void _finishTour() {
    WizardService.markOnboardingTourSeen();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.primaryColor.withOpacity(0.95),
      body: SafeArea(
        child: GestureDetector(
          onTap: _nextPage,
          behavior: HitTestBehavior.opaque,
          child: Column(
            children: [
              // Skip button
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextButton(
                    onPressed: _finishTour,
                    child: Text(
                      TranslationService.translate(context, 'onboarding_skip'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              
              // Page content
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() => _currentPage = index);
                  },
                  children: [
                    _buildSlide(
                      icon: Icons.auto_stories,
                      title: TranslationService.translate(context, 'onboarding_welcome_title'),
                      description: TranslationService.translate(context, 'onboarding_welcome_desc'),
                    ),
                    _buildSlide(
                      icon: Icons.library_books,
                      title: TranslationService.translate(context, 'onboarding_books_title'),
                      description: TranslationService.translate(context, 'onboarding_books_desc'),
                    ),
                    _buildSlide(
                      icon: Icons.share,
                      title: TranslationService.translate(context, 'onboarding_p2p_title'),
                      description: TranslationService.translate(context, 'onboarding_p2p_desc'),
                    ),
                    _buildSlide(
                      icon: Icons.people,
                      title: TranslationService.translate(context, 'onboarding_contacts_title'),
                      description: TranslationService.translate(context, 'onboarding_contacts_desc'),
                    ),
                    _buildSlide(
                      icon: Icons.analytics,
                      title: TranslationService.translate(context, 'onboarding_stats_title'),
                      description: TranslationService.translate(context, 'onboarding_stats_desc'),
                      isLast: true,
                    ),
                  ],
                ),
              ),
              
              // Progress indicators
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _totalPages,
                    (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentPage == index ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentPage == index
                            ? Colors.white
                            : Colors.white.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlide({
    required IconData icon,
    required String title,
    required String description,
    bool isLast = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 80,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 48),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 48),
          if (isLast)
            ElevatedButton(
              onPressed: _finishTour,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Theme.of(context).primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: Text(
                TranslationService.translate(context, 'onboarding_finish'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else
            Text(
              TranslationService.translate(context, 'onboarding_tap_continue'),
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.7),
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}
