import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/widgets/common/floating_nav_bar.dart';

const items = [
  NavItemData(
    icon: Icons.movie_outlined,
    selectedIcon: Icons.movie,
    label: '片库',
  ),
  NavItemData(
    icon: Icons.casino_outlined,
    selectedIcon: Icons.casino,
    label: '抽片',
  ),
  NavItemData(
    icon: Icons.history_outlined,
    selectedIcon: Icons.history,
    label: '观影',
  ),
  NavItemData(
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    label: '设置',
  ),
];

void main() {
  testWidgets('drag previews the selection and switches only on release', (
    tester,
  ) async {
    var selected = 0;
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: FloatingNavBar(
                currentIndex: selected,
                items: items,
                onSelected: (index) => setState(() {
                  selected = index;
                  calls++;
                }),
              ),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('片库')),
    );
    await gesture.moveTo(tester.getCenter(find.text('设置')));
    await tester.pump();
    expect(selected, 0);
    expect(calls, 0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, 3);
    expect(calls, 1);
    await tester.drag(find.text('设置'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(selected, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'rapid navigation selects the last destination and keeps safe area',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: StatefulBuilder(
            builder: (context, setState) => MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 640),
                viewPadding: EdgeInsets.only(bottom: 34),
                textScaler: TextScaler.linear(2),
              ),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: FloatingNavBar(
                    currentIndex: selected,
                    items: items,
                    onSelected: (index) => setState(() => selected = index),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('设置'));
      await tester.pump(const Duration(milliseconds: 30));
      await tester.tap(find.text('抽片'));
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(tester.getBottomLeft(find.text('抽片')).dy, lessThan(640 - 34));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keyboard hides dock and reduced motion settles immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              disableAnimations: true,
              viewInsets: EdgeInsets.only(bottom: 260),
            ),
            child: FloatingNavBar(
              currentIndex: 0,
              items: items,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('片库'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
