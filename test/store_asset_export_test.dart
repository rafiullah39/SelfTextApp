import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'export code-rendered store branding',
    () async {
      final font = FontLoader('DancingScript')
        ..addFont(
          File(
            'assets/fonts/DancingScript.ttf',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await font.load();
      final sans = FontLoader('StoreSans')
        ..addFont(
          File(
            'C:/Windows/Fonts/segoeui.ttf',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await sans.load();
      void logo(ui.Canvas c, double x, double y, double size) {
        c.save();
        c.translate(x, y);
        c.scale(size / 108);
        c.drawRRect(
          ui.RRect.fromRectAndRadius(
            const ui.Rect.fromLTWH(0, 0, 108, 108),
            const ui.Radius.circular(25),
          ),
          ui.Paint()..color = const ui.Color(0xff007f65),
        );
        final bubble = ui.Path()
          ..moveTo(24, 27)
          ..lineTo(84, 27)
          ..lineTo(84, 72)
          ..lineTo(48, 72)
          ..lineTo(30, 85)
          ..lineTo(30, 72)
          ..lineTo(24, 72)
          ..close();
        c.drawPath(bubble, ui.Paint()..color = const ui.Color(0xffd9f4df));
        c.drawPath(
          ui.Path()
            ..moveTo(40, 48)
            ..lineTo(50, 59)
            ..lineTo(72, 38),
          ui.Paint()
            ..color = const ui.Color(0xff007f65)
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 7
            ..strokeCap = ui.StrokeCap.round
            ..strokeJoin = ui.StrokeJoin.round,
        );
        c.restore();
      }

      void text(
        ui.Canvas c,
        String value,
        double x,
        double y,
        double size, {
        bool script = false,
        int color = 0xffffffff,
      }) {
        final p =
            (ui.ParagraphBuilder(
                    ui.ParagraphStyle(
                      fontFamily: script ? 'DancingScript' : 'StoreSans',
                      fontSize: size,
                    ),
                  )
                  ..pushStyle(ui.TextStyle(color: ui.Color(color)))
                  ..addText(value))
                .build()
              ..layout(const ui.ParagraphConstraints(width: 900));
        c.drawParagraph(p, ui.Offset(x, y));
      }

      Future<void> save(
        String name,
        int width,
        int height,
        void Function(ui.Canvas) draw,
      ) async {
        final recorder = ui.PictureRecorder();
        draw(ui.Canvas(recorder));
        final picture = recorder.endRecording();
        final image = await picture.toImage(width, height);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('../dist/play-store/store-assets/$name');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      }

      await save('icon-512.png', 512, 512, (c) {
        c.drawRect(
          const ui.Rect.fromLTWH(0, 0, 512, 512),
          ui.Paint()..color = const ui.Color(0xff007f65),
        );
        logo(c, 0, 0, 512);
      });
      await save('feature-1024x500.png', 1024, 500, (c) {
        const bounds = ui.Rect.fromLTWH(0, 0, 1024, 500);
        c.drawRect(
          bounds,
          ui.Paint()
            ..shader = ui.Gradient.linear(
              const ui.Offset(0, 0),
              const ui.Offset(1024, 500),
              [const ui.Color(0xff051e22), const ui.Color(0xff0d795f)],
            ),
        );
        logo(c, 70, 68, 85);
        text(c, 'SelfText', 180, 64, 76, script: true);
        text(c, 'Say it. Type it.', 70, 210, 52);
        text(c, 'Remember it.', 70, 274, 52);
        text(
          c,
          'Reminders  /  Alarms  /  Notes',
          72,
          403,
          24,
          color: 0xffd9f4df,
        );
        c.drawCircle(
          const ui.Offset(810, 251),
          115,
          ui.Paint()..color = const ui.Color(0xff46f0d2).withValues(alpha: .14),
        );
        c.drawCircle(
          const ui.Offset(810, 251),
          89,
          ui.Paint()
            ..color = const ui.Color(0xff46f0d2)
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 5,
        );
        c.drawPath(
          ui.Path()
            ..moveTo(810, 198)
            ..lineTo(810, 251)
            ..lineTo(852, 275),
          ui.Paint()
            ..color = const ui.Color(0xffffffff)
            ..strokeWidth = 7
            ..strokeCap = ui.StrokeCap.round
            ..style = ui.PaintingStyle.stroke,
        );
      });
    },
    skip: Platform.environment['SELFTEXT_EXPORT_STORE_ASSETS'] != '1',
  );
}
