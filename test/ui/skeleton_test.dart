// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/widgets/common/skeleton.dart';
import 'package:random_movie/widgets/movie/poster_tint.dart';

Widget _host({required Widget child, bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  group('T11 骨架屏', () {
    testWidgets('骨架网格渲染出与 count 相同的占位卡', (tester) async {
      await tester.pumpWidget(
        _host(
          child: const LibrarySkeletonGrid(count: 5),
        ),
      );
      await tester.pump(Motion.shimmer * 0.3);

      expect(find.byType(SkeletonPosterCard), findsNWidgets(5));
    });

    testWidgets('移除动效时不创建循环动画（pumpAndSettle 能结束）', (tester) async {
      await tester.pumpWidget(
        _host(
          disableAnimations: true,
          child: const LibrarySkeletonGrid(count: 4),
        ),
      );
      // 若仍在跑无限循环动画，这里会超时——正好证明「移除动效」被遵守。
      await tester.pumpAndSettle();
      expect(find.byType(SkeletonPosterCard), findsNWidgets(4));
    });

    testWidgets('正常模式下高光是一段可推进的动画', (tester) async {
      await tester.pumpWidget(
        _host(
          child: const LibrarySkeletonGrid(count: 2),
        ),
      );
      final first = ShimmerScope.progressOf(
        tester.element(find.byType(SkeletonPosterCard).first),
      );
      await tester.pump(Motion.shimmer * 0.25);
      final second = ShimmerScope.progressOf(
        tester.element(find.byType(SkeletonPosterCard).first),
      );
      expect(second, isNot(equals(first)), reason: '高光进度应当随时间变化');
      // 收尾：避免无限循环动画让测试结束时仍有活动 ticker。
      await tester.pumpWidget(_host(child: const SizedBox()));
    });

    testWidgets('骨架与真实网格用同一套网格参数（避免加载完成跳动）', (tester) async {
      await tester.pumpWidget(_host(child: const LibrarySkeletonGrid()));
      final skeletonGrid = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          skeletonGrid.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent;

      expect(delegate.maxCrossAxisExtent, 190);
      expect(delegate.crossAxisSpacing, Spacing.md);
      expect(delegate.mainAxisSpacing, Spacing.lg);
    });

    testWidgets('大字体下骨架卡比例跟随切换', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: const Scaffold(body: LibrarySkeletonGrid(count: 2)),
          ),
        ),
      );
      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent;
      // 网格改用 mainAxisExtent 固定行高（滚动时省掉逐项测量），
      // 大字体下用更高的行高，与真实网格 _libraryCardExtent 保持一致。
      // 两条路径的取值必须同步，否则骨架 → 真数据会跳动。
      expect(delegate.mainAxisExtent, 362.5);
    });
  });

  group('T11 海报占位色', () {
    test('没有海报也没有 id 时返回 null（交给中性色）', () {
      expect(PosterTint.of(Movie(id: '', title: '空')), isNull);
    });

    test('派生色对同一部影片稳定', () {
      final movie = Movie(id: 'm1', title: '影片', poster: 'https://e.com/a.jpg');
      final a = PosterTint.of(movie);
      final b = PosterTint.of(movie);
      expect(a, isNotNull);
      expect(a, b);
    });

    test('不同影片派生色不同', () {
      final a = PosterTint.of(
        Movie(id: 'a', title: 'A', poster: 'https://e.com/a.jpg'),
      );
      final b = PosterTint.of(
        Movie(id: 'b', title: 'B', poster: 'https://e.com/b.jpg'),
      );
      expect(a, isNot(b));
    });

    test('已存海报主色优先于派生色', () {
      const stored = 0xFF123456;
      final movie = Movie(
        id: 'm1',
        title: '影片',
        poster: 'https://e.com/a.jpg',
        posterColor: stored,
      );
      expect(PosterTint.of(movie), const Color(stored));
    });

    test('派生色饱和度与亮度被压低，不会抢文字对比', () {
      final color = PosterTint.derived('some-seed');
      final hsl = HSLColor.fromColor(color);
      expect(hsl.saturation, lessThan(0.5));
      expect(hsl.lightness, inInclusiveRange(0.3, 0.6));
    });
  });

  group('T11 海报主色随备份往返', () {
    test('Movie.toJson / fromJson 保留 posterColor', () {
      final movie = Movie(
        id: 'm',
        title: '影片',
        posterColor: 0xFF00FF00,
      );
      final restored = Movie.fromJson(movie.toJson());
      expect(restored.posterColor, 0xFF00FF00);
    });

    test('没有主色时序列化为 null，不影响旧备份读取', () {
      final movie = Movie(id: 'm', title: '影片');
      expect(movie.toJson()['posterColor'], isNull);
      expect(Movie.fromJson(movie.toJson()).posterColor, isNull);
    });
  });
}
