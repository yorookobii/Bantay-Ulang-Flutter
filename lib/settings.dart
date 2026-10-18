import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'privacy_policy.dart';
import 'terms_and_conditions.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4FAF9),
    appBar: AppBar(
      title: Text(
        'Settings',
        style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600),
      ),
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF0F766E),
      surfaceTintColor: Colors.transparent,
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'About Bantay Ulang',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Aquaponics monitoring and management for freshwater prawn '
                  '(Ulang) cultivation and plant growth.',
                  style: GoogleFonts.poppins(fontSize: 14, height: 1.6),
                ),
                const SizedBox(height: 24),
                Card(
                  color: Colors.white,
                  child: ListTile(
                    key: const Key('settings_privacy_policy'),
                    leading: const Icon(
                      Icons.privacy_tip_outlined,
                      color: Color(0xFF0F766E),
                    ),
                    title: Text('Privacy Policy', style: GoogleFonts.poppins()),
                    subtitle: Text(
                      'Your information, permissions, and deletion requests',
                      style: GoogleFonts.poppins(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        settings: const RouteSettings(name: '/privacy'),
                        builder: (_) => const PrivacyPolicyPage(),
                      ),
                    ),
                  ),
                ),
                Card(
                  color: Colors.white,
                  child: ListTile(
                    key: const Key('settings_terms_and_conditions'),
                    leading: const Icon(
                      Icons.description_outlined,
                      color: Color(0xFF0F766E),
                    ),
                    title: Text(
                      'Terms and Conditions',
                      style: GoogleFonts.poppins(),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        settings: const RouteSettings(name: '/terms'),
                        builder: (_) => const TermsAndConditionsPage(),
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Notifications',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Manage Bantay Ulang alerts and task notifications in your '
                  'device\'s app notification settings.',
                  style: GoogleFonts.poppins(fontSize: 14, height: 1.6),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
