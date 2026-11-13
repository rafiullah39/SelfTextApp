import 'package:flutter/material.dart';
import 'store.dart';

Future<void> reportProblem(
  BuildContext context,
  SelfTextStore store, {
  String? interpretationId,
}) async {
  if (!store.signedIn) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Sign in to send a report, or contact support from the help page.',
        ),
      ),
    );
    return;
  }
  final sent = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _FeedbackDialog(store: store, interpretationId: interpretationId),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Report received. Thank you for helping improve SelfText.',
        ),
      ),
    );
  }
}

class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog({required this.store, this.interpretationId});
  final SelfTextStore store;
  final String? interpretationId;
  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final description = TextEditingController();
  String category = 'other';
  String? error;
  bool busy = false;
  @override
  void dispose() {
    description.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (description.text.trim().length < 5) {
      setState(() => error = 'Please describe the issue in a few words.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.api.request('POST', '/feedback', {
        'category': category,
        'description': description.text.trim(),
        if (widget.interpretationId != null)
          'interpretation_id': widget.interpretationId,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Report a problem'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tell us about incorrect, unsafe or unwanted suggestions. Your description and this suggestion’s reference, when available, go to the SelfText developer.',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Issue'),
              items: const [
                DropdownMenuItem(
                  value: 'incorrect_time',
                  child: Text('Incorrect date or time'),
                ),
                DropdownMenuItem(
                  value: 'unsafe_content',
                  child: Text('Unsafe or offensive content'),
                ),
                DropdownMenuItem(
                  value: 'privacy',
                  child: Text('Privacy concern'),
                ),
                DropdownMenuItem(value: 'other', child: Text('Something else')),
              ],
              onChanged: busy ? null : (v) => setState(() => category = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: description,
              enabled: !busy,
              maxLength: 1000,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'What went wrong?',
                helperText:
                    'Do not include passwords or sensitive information.',
              ),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy ? null : send,
          child: Text(busy ? 'Sending…' : 'Send report'),
        ),
      ],
    ),
  );
}
