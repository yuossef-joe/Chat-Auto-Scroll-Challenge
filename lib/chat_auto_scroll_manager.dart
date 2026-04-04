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

  static const double _bottomThreshold = 20.0;

  ChatAutoScrollManager({
    required this.scrollController,
    this.topAndBottomChromeHeight = 168,
    required this.bottomSafeArea,
  });

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

  bool handleScrollNotification(Notification notification) {
    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.forward) {
        _userHasScrolledAway = true;
      }
    }

    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
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
