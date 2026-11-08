import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:random_movie/models/annual_review.dart';
import 'package:random_movie/models/movie.dart';
import 'package:random_movie/models/viewing_session.dart';
import 'package:random_movie/services/storage_service.dart';
import 'package:random_movie/widgets/common/common_widgets.dart';

class AnnualReviewPage extends StatefulWidget {
  final StorageService? storage;
  const AnnualReviewPage({super.key, this.storage});
  @override
  State<AnnualReviewPage> createState() => _AnnualReviewPageState();
}

class _AnnualReviewPageState extends State<AnnualReviewPage> {
  final _posterKey = GlobalKey();
  late Future<void> _future;
  List<Movie> _movies = [];
  List<ViewingSession> _sessions = [];
  late List<int> _years;
  int _year = DateTime.now().year;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _load() async {
    final storage = widget.storage ?? StorageService();
    _movies = await storage.getAllMoviesForBackup();
    _sessions = await storage.getAllSessionsForBackup();
    _years = {
      DateTime.now().year,
      ..._sessions.map((s) => s.watchedAt.toLocal().year),
    }.toList()..sort((a, b) => b.compareTo(a));
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    ui.Image? image;
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary =
          _posterKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/pianke_annual_$_year.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      if (!mounted) return;
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'image/png'),
      ], subject: '我的 $_year 观影回顾');
    } catch (_) {
      if (mounted) AppToast.error(context, '生成图片失败，请重试');
    } finally {
      image?.dispose();
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('年度回顾')),
    body: FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ErrorState(
            message: '无法读取本地记录',
            onRetry: () => setState(() => _future = _load()),
          );
        }
        final review = AnnualReview.build(_year, _movies, _sessions);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<int>(
              initialValue: _year,
              decoration: const InputDecoration(labelText: '年份'),
              items: [
                for (final year in _years)
                  DropdownMenuItem(value: year, child: Text('$year 年')),
              ],
              onChanged: _sharing
                  ? null
                  : (year) => setState(() => _year = year!),
            ),
            const SizedBox(height: 16),
            RepaintBoundary(
              key: _posterKey,
              child: _ReviewPoster(review: review),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sharing ? null : _share,
              icon: const Icon(Icons.ios_share),
              label: Text(_sharing ? '生成中…' : '保存或分享回顾图片'),
            ),
            const SizedBox(height: 12),
            const Text(
              '只统计本地已保存的观影记录。图片包含影片名称和汇总数字，不含短评、同伴或账号。',
              textAlign: TextAlign.center,
            ),
          ],
        );
      },
    ),
  );
}

class _ReviewPoster extends StatelessWidget {
  final AnnualReview review;
  const _ReviewPoster({required this.review});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('片刻 · ${review.year}', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text('我的观影回顾', style: theme.textTheme.titleLarge),
            const Divider(height: 32),
            Text(
              '${review.sessionCount} 次观影 · ${review.activeDays} 个观影日',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              '${review.movieCount} 部电影 · ${review.seriesCount} 部剧集\n其中 ${review.rewatchCount} 条记录标记为重看',
            ),
            const SizedBox(height: 24),
            Text('常看类型', style: theme.textTheme.titleMedium),
            Text(
              review.genres.isEmpty
                  ? '还没有类型记录'
                  : review.genres
                        .map((e) => '${e.key} ${e.value}部')
                        .join(' · '),
            ),
            const SizedBox(height: 24),
            Text('我的评分分布', style: theme.textTheme.titleMedium),
            _RatingChart(values: review.ratingBins),
            const SizedBox(height: 24),
            Text('高分记忆', style: theme.textTheme.titleMedium),
            if (review.highlights.isEmpty) const Text('还没有当次评分，留下下一次观影的感受吧'),
            for (final movie in review.highlights)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('· ${movie.title}'),
              ),
            const Divider(height: 32),
            Text(
              '电影、剧集按作品去重；次数和评分按观影记录统计。\n剧集记录不代表追完，不推算分集数或观看时长。',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingChart extends StatelessWidget {
  final List<int> values;
  const _RatingChart({required this.values});
  @override
  Widget build(BuildContext context) {
    final labels = [
      for (var i = 0; i < 5; i++) '${i == 0 ? '0–1' : '$i–${i + 1}'}星',
    ];
    final style = Theme.of(context).textTheme.bodySmall!;
    final scaler = MediaQuery.textScalerOf(context);
    return Semantics(
      label: [
        for (var i = 0; i < 5; i++) '${labels[i]} ${values[i]}次',
      ].join('，'),
      child: SizedBox(
        height: 5 * scaler.scale(30),
        width: double.infinity,
        child: CustomPaint(
          painter: _RatingPainter(
            values,
            labels,
            style,
            scaler,
            Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _RatingPainter extends CustomPainter {
  final List<int> values;
  final List<String> labels;
  final TextStyle style;
  final TextScaler scaler;
  final Color color;
  _RatingPainter(this.values, this.labels, this.style, this.scaler, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final texts = [
      for (final label in [...labels, ...values.map((v) => '$v')])
        TextPainter(
          text: TextSpan(text: label, style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout(),
    ];
    final left =
        texts.take(5).map((p) => p.width).reduce((a, b) => a > b ? a : b) + 8;
    final right =
        texts.skip(5).map((p) => p.width).reduce((a, b) => a > b ? a : b) + 8;
    final barWidth = (size.width - left - right).clamp(0.0, size.width);
    final maximum = values.fold<int>(1, (a, b) => a > b ? a : b);
    final row = size.height / 5;
    for (var i = 0; i < 5; i++) {
      final y = row * i;
      texts[i].paint(canvas, Offset(0, y + (row - texts[i].height) / 2));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, y + row * .3, barWidth, row * .4),
          const Radius.circular(3),
        ),
        Paint()..color = color.withValues(alpha: .1),
      );
      if (values[i] > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              left,
              y + row * .3,
              barWidth * values[i] / maximum,
              row * .4,
            ),
            const Radius.circular(3),
          ),
          Paint()..color = color,
        );
      }
      texts[i + 5].paint(
        canvas,
        Offset(left + barWidth + 8, y + (row - texts[i + 5].height) / 2),
      );
    }
    for (final text in texts) {
      text.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant _RatingPainter old) =>
      old.values != values ||
      old.style != style ||
      old.scaler != scaler ||
      old.color != color;
}
