// Independently implemented for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:random_movie/config/api_config.dart';

/// A shared, bounded-decode poster. Badges and labels never join its Hero flight.
class MoviePoster extends StatelessWidget {
  final String url;
  final String? heroTag;
  final double radius;

  const MoviePoster({
    super.key,
    required this.url,
    this.heroTag,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget placeholder() => ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(
        Icons.movie_outlined,
        size: 30,
        color: scheme.onSurfaceVariant,
      ),
    );
    final poster = ClipRSuperellipse(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? placeholder()
          : CachedNetworkImage(
              imageUrl: url,
              httpHeaders: ApiConfig.imageHeaders,
              fit: BoxFit.cover,
              memCacheWidth: 300,
              maxWidthDiskCache: 300,
              fadeInDuration: Duration.zero,
              placeholder: (_, _) => placeholder(),
              errorWidget: (_, _, _) => placeholder(),
            ),
    );
    if (heroTag == null ||
        url.isEmpty ||
        MediaQuery.disableAnimationsOf(context)) {
      return poster;
    }
    return Hero(
      tag: heroTag!,
      transitionOnUserGestures: true,
      flightShuttleBuilder: (_, animation, direction, from, to) =>
          (direction == HeroFlightDirection.push
                  ? to.widget as Hero
                  : from.widget as Hero)
              .child,
      child: poster,
    );
  }
}
