// widgets/bottom_navigation.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class BottomNavigationWidget extends StatefulWidget {
  final String activeTab;
  final Function(String) onTabChanged;
  final String userRole;

  const BottomNavigationWidget({
    Key? key,
    required this.activeTab,
    required this.onTabChanged,
    this.userRole = 'guest',
  }) : super(key: key);

  @override
  State<BottomNavigationWidget> createState() => _BottomNavigationWidgetState();
}

class _BottomNavigationWidgetState extends State<BottomNavigationWidget> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade200, width: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            _buildNavButton(
              icon: Icons.home_outlined,
              activeIcon: Icons.home,
              label: 'Home',
              tabKey: 'home',
            ),
            _buildNavButton(
              icon: Icons.history,
              label: 'History',
              tabKey: 'history',
            ),
            _buildCenterButton(),
            _buildNavButton(
              icon: Icons.description_outlined,
              label: 'Terms',
              tabKey: 'terms',
            ),
            _buildNavButton(
              icon: Icons.person_outline,
              activeIcon: Icons.person,
              label: 'Profile',
              tabKey: 'profile',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterButton() {
    if (widget.userRole == 'passenger' || widget.userRole == 'customer') {
      return _buildSpecialButton(
        'Lhokfood',
        Icons.restaurant_menu,
        'FOOD',
        Colors.orange,
      );
    } else if (widget.userRole == 'driver') {
      return _buildSpecialButton(
        'lhokdriver',
        Icons.motorcycle,
        'DRIVE',
        Colors.blue,
      );
    }
    return const Expanded(child: SizedBox());
  }

  Widget _buildSpecialButton(
    String tabKey,
    IconData icon,
    String label,
    Color color,
  ) {
    final isActive = widget.activeTab == tabKey;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTabChanged(tabKey);
        },
        child: Container(
          height: 48,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors:
                  isActive
                      ? [Colors.orange.shade300, Colors.orange.shade700]
                      : [Colors.orange.shade400, Colors.orange.shade600],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(height: 1),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    IconData? activeIcon,
    required String label,
    required String tabKey,
  }) {
    final isActive = widget.activeTab == tabKey;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTabChanged(tabKey);
        },
        child: Container(
          height: 70,
          color: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isActive ? (activeIcon ?? icon) : icon,
                size: 20,
                color: isActive ? Colors.orange.shade600 : Colors.grey.shade500,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color:
                      isActive ? Colors.orange.shade600 : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Page wrapper - Simplified
class PageWithBottomNav extends StatelessWidget {
  final Widget child;
  final String activeTab;
  final String userRole;

  const PageWithBottomNav({
    Key? key,
    required this.child,
    required this.activeTab,
    this.userRole = 'guest',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationWidget(
        activeTab: activeTab,
        userRole: userRole,
        onTabChanged: (tab) => _navigateToTab(context, tab),
      ),
    );
  }

  void _navigateToTab(BuildContext context, String tab) {
    final routes = {
      'home': userRole == 'driver' ? '/dashboard/driver' : '/dashboard',
      'history': '/history',
      'Lhokfood': '/Lhokfood',
      'lhokdriver': '/dashboard/driver',
      'profile': '/users/profile',
      'terms': '/terms',
    };

    final route = routes[tab] ?? '/dashboard';
    if (ModalRoute.of(context)?.settings.name != route) {
      context.push(route);
    }
  }
}
