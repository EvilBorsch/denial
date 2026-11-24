import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/motion.dart' show SelectedListenable;

import 'home_grid_geometry.dart';
import 'home_interactions.dart';
import 'widgets/home_empty_state.dart';
import 'widgets/home_grid_page.dart';
import 'widgets/page_dots.dart';

/// The paged home grid and its page dots.
class HomePager extends StatefulWidget {
  const HomePager({
    super.key,
    required this.slots,
    required this.hasError,
    required this.pages,
    required this.sharedBottomRow,
    required this.controller,
    required this.viewportKey,
    required this.onLayout,
    required this.onPageChanged,
  });

  /// Null while the grid loads.
  final List<HomeGridItem?>? slots;
  final bool hasError;

  /// Pages the user made: [HomeGridLayout.pageCount].
  final int pages;

  /// The first page's bottom row stays put while the pages move.
  final bool sharedBottomRow;
  final PageController controller;

  /// Marks the grid viewport, whose coordinates [HomeGridGeometry] uses.
  final GlobalKey viewportKey;
  final ValueChanged<HomeGridGeometry> onLayout;
  final ValueChanged<int> onPageChanged;

  static const double inset = 22;
  static const double dotsReservedHeight = 7;

  /// Under a grid whose bottom row is not shared: the band the page dots
  /// take, kept clear of the home pill below it.
  static const double dotsBand = 36;

  /// Where the page dots go in a pager [viewportHeight] tall: between the
  /// rows above and a shared bottom row, or in the band under the grid.
  static double dotsTop(HomeGridGeometry geometry, double viewportHeight) {
    if (!geometry.sharedBottomRow) {
      return viewportHeight - dotsBand + 8;
    }
    final rowVisualHeight = geometry.tileSize.height.clamp(
      0.0,
      _rowVisualHeight,
    );
    final upperBottom =
        (geometry.upperRows - 1) * geometry.stepY + rowVisualHeight;
    return (upperBottom + geometry.bottomRowTop - dotsReservedHeight) / 2;
  }

  /// Icon and label of a phone tile; rows below a taller cell show no more.
  static const double _rowVisualHeight = 126;

  @override
  State<HomePager> createState() => _HomePagerState();
}

typedef _PagerMode = ({bool locked, bool extraPage});

class _HomePagerState extends State<HomePager> {
  HomeInteractions? _interactions;
  SelectedListenable<_PagerMode>? _mode;

  /// Built pages, reused while slots and geometry hold: locking the pager
  /// for a drag must not rebuild every tile on its pages.
  final _pages = <int, Widget>{};
  List<HomeGridItem?>? _pagesSlots;
  HomeGridGeometry? _pagesGeometry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final interactions = HomeInteractionScope.of(context);
    if (identical(interactions, _interactions)) return;
    _interactions = interactions;
    _mode?.dispose();
    // A held tile or widget frame owns the finger: the pager stays put, and
    // a drag gets an empty page past the last to drop onto.
    _mode = SelectedListenable<_PagerMode>(
      Listenable.merge([interactions.drag.drag, interactions.resize.target]),
      () => (
        locked: interactions.drag.active || interactions.resize.active,
        extraPage: interactions.drag.active,
      ),
    );
  }

  @override
  void dispose() {
    _mode?.dispose();
    super.dispose();
  }

  Widget _page(int page, List<HomeGridItem?> slots, HomeGridGeometry geometry) {
    if (!identical(slots, _pagesSlots) || geometry != _pagesGeometry) {
      _pages.clear();
      _pagesSlots = slots;
      _pagesGeometry = geometry;
    }
    return _pages[page] ??= _KeptAlivePage(
      child: HomeGridPage(slots: slots, page: page, geometry: geometry),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = HomeGridGeometry.forViewport(
          constraints.biggest,
          inset: HomePager.inset,
          rowGap: widget.sharedBottomRow
              ? HomePager.dotsReservedHeight
              : HomePager.dotsBand,
          sharedBottomRow: widget.sharedBottomRow,
        );
        HomeGridLayout.columns = geometry.columns;
        HomeGridLayout.rows = geometry.rows;
        HomeGridLayout.sharedBottomRow = geometry.sharedBottomRow;
        widget.onLayout(geometry);

        final slots = widget.slots;
        final dotsTop = HomePager.dotsTop(geometry, constraints.maxHeight);

        final pageCount = slots == null
            ? 0
            : HomeGridLayout.pageCount(slots, geometry.pageSize, widget.pages);
        final Widget content;
        if (slots == null) {
          content = HomeEmptyState(
            label: widget.hasError
                ? context.l10n.commonError
                : context.l10n.commonLoading,
          );
        } else {
          final pager = ValueListenableBuilder<_PagerMode>(
            valueListenable: _mode!,
            builder: (context, mode, _) => PageView.builder(
              controller: widget.controller,
              physics: mode.locked
                  ? const NeverScrollableScrollPhysics()
                  : null,
              // Keep the neighbors built, and every visited page alive: a
              // swipe would otherwise build its incoming page's tiles, and
              // re-decode their vector icons, on its first frame.
              allowImplicitScrolling: true,
              itemCount: pageCount + (mode.extraPage ? 1 : 0),
              onPageChanged: widget.onPageChanged,
              itemBuilder: (context, page) => _page(page, slots, geometry),
            ),
          );
          content = geometry.sharedBottomRow
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    pager,
                    HomeGridPage(
                      slots: slots,
                      page: 0,
                      geometry: geometry,
                      bottomRow: true,
                    ),
                  ],
                )
              : pager;
        }

        return Stack(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                key: widget.viewportKey,
                width: double.infinity,
                height: geometry.height,
                child: content,
              ),
            ),
            if (slots != null)
              Positioned(
                top: dotsTop,
                left: 0,
                right: 0,
                child: _HomePageDots(count: pageCount),
              ),
          ],
        );
      },
    );
  }
}

class _HomePageDots extends ConsumerWidget {
  const _HomePageDots({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(
      homeGridControllerProvider.select(
        (value) => value.asData?.value.page ?? 0,
      ),
    );
    return PageDots(count: count, active: page.clamp(0, count - 1));
  }
}

class _KeptAlivePage extends StatefulWidget {
  const _KeptAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeptAlivePage> createState() => _KeptAlivePageState();
}

class _KeptAlivePageState extends State<_KeptAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
