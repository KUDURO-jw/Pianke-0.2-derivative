import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:random_movie/models/movie.dart';
import 'package:random_movie/providers/movie_provider.dart';
import 'package:random_movie/services/local_data_guard.dart';
import 'package:random_movie/services/storage_service.dart';
import 'package:random_movie/widgets/common/common_widgets.dart';
import 'package:random_movie/widgets/movie/viewing_session_editor.dart';

Future<void> showQuickViewingEntry(
  BuildContext context, {
  DateTime? date,
  StorageService? storage,
}) async {
  final owner = Object();
  LocalDataGuard.hold(owner);
  try {
    final provider = context.read<MovieProvider>();
    final movie = await showModalBottomSheet<Movie>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LocalMoviePicker(storage: storage ?? StorageService()),
    );
    if (movie == null || !context.mounted) return;
    final sessions = await provider.sessionsForMovie(movie.id);
    if (!context.mounted) return;
    final draft = await showViewingSessionEditor(
      context,
      movieId: movie.id,
      initialDate: date,
      defaultIsRewatch: sessions.isNotEmpty,
    );
    if (draft == null || !context.mounted) return;
    final saved = await provider.addViewingSession(draft);
    if (!context.mounted) return;
    if (saved == null) {
      AppToast.error(context, '记录失败，请重试');
    } else {
      AppToast.success(context, '已记录 ${movie.title}');
    }
  } catch (_) {
    if (context.mounted) AppToast.error(context, '无法读取或保存观影记录，请重试');
  } finally {
    LocalDataGuard.release(owner);
  }
}

class _LocalMoviePicker extends StatefulWidget {
  final StorageService storage;
  const _LocalMoviePicker({required this.storage});
  @override
  State<_LocalMoviePicker> createState() => _LocalMoviePickerState();
}

class _LocalMoviePickerState extends State<_LocalMoviePicker> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  List<Movie> _movies = [];
  String _query = '';
  bool _loading = false;
  bool _hasMore = true;
  bool _failed = false;
  int _revision = 0;
  static const _pageSize = 40;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 200 && _hasMore && !_loading) _load();
    });
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _failed = false;
      if (reset) _movies = [];
    });
    try {
      final next = await widget.storage.queryMovies(
        limit: _pageSize,
        offset: _movies.length,
        searchQuery: _query,
      );
      if (!mounted || revision != _revision) return;
      setState(() {
        _movies = [..._movies, ...next];
        _hasMore = next.length == _pageSize;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: Column(
          children: [
            Text('选择要记录的影片', style: Theme.of(context).textTheme.titleLarge),
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: '搜索本地片名、导演或演员',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                _revision++;
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 250), () {
                  _query = value.trim();
                  _load(reset: true);
                });
              },
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                itemCount: _movies.length + 1,
                itemBuilder: (context, index) {
                  if (index == _movies.length) {
                    if (_loading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (_failed) {
                      return TextButton(
                        onPressed: _load,
                        child: const Text('读取失败，重试'),
                      );
                    }
                    if (_movies.isEmpty) {
                      return const ListTile(
                        title: Text('没有找到影片'),
                        subtitle: Text('可先在片库添加影片，再补记观影。'),
                      );
                    }
                    return const SizedBox(height: 16);
                  }
                  final movie = _movies[index];
                  return ListTile(
                    title: Text(movie.title),
                    subtitle: Text(
                      [
                        movie.year,
                        movie.director,
                      ].where((v) => v.isNotEmpty).join(' · '),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(context, movie),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
