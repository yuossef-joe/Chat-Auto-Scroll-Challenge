import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/widgets.dart';

class ChatAutoScrollManager {
  final ScrollController scrollController;

  final double topAndBottomChromeHeight;

  final double Function() bottomSafeArea;

  // ---- per-stream state ----
  final Map<String, double> _initialScrollExtents = {};
  final Map<String, bool> _reachedTargetScroll = {};

  // ---- user-intent state ----
  bool _userHasScrolledAway = false;

  /// True only while the user is physically dragging / flinging the list.
  bool _isUserScrolling = false;

  static const double _bottomThreshold = 20.0;

  /// Whether the user has manually scrolled away from the bottom.
  bool get isUserScrolledAway => _userHasScrolledAway;

  ChatAutoScrollManager({
    required this.scrollController,
    this.topAndBottomChromeHeight = 168,
    required this.bottomSafeArea,
  });

  // ---------------------------------------------------------------
  // Scroll-position save / restore
  // ---------------------------------------------------------------

  /// Save the current scroll offset so it can be restored after a message
  /// insert that we don't want the user to see (they are scrolled away).
  double? saveOffset() {
    if (!scrollController.hasClients) return null;
    return scrollController.offset;
  }

  /// Restore scroll position in the next frame. Call this inside a
  /// `postFrameCallback` after a message insert when the user was scrolled
  /// away.  The [previousOffset] is the value returned by [saveOffset].
  void restoreOffset(double previousOffset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;
      // Clamp to the new maxScrollExtent (the list grew, so max is bigger).
      final clamped = previousOffset.clamp(
        scrollController.position.minScrollExtent,
        scrollController.position.maxScrollExtent,
      );
      scrollController.jumpTo(clamped);
    });
  }

  // ---------------------------------------------------------------
  // Streaming helpers
  // ---------------------------------------------------------------

  void onStreamStarted(String streamId) {
    _reachedTargetScroll[streamId] = false;
  }

  void onStreamingChunkReceived(String streamId) {
    if (_userHasScrolledAway) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;

      final reachedTarget = _reachedTargetScroll[streamId] ?? false;
      if (reachedTarget) return;

      if (!_initialScrollExtents.containsKey(streamId)) {
        _initialScrollExtents[streamId] =
            scrollController.position.maxScrollExtent;
      }
      final initialExtent = _initialScrollExtents[streamId]!;

      if (initialExtent <= 0) return;

      final targetScroll =
          initialExtent +
          scrollController.position.viewportDimension -
          bottomSafeArea() -
          topAndBottomChromeHeight;

      if (scrollController.position.maxScrollExtent > targetScroll) {
        scrollController.animateTo(
          targetScroll,
          duration: const Duration(milliseconds: 250),
          curve: Curves.linearToEaseOut,
        );
        _reachedTargetScroll[streamId] = true;
      } else {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.linearToEaseOut,
        );
      }
    });
  }

  void onStreamEnded(String streamId) {
    _initialScrollExtents.remove(streamId);
    _reachedTargetScroll.remove(streamId);
  }

  // ---------------------------------------------------------------
  // Scroll notifications
  // ---------------------------------------------------------------

  bool handleScrollNotification(Notification notification) {
    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.forward) {
        _userHasScrolledAway = true;
        _isUserScrolling = true;
      } else if (notification.direction == ScrollDirection.idle) {
        _isUserScrolling = false;
      } else {
        // ScrollDirection.reverse  (scrolling toward bottom)
        _isUserScrolling = true;
      }
    }

    // Only check "returned to bottom" during an actual user-initiated scroll,
    // never during a programmatic animateTo / jumpTo.
    if (_isUserScrolling &&
        (notification is ScrollUpdateNotification ||
            notification is ScrollEndNotification)) {
      _checkIfReturnedToBottom();
    }

    return false;
  }

  void onScrollToBottomPressed() {
    _userHasScrolledAway = false;
  }

  void _checkIfReturnedToBottom() {
    if (!scrollController.hasClients) return;

    final position = scrollController.position;
    final distanceFromBottom = position.maxScrollExtent - position.pixels;

    if (distanceFromBottom <= _bottomThreshold) {
      _userHasScrolledAway = false;
    }
  }

  void dispose() {
    _initialScrollExtents.clear();
    _reachedTargetScroll.clear();
  }
}
