import 'package:flutter/material.dart';
import '../services/translation_service.dart';
import '../services/wizard_service.dart';

class OnboardingTourScreen extends StatefulWidget {
  const OnboardingTourScreen({super.key});

  @override
  State<OnboardingTourScreen> createState() => _OnboardingTourScreenState();
}

class _OnboardingTourScreenState extends State<OnboardingTourScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  
  late AnimationController _iconAnimationController;
  late Animation<double> _iconScaleAnimation;
  late Animation<double> _iconRotationAnimation;

  // Slide data for cleaner code
  static const List<_SlideData> _slides = [
    _SlideData(
      icon: Icons.auto_stories,
      gradient: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
      titleKey: 'onboarding_welcome_title',
      descKey: 'onboarding_welcome_desc',
      features: ['feature_organize', 'feature_discover', 'feature_share'],
    ),
    _SlideData(
      icon: Icons.library_books,
      gradient: [Color(0xFF10B981), Color(0xFF059669)],
      titleKey: 'onboarding_books_title',
      descKey: 'onboarding_books_desc',
      features: ['feature_scan', 'feature_search', 'feature_manual'],
    ),
    _SlideData(
      icon: Icons.cloud_sync,
      gradient: [Color(0xFFF59E0B), Color(0xFFD97706)],
      titleKey: 'onboarding_network_title',
      descKey: 'onboarding_network_desc',
      features: ['feature_connect', 'feature_borrow', 'feature_track'],
    ),
    _SlideData(
      icon: Icons.insights,
      gradient: [Color(0xFFEC4899), Color(0xFFDB2777)],
      titleKey: 'onboarding_stats_title',
      descKey: 'onboarding_stats_desc',
      features: ['feature_stats', 'feature_goals', 'feature_history'],
    ),
  ];

  int get _totalPages => _slides.length;

  @override
  void initState() {
    super.initState();
    _iconAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _iconScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _iconAnimationController,
        curve: Curves.elasticOut,
      ),
    );
    
    _iconRotationAnimation = Tween<double>(begin: -0.1, end: 0.0).animate(
      CurvedAnimation(
        parent: _iconAnimationController,
        curve: Curves.easeOut,
      ),
    );
    
    _iconAnimationController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _iconAnimationController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _goToPage(_currentPage + 1);
    } else {
      _finishTour();
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _goToPage(_currentPage - 1);
    }
  }

  void _finishTour() {
    WizardService.markOnboardingTourSeen();
    Navigator.of(context).pop();
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    _iconAnimationController.reset();
    _iconAnimationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final currentSlide = _slides[_currentPage];
    
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: currentSlide.gradient,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  itemCount: _totalPages,
                  itemBuilder: (context, index) => _buildSlide(_slides[index]),
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back button (hidden on first page)
          AnimatedOpacity(
            opacity: _currentPage > 0 ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IconButton(
              onPressed: _currentPage > 0 ? _previousPage : null,
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            ),
          ),
          // Step indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_currentPage + 1} / $_totalPages',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          // Skip button
          TextButton(
            onPressed: _finishTour,
            child: Text(
              TranslationService.translate(context, 'onboarding_skip'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlide(_SlideData slide) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          // Animated icon
          AnimatedBuilder(
            animation: _iconAnimationController,
            builder: (context, child) {
              return Transform.scale(
                scale: _iconScaleAnimation.value,
                child: Transform.rotate(
                  angle: _iconRotationAnimation.value,
                  child: child,
                ),
              );
            },
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Icon(
                slide.icon,
                size: 70,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 40),
          // Title
          Text(
            TranslationService.translate(context, slide.titleKey),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 20),
          // Description
          Text(
            TranslationService.translate(context, slide.descKey),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              color: Colors.white.withValues(alpha: 0.9),
              height: 1.6,
            ),
          ),
          const SizedBox(height: 36),
          // Feature chips
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: slide.features.map((featureKey) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getFeatureIcon(featureKey),
                      size: 18,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      TranslationService.translate(context, featureKey),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  IconData _getFeatureIcon(String featureKey) {
    switch (featureKey) {
      case 'feature_organize': return Icons.folder_outlined;
      case 'feature_discover': return Icons.explore_outlined;
      case 'feature_share': return Icons.share_outlined;
      case 'feature_scan': return Icons.qr_code_scanner;
      case 'feature_search': return Icons.search;
      case 'feature_manual': return Icons.edit_outlined;
      case 'feature_connect': return Icons.link;
      case 'feature_borrow': return Icons.swap_horiz;
      case 'feature_track': return Icons.track_changes;
      case 'feature_stats': return Icons.bar_chart;
      case 'feature_goals': return Icons.flag_outlined;
      case 'feature_history': return Icons.history;
      default: return Icons.check_circle_outline;
    }
  }

  Widget _buildFooter() {
    final isLastPage = _currentPage == _totalPages - 1;

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Progress dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_totalPages, (index) {
              final isActive = index == _currentPage;
              return GestureDetector(
                onTap: () => _goToPage(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isActive ? 32 : 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),
          // Action button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _nextPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _slides[_currentPage].gradient[0],
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isLastPage
                        ? TranslationService.translate(context, 'onboarding_finish')
                        : TranslationService.translate(context, 'onboarding_next'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (!isLastPage) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward, size: 20),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Swipe hint
          Text(
            TranslationService.translate(context, 'onboarding_swipe_hint'),
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideData {
  final IconData icon;
  final List<Color> gradient;
  final String titleKey;
  final String descKey;
  final List<String> features;

  const _SlideData({
    required this.icon,
    required this.gradient,
    required this.titleKey,
    required this.descKey,
    required this.features,
  });
}
