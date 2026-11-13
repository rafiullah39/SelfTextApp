import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:selftext/app.dart';
import 'package:selftext/store.dart';
import 'sync_test.dart' show MemorySessionStorage;

void main(){
  final enabled=Platform.environment['SELFTEXT_DESIGN_PREVIEW']=='1';
  final playPreview=Platform.environment['SELFTEXT_PLAY_PREVIEW']=='1';
  setUpAll(()async{
    if(!enabled)return;
    for(final font in {'Roboto':'C:/Windows/Fonts/segoeui.ttf','DancingScript':'assets/fonts/DancingScript.ttf','MaterialIcons':'D:/Android/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'}.entries){
      final loader=FontLoader(font.key)..addFont(File(font.value).readAsBytes().then(ByteData.sublistView));await loader.load();
    }
  });
  testWidgets('render the simplified product in both themes',(tester)async{
    tester.view.physicalSize=Size(390,playPreview?780:844);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final store=SelfTextStore(sessionStorage:MemorySessionStorage())..onboarded=true;
    addTearDown(store.dispose);
    final due=DateTime.now().add(const Duration(hours:4));
    store.createRecord(title:'Submit my assignment',kind:RecordKind.task,chatId:'inbox',startAt:due.subtract(const Duration(hours:2)),dueAt:due,reminderTimes:[due.subtract(const Duration(hours:2)),due.subtract(const Duration(minutes:10)),due]);
    store.createRecord(title:'A quick note',kind:RecordKind.note,chatId:'inbox',body:'Bring my notebook and charger tomorrow.');
    for(final mode in ['light','dark']){
      await store.setAppearance(mode);
      await tester.pumpWidget(RepaintBoundary(key:const Key('preview'),child:SelfTextApp(store:store)));await tester.pumpAndSettle();
      for(final tab in ['Dashboard','Chats','Tasks','Calendar','Profile']){
        await tester.tap(find.widgetWithText(NavigationDestination,tab));await tester.pumpAndSettle();
        expect(tester.takeException(),isNull);
        final name=tab.replaceAll(' ','-').toLowerCase();
        final path=playPreview?'../../dist/play-store/screenshots/$mode-$name.png':'../../dist/ui-0.9.2-$mode-$name.png';
        await expectLater(find.byKey(const Key('preview')),matchesGoldenFile(path));
      }
    }
  },skip:!enabled);
}
