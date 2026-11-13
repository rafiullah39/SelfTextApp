import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VoiceCapture {
  static const channel = MethodChannel('selftext/voice');
  static const events = EventChannel('selftext/voice-events');
  static Future<String?> capture(BuildContext context) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voice capture is available in the Android app.'),
        ),
      );
      return null;
    }
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _VoiceSheet(),
    );
  }
}

class _VoiceSheet extends StatefulWidget {
  const _VoiceSheet();
  @override
  State<_VoiceSheet> createState() => _VoiceState();
}

class _VoiceState extends State<_VoiceSheet> {
  String language = 'auto';
  bool listening = false, stopping = false;
  String? error;
  final transcript = TextEditingController();
  StreamSubscription<dynamic>? stream;
  @override
  void initState() {
    super.initState();
    stream = VoiceCapture.events.receiveBroadcastStream().listen(
      (event) {
        if (mounted && listening) {
          setState(() => transcript.text = event as String);
        }
      },
      onError: (Object e) {
        if (mounted) {
          setState(
            () => error =
                'Live transcription is unavailable. Stop to review the captured text.',
          );
        }
      },
    );
  }

  Future<void> start() async {
    setState(() {
      listening = true;
      stopping = false;
      error = null;
      transcript.clear();
    });
    try {
      final text = await VoiceCapture.channel.invokeMethod<String>(
        'recognize',
        {'locale': language},
      );
      if (!mounted) return;
      setState(() {
        listening = false;
        stopping = false;
        if (text != null) transcript.text = text;
      });
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          listening = false;
          stopping = false;
          error =
              e.message ?? 'Voice capture failed. You can edit the text below.';
        });
      }
    }
  }

  Future<void> stop() async {
    setState(() => stopping = true);
    try {
      await VoiceCapture.channel.invokeMethod<void>('stop');
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  @override
  void dispose() {
    stream?.cancel();
    if (listening) VoiceCapture.channel.invokeMethod<void>('cancel');
    transcript.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  listening ? Icons.mic : Icons.graphic_eq,
                  size: 32,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    listening
                        ? 'Listening until you stop'
                        : 'Say it. Clear your mind.',
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cancel voice',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Pause naturally. Tap Stop when you are finished, then review your words before sending.',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: language,
              decoration: const InputDecoration(labelText: 'Speech language'),
              items: const [
                DropdownMenuItem(
                  value: 'auto',
                  child: Text('Auto · English / Urdu'),
                ),
                DropdownMenuItem(value: 'en-US', child: Text('English')),
                DropdownMenuItem(value: 'ur-PK', child: Text('اردو · Urdu')),
              ],
              onChanged: listening
                  ? null
                  : (v) => setState(() => language = v!),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: transcript,
              readOnly: listening,
              minLines: 3,
              maxLines: 6,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: listening ? 'Live transcript' : 'Review your words',
                hintText: 'Your words will appear here…',
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: listening
                  ? FilledButton.icon(
                      onPressed: stopping ? null : stop,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: Text(stopping ? 'Finishing…' : 'Stop recording'),
                    )
                  : FilledButton.icon(
                      onPressed: start,
                      icon: const Icon(Icons.mic),
                      label: Text(
                        transcript.text.isEmpty
                            ? 'Start speaking'
                            : 'Record again',
                      ),
                    ),
            ),
            if (!listening && transcript.text.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, transcript.text.trim()),
                  icon: const Icon(Icons.check),
                  label: const Text('Use this text'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Your phone’s speech service may use the internet. Choose Urdu explicitly if Auto misses it.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}
