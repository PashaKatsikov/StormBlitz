import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player_profile.dart';
import '../relay/config/relay_config.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_transitions.dart';
import 'web_view_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  // Single source of truth — same URLs registered in App Store Connect.
  static String get privacyUrl => RelayConfig.privacyUrl;
  static String get supportUrl => RelayConfig.supportUrl;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<PlayerProfile>();

    return AppScaffold(
      title: 'SETTINGS',
      showBack: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _tile(
            context,
            icon: Icons.privacy_tip_outlined,
            color: AppColors.lightning,
            label: 'Privacy Policy',
            onTap: () => Navigator.of(context).push(
              AppTransitions.slideUp(
                WebViewScreen(title: 'Privacy Policy', url: privacyUrl),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _tile(
            context,
            icon: Icons.support_agent,
            color: AppColors.lightning,
            label: 'Support',
            onTap: () => Navigator.of(context).push(
              AppTransitions.slideUp(
                WebViewScreen(title: 'Support', url: supportUrl),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _tile(
            context,
            icon: Icons.delete_forever,
            color: AppColors.hpRed,
            label: 'Reset progress',
            onTap: () => _confirmReset(context, profile),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('Storm Blitz v1.0.0',
                style: AppTheme.body(12, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.panel.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.panelBorder),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: AppTheme.title(15))),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  void _confirmReset(BuildContext context, PlayerProfile profile) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.hpRed, width: 1.5),
        ),
        title: Text('Reset progress?', style: AppTheme.title(20)),
        content: Text(
          'All gold, cards, chests, relics and achievements will be lost forever.',
          style: AppTheme.body(14, color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('CANCEL',
                style: AppTheme.body(15, color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              profile.resetAll();
              Navigator.of(dialogContext).pop();
            },
            child: Text('RESET',
                style: AppTheme.body(15,
                    color: AppColors.hpRed, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
