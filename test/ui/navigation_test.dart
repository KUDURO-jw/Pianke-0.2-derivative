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
  testWidgets(
    'selected destination stays enlarged and pressing lifts its lens',
    (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
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
      );
      AnimatedScale item(String label) => tester.widget<AnimatedScale>(
        find.byKey(ValueKey('dock-item-scale-$label')),
      );
      expect(item('片库').scale, greaterThan(1));
      expect(item('抽片').scale, 1);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('抽片')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(item('抽片').scale, greaterThan(item('片库').scale));
      expect(
        tester
            .widget<AnimatedScale>(
              find.byKey(const ValueKey('dock-lens-scale')),
            )
            .scale,
        greaterThan(1),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(item('抽片').scale, greaterThan(1));
      expect(item('片库').scale, 1);
      expect(tester.takeException(), isNull);
    },
  );
  for (final direction in TextDirection.values) {
    testWidgets('short flick is bounded to one neighbour in $direction', (
      tester,
    ) async {
      var selected = 2;
      final sign = direction == TextDirection.ltr ? 1.0 : -1.0;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: direction,
            child: StatefulBuilder(
              builder: (context, setState) => Scaffold(
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
      await tester.fling(
        find.text('观影'),
        Offset(-30 * sign, 0),
        4000,
        frameInterval: const Duration(milliseconds: 1),
      );
      await tester.pumpAndSettle();
      expect(selected, 1);
      await tester.fling(
        find.text('抽片'),
        Offset(30 * sign, 0),
        4000,
        frameInterval: const Duration(milliseconds: 1),
      );
      await tester.pumpAndSettle();
      expect(selected, 2);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'slow short movement stays put while the same fast movement advances one',
    (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
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
      );
      await tester.timedDrag(
        find.text('片库'),
        const Offset(30, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(selected, 0);
      await tester.timedDrag(
        find.text('片库'),
        const Offset(30, 0),
        const Duration(milliseconds: 50),
      );
      await tester.pumpAndSettle();
      expect(selected, 1);
    },
  );
  testWidgets(
    'short fast fling travels beyond release position and clamps at ends',
    (tester) async {
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
      await tester.fling(
        find.text('片库'),
        const Offset(30, 0),
        1200,
        frameInterval: const Duration(milliseconds: 5),
      );
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(calls, 1);
      await tester.fling(
        find.text(items[selected].label),
        const Offset(-30, 0),
        2400,
        frameInterval: const Duration(milliseconds: 5),
      );
      await tester.pumpAndSettle();
      expect(selected, 0);
      expect(calls, 2);
      expect(tester.takeException(), isNull);
    },
  );
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
