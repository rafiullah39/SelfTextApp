import 'package:flutter/material.dart';
import 'store.dart';

class DaySnapshot extends StatelessWidget {
  const DaySnapshot({
    super.key,
    required this.store,
    required this.onPlan,
    required this.onFocus,
  });
  final SelfTextStore store;
  final VoidCallback onPlan, onFocus;
  @override
  Widget build(BuildContext context) {
    final day = store.calendarNow;
    final tasks = store
        .onDay(day)
        .where((r) => r.kind == RecordKind.task)
        .toList();
    final complete = tasks.where((r) => r.done).length;
    final open = store.tasks
        .where((r) => !r.done && r.status != 'cancelled')
        .length;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff303e45), Color(0xff222231)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18007f65),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MAKE ROOM FOR WHAT MATTERS',
            style: TextStyle(
              color: Color(0xffcdebdc),
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      day.hour < 12
                          ? 'Good morning.'
                          : day.hour < 17
                          ? 'Good afternoon.'
                          : 'Slow down. Stay clear.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 27,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$complete of ${tasks.length} today · $open open tasks',
                      style: const TextStyle(color: Color(0xffd6eade)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: tasks.isEmpty ? 0 : complete / tasks.length,
                        strokeWidth: 5,
                        color: const Color(0xff46f0d2),
                        backgroundColor: Colors.white24,
                      ),
                    ),
                    const Icon(
                      Icons.spa_outlined,
                      color: Color(0xff46f0d2),
                      size: 28,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff46f0d2),
                  foregroundColor: const Color(0xff073d30),
                ),
                onPressed: onPlan,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Build a plan'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                onPressed: onFocus,
                icon: const Icon(Icons.timelapse, size: 18),
                label: const Text('Focus'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
