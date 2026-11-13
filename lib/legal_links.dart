import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';

Future<void> openLegalLink(BuildContext context, String path) async {
  final base = SelfTextApi.configuredUrl.isNotEmpty
      ? SelfTextApi.configuredUrl
      : 'https://selftext-api.vercel.app';
  final uri = Uri.parse('$base$path');
  try {
    if (uri.scheme != 'https' ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('No browser');
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Open $uri in your browser.')));
    }
  }
}

class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    children: [
      TextButton(
        onPressed: () => openLegalLink(context, '/support'),
        child: const Text('Help & support'),
      ),
      TextButton(
        onPressed: () => openLegalLink(context, '/privacy'),
        child: const Text('Privacy policy'),
      ),
      TextButton(
        onPressed: () => openLegalLink(context, '/terms'),
        child: const Text('Terms'),
      ),
      TextButton(
        onPressed: () => openLegalLink(context, '/delete-account'),
        child: const Text('Delete account online'),
      ),
    ],
  );
}

Future<bool> confirmAiConsent(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Enable optional AI?'),
        content: const SingleChildScrollView(
          child: Text(
            'I am 18 or older. I agree to send relevant messages and saved content to Google Gemini for AI features. Free Gemini inputs and responses may be reviewed and used to improve Google products. I will not submit confidential or sensitive personal information. AI can misunderstand dates and tasks. I can turn AI off in Profile.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => openLegalLink(c, '/privacy'),
            child: const Text('Privacy details'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('I agree — enable AI'),
          ),
        ],
      ),
    ) ??
    false;
