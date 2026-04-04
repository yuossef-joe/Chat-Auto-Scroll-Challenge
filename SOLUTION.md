# Solution — Chat Auto-Scroll Challenge

## Overview

This document explains the auto-scroll UX challenge, the issues identified in the
original codebase, and the architecture of the fix that matches the
[reference implementation](https://iman-admin.github.io/chat-scroll-demo/).

---

## UX Issues Identified

### 1. No auto-scroll during token streaming

The `ChatAnimatedList` widget from `flutter_chat_ui` auto-scrolls **only when a
new message is inserted** (via `_scrollToEnd` → `_subsequentScrollToEnd`).
Because the streaming response is inserted **once** as a `TextStreamMessage` and
then updated in-place through `GeminiStreamManager.addChunk()` /
`notifyListeners()`, the library never fires another scroll after the initial
insert. The result: as the AI response grows token-by-token the content
overflows below the viewport and the user has to scroll manually.

### 2. No pause when the user scrolls away

There was no mechanism to detect that the user manually scrolled up during an
active stream and suppress the (non-existent) auto-scroll. Even if auto-scroll
were added naïvely, it would fight the user's scroll position.

### 3. No resume when the user returns to the bottom

Without scroll-intent tracking there was no way to re-engage auto-scroll when
the user scrolls back down to the bottom of the list.

### 4. Library's default `shouldScrollToEndWhenAtBottom` conflicts with custom logic

The default `true` value causes the library to try its own scroll-to-end on
insert, which interferes with a custom scroll strategy. The reference
implementation explicitly sets this to `false` and takes full control.

---

## Architecture of the Fix

### New file: `lib/chat_auto_scroll_manager.dart`

A dedicated, **context-free** class (`ChatAutoScrollManager`) that owns all
auto-scroll state and decisions. It receives a `ScrollController` and layout
metrics, but never touches `BuildContext` directly, making it easy to unit-test.

**Key responsibilities:**

| Method                                   | When called                          | What it does                                                   |
| ---------------------------------------- | ------------------------------------ | -------------------------------------------------------------- |
| `onStreamStarted(streamId)`              | After the stream message is inserted | Initialises per-stream maps                                    |
| `onStreamingChunkReceived(streamId)`     | After every `addChunk()`             | Schedules a post-frame scroll if the user hasn't scrolled away |
| `onStreamEnded(streamId)`                | On stream done / error / stop        | Cleans up per-stream state                                     |
| `handleScrollNotification(notification)` | From `NotificationListener` wrapper  | Detects user-scroll-away (↑) and return-to-bottom (↓)          |

**Scroll algorithm (per chunk):**

1. If `_userHasScrolledAway` → do nothing.
2. If `_reachedTargetScroll[streamId]` → do nothing (message is pinned).
3. Lazily capture `_initialScrollExtents[streamId]` (the `maxScrollExtent` right
   after the streaming message was inserted).
4. Compute `targetScroll = initialExtent + viewportDimension − bottomSafeArea − chromeHeight`.
5. If `maxScrollExtent > targetScroll` → pin to `targetScroll` and mark reached.
6. Otherwise → `animateTo(maxScrollExtent)` (follow the bottom).

This is the same "target-scroll pinning" used by the official library example
(`examples/flyer_chat/lib/gemini.dart`).

### Modified file: `lib/gemini_chat_screen.dart`

| Change                                                                | Why                                                                    |
| --------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Import `chat_auto_scroll_manager.dart`                                | Use the new manager                                                    |
| Instantiate `ChatAutoScrollManager` in `initState`                    | Lifecycle setup                                                        |
| Set `shouldScrollToEndWhenAtBottom: false` on `ChatAnimatedList`      | Disable library's built-in auto-scroll so the manager has sole control |
| Wrap `ChatAnimatedList` in `NotificationListener<Notification>`       | Feed scroll events to the manager for user-intent detection            |
| Call `onStreamStarted` after `insertMessage` + `startStream`          | Begin tracking                                                         |
| Call `onStreamingChunkReceived` after `addChunk`                      | Trigger per-chunk scroll                                               |
| Call `onStreamEnded` in `onDone`, `onError`, and `_stopCurrentStream` | Clean up                                                               |
| Post-frame `animateTo(maxScrollExtent)` after stream message insert   | Manual scroll-to-bottom on insert (since library's auto-scroll is off) |
| Dispose manager in `dispose()`                                        | Lifecycle cleanup                                                      |

### Unchanged files

- `lib/gemini_stream_manager.dart` — No changes needed; stream state management
  is already clean and well-separated.
- `lib/in_memory_chat_controller.dart` — No changes needed.
- `lib/main.dart` — No changes needed.

---

## How It Works — End to End

1. **User sends a message →** `shouldScrollToEndWhenSendingMessage` (library
   default `true`) scrolls to bottom automatically.
2. **AI stream starts →** A `TextStreamMessage` is inserted. We manually scroll
   to bottom in a post-frame callback. `onStreamStarted` preps per-stream state.
3. **Each chunk arrives →** `addChunk` updates text via `notifyListeners()`.
   `onStreamingChunkReceived` fires a post-frame callback that animates to
   `maxScrollExtent` (or pins to `targetScroll` once the message fills the
   viewport).
4. **User scrolls up →** `UserScrollNotification` with `ScrollDirection.forward`
   sets `_userHasScrolledAway = true`. All future chunk callbacks exit early.
5. **User returns to bottom →** `ScrollUpdateNotification` / `ScrollEndNotification`
   checks `distanceFromBottom ≤ 20px` and re-engages auto-scroll.
6. **Stream ends (done / error / stop) →** `onStreamEnded` clears per-stream
   maps. `completeStream` replaces the `TextStreamMessage` with a final
   `TextMessage`.

---

## Edge Cases Handled

| Scenario                            | Handling                                                                    |
| ----------------------------------- | --------------------------------------------------------------------------- |
| First message (list not scrollable) | `initialExtent <= 0` guard skips scroll                                     |
| Very short response                 | `maxScrollExtent <= targetScroll` → follows bottom normally                 |
| User stops stream mid-way           | `_stopCurrentStream` calls `onStreamEnded` before `errorStream`             |
| Multiple rapid messages             | Each stream has its own ID in the maps; old stream cleaned up on end        |
| Empty chunks                        | Already filtered by `if (textChunk.isEmpty) return`                         |
| Scroll-to-bottom button             | Library's own handler is unaffected; reaching bottom re-enables auto-scroll |

---

## Files Changed

```
lib/
  chat_auto_scroll_manager.dart   ← NEW (scroll logic)
  gemini_chat_screen.dart         ← MODIFIED (wiring)
```
