import 'dart:async';
import 'package:flutter/material.dart';
import 'store.dart';

class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key, required this.store, this.record});
  final SelfTextStore store;
  final ProductivityRecord? record;
  @override
  State<FocusScreen> createState() => _FocusState();
}

class _FocusState extends State<FocusScreen> {
  int minutes = 25, remaining = 25 * 60;
  DateTime? end;
  Timer? ticker;
  bool finished = false;
  void start() {
    end = DateTime.now().add(Duration(seconds: remaining));
    ticker?.cancel();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final seconds = end!.difference(DateTime.now()).inSeconds;
      setState(() {
        remaining = seconds.clamp(0, minutes * 60);
        if (remaining == 0) {
          finished = true;
          end = null;
          ticker?.cancel();
        }
      });
    });
    setState(() {});
  }

  void pause() {
    ticker?.cancel();
    setState(() => end = null);
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('A little focus')),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                widget.record?.title ?? 'One thing at a time.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'An in-app focus timer. Take a breath, then begin.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 35),
              SizedBox(
                width: 230,
                height: 230,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: 1 - remaining / (minutes * 60),
                        strokeWidth: 12,
                        backgroundColor: const Color(0xffd9f4df),
                      ),
                    ),
                    Text(
                      finished
                          ? 'Nice work!'
                          : '${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 35),
              if (end == null && !finished)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in [15, 25, 45])
                      ChoiceChip(
                        label: Text('$m min'),
                        selected: minutes == m,
                        onSelected: (_) => setState(() {
                          minutes = m;
                          remaining = m * 60;
                        }),
                      ),
                  ],
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: finished
                    ? () {
                        setState(() {
                          finished = false;
                          remaining = minutes * 60;
                        });
                      }
                    : end == null
                    ? start
                    : pause,
                icon: Icon(end == null ? Icons.play_arrow : Icons.pause),
                label: Text(
                  finished
                      ? 'Another session'
                      : end == null
                      ? 'Start focusing'
                      : 'Pause',
                ),
              ),
              if (widget.record != null && !widget.record!.done)
                TextButton(
                  onPressed: () {
                    widget.store.toggle(widget.record!);
                    Navigator.pop(context);
                  },
                  child: const Text('Mark task completed'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
