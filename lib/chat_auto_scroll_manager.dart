import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/widgets.dart';

/// Manages auto-scroll behavior during streaming chat responses.
///
/// Responsibilities:
/// - Scrolls to bottom as new chunks arrive during streaming.
/// - Pins the streaming message to the top of the viewport once it's tall
///   enough (target-scroll pinning).
/// - Pauses auto-scroll when the user manually scrolls away.
/// - Resumes auto-scroll when the user returns to the bottom.
/// - Cleans up per-stream state on stream completion or error.
class ChatAutoScrollManager {
  final ScrollController scrollController;

  /// Combined height of the app bar, composer, and any visual buffer.
  /// Used to calculate the target-scroll pin position.
  /// In the reference implementation this is 168
  /// (56 AppBar + 104 composer area + 8 visual buffer).
  final double topAndBottomChromeHeight;

  /// Callback that returns the current bottom safe-area inset.
  /// Kept as a callback so the manager stays context-free and testable.
  final double Function() bottomSafeArea;

  // ---- per-stream state ----
  final Map<String, double> _initialScrollExtents = {};
  final Map<String, bool> _reachedTargetScroll = {};

  // ---- user-intent state ----
  bool _userHasScrolledAway = false;

  /// Threshold (in logical pixels) for considering the user "at the bottom".
  static const double _bottomThreshold = 20.0;

  ChatAutoScrollManager({
    required this.scrollController,
    this.topAndBottomChromeHeight = 168,
    required this.bottomSafeArea,
  });

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Call when a new streaming response begins.
  void onStreamStarted(String streamId) {
    _reachedTargetScroll[streamId] = false;
    // Don't record initial extent yet — do it lazily on first chunk
    // so the insert-scroll has time to finish.
  }

  /// Call after every chunk is added to the stream manager.
  ///
  /// This should be invoked from the widget layer so that
  /// [WidgetsBinding.instance.addPostFrameCallback] runs in the correct phase.
  void onStreamingChunkReceived(String streamId) {
    if (_userHasScrolledAway) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;

      final reachedTarget = _reachedTargetScroll[streamId] ?? false;
      if (reachedTarget) return;

      // Lazily capture the initial extent after the first rebuild.
      if (!_initialScrollExtents.containsKey(streamId)) {
        _initialScrollExtents[streamId] =
            scrollController.position.maxScrollExtent;
      }
      final initialExtent = _initialScrollExtents[streamId]!;

      // If the list is not yet scrollable there's nothing to do.
      if (initialExtent <= 0) return;

      // Target position: pin the streaming message to the top of the
      // visible area (below the app bar).  Once the message is tall enough
      // to fill the viewport it stops scrolling further.
      final targetScroll =
          initialExtent +
          scrollController.position.viewportDimension -
          bottomSafeArea() -
          topAndBottomChromeHeight;

      if (scrollController.position.maxScrollExtent > targetScroll) {
        // Message has grown past the viewport — pin to target.
        scrollController.animateTo(
          targetScroll,
          duration: const Duration(milliseconds: 250),
          curve: Curves.linearToEaseOut,
        );
        _reachedTargetScroll[streamId] = true;
      } else {
        // Message hasn't filled the viewport yet — follow the bottom.
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.linearToEaseOut,
        );
      }
    });
  }

  /// Call when the stream completes or errors out.
  void onStreamEnded(String streamId) {
    _initialScrollExtents.remove(streamId);
    _reachedTargetScroll.remove(streamId);
  }

  // ---------------------------------------------------------------------------
  // Scroll-intent detection
  // ---------------------------------------------------------------------------

  /// Should be called from a [NotificationListener] wrapping the chat list.
  /// Returns `false` so that the notification continues to bubble.
  bool handleScrollNotification(Notification notification) {
    if (notification is UserScrollNotification) {
      // User dragging upward (ScrollDirection.forward in a non-reversed list)
      // means they're scrolling away from the bottom.
      if (notification.direction == ScrollDirection.forward) {
        _userHasScrolledAway = true;
      }
    }

    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      _checkIfReturnedToBottom();
    }

    // Don't consume the notification.
    return false;
  }

  /// Also useful to call after the scroll-to-bottom button is pressed.
  void onScrollToBottomPressed() {
    _userHasScrolledAway = false;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  void _checkIfReturnedToBottom() {
    if (!scrollController.hasClients) return;

    final position = scrollController.position;
    final distanceFromBottom = position.maxScrollExtent - position.pixels;

    if (distanceFromBottom <= _bottomThreshold) {
      _userHasScrolledAway = false;
    }
  }

  /// Clean up all state.  Call from the widget's [dispose].
  void dispose() {
    _initialScrollExtents.clear();
    _reachedTargetScroll.clear();
  }
}
