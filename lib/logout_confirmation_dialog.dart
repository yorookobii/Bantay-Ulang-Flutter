import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LogoutConfirmationDialog extends StatefulWidget {
  final VoidCallback? onConfirm;

  const LogoutConfirmationDialog({super.key, this.onConfirm});

  @override
  State<LogoutConfirmationDialog> createState() =>
      _LogoutConfirmationDialogState();
}

class _LogoutConfirmationDialogState extends State<LogoutConfirmationDialog> {
  bool _closed = false;

  void _close(bool confirmed) {
    if (_closed || ModalRoute.of(context)?.isCurrent != true) return;
    _closed = true;
    Navigator.of(context).pop(confirmed);
    if (confirmed) widget.onConfirm?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFFFEE2E2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.logout_rounded,
              color: Color(0xFFEF4444),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            "Confirm Logout",
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
      content: Text(
        "Are you sure you want to log out?",
        style: GoogleFonts.poppins(
          fontSize: 14,
          color: const Color(0xFF64748B),
          height: 1.4,
        ),
      ),
      actions: [
        TextButton(
          key: const Key('logout_no_button'),
          onPressed: () => _close(false),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          child: Text(
            "No",
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
            ),
          ),
        ),
        ElevatedButton(
          key: const Key('logout_yes_button'),
          onPressed: () => _close(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            "Yes, Log Out",
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

Future<bool?> showLogoutConfirmationDialog(
  BuildContext context, {
  VoidCallback? onConfirm,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext dialogContext) =>
        LogoutConfirmationDialog(onConfirm: onConfirm),
  );
}
