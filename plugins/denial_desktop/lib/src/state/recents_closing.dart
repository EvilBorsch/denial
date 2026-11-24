import 'dart:async';

/// Apps closed from Recents whose windows are still going: what each card
/// held when it was closed, and how long its app has to close it.
///
/// Recents closes an app with a request, as a window's own close button
/// does (xdg_toplevel.close, WM_DELETE_WINDOW), never by killing it. An app
/// may answer the request with a question first, such as whether to save a
/// document, and keep its window open meanwhile. Such an app is kept open:
/// it opened a window over its card, a dialog of its own, or it still has a
/// window of the card open [grace] after the last app closed with it.
/// Apps closed together, as by «Close all», are judged together, so
/// [onKept] hears of them at once; it hears of each card once, with the
/// card's windows as they were when it was closed.
class RecentsClosing {
  RecentsClosing({required this.grace, required this.onKept});

  /// How long closed apps have to close their windows.
  final Duration grace;

  /// The apps of these cards kept a window open: each card with its
  /// windows as they were when it was closed.
  final void Function(Map<int, Set<int>> kept) onKept;

  final _cards = <int, Set<int>>{};
  Timer? _timer;

  /// No closed app is still going.
  bool get isEmpty => _cards.isEmpty;

  /// The app of [card] was asked to close [windows], the card's windows.
  void closing(int card, Iterable<int> windows) {
    _cards[card] = {card, ...windows};
    _timer?.cancel();
    _timer = Timer(grace, _graceOver);
  }

  /// The windows changed: [open] are the open windows, and [cardOf] names
  /// the card a window rides on. A card whose windows have all closed is
  /// done; one with a new window over it is kept open at once.
  void windowsChanged(Iterable<int> open, int? Function(int window) cardOf) {
    if (_cards.isEmpty) return;
    final now = open.toSet();
    final kept = <int, Set<int>>{};
    for (final MapEntry(key: card, value: windows) in [..._cards.entries]) {
      if (!windows.any(now.contains)) {
        _cards.remove(card);
        continue;
      }
      final asks = now.any(
        (window) => !windows.contains(window) && cardOf(window) == card,
      );
      if (asks) kept[card] = _cards.remove(card)!;
    }
    if (_cards.isEmpty) _stop();
    if (kept.isNotEmpty) onKept(kept);
  }

  void _graceOver() {
    _timer = null;
    if (_cards.isEmpty) return;
    final kept = Map<int, Set<int>>.of(_cards);
    _cards.clear();
    onKept(kept);
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Forgets every closed app, as a new session of the shell does.
  void clear() {
    _stop();
    _cards.clear();
  }
}
