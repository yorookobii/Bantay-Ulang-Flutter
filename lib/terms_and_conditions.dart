import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class TermsAndConditionsDocument {
  TermsAndConditionsDocument.fromJson(Map<String, dynamic> json)
    : appName = json['title'] as String,
      lastUpdated = json['lastUpdated'] as String,
      sections = (json['sections'] as List)
          .map(
            (value) => TermsAndConditionsSection.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList();

  final String appName;
  final String lastUpdated;
  final List<TermsAndConditionsSection> sections;

  static Future<TermsAndConditionsDocument> load() async =>
      TermsAndConditionsDocument.fromJson(
        jsonDecode(
              await rootBundle.loadString(
                'assets/terms/terms_and_conditions.json',
              ),
            )
            as Map<String, dynamic>,
      );
}

class TermsAndConditionsSection {
  TermsAndConditionsSection.fromJson(Map<String, dynamic> json)
    : title = json['title'] as String,
      paragraphs = List<String>.from(json['paragraphs'] as List);

  final String title;
  final List<String> paragraphs;
}

/// Public, bundled terms: opening it requires no account or network request.
class TermsAndConditionsPage extends StatefulWidget {
  const TermsAndConditionsPage({super.key});

  @override
  State<TermsAndConditionsPage> createState() => _TermsAndConditionsPageState();
}

class _TermsAndConditionsPageState extends State<TermsAndConditionsPage> {
  late Future<TermsAndConditionsDocument> _document;

  @override
  void initState() {
    super.initState();
    _document = TermsAndConditionsDocument.load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4FAF9),
    appBar: AppBar(
      title: Text(
        'Terms and Conditions',
        style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600),
      ),
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF0F766E),
      surfaceTintColor: Colors.transparent,
    ),
    body: SafeArea(
      child: FutureBuilder<TermsAndConditionsDocument>(
        future: _document,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('The terms and conditions could not be opened.'),
                    TextButton(
                      onPressed: () => setState(() {
                        _document = TermsAndConditionsDocument.load();
                      }),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final policy = snapshot.data!;
          final bodyStyle = GoogleFonts.poppins(
            fontSize: 14,
            height: 1.65,
            color: const Color(0xFF374151),
          );
          return SelectionArea(
            child: SingleChildScrollView(
              key: const Key('terms_and_conditions_scroll'),
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        policy.appName,
                        style: GoogleFonts.poppins(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F766E),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Last updated: ${policy.lastUpdated}',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 20),
                      for (final section in policy.sections) ...[
                        Text(
                          section.title,
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0F766E),
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final paragraph in section.paragraphs) ...[
                          Text(paragraph, style: bodyStyle),
                          const SizedBox(height: 12),
                        ],
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
