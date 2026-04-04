# Chat Auto-Scroll Challenge

## Setup

1. Get a free Gemini API key from [ai.google.dev](https://ai.google.dev) the Api AIzaSyDbfrQvDWx9ThnYTFuvCK_XNCfWLvkmTGA
2. Run `flutter pub get`
3. Run `flutter run` (web, macOS, or any platform)
4. Enter your API key and start chatting

## The Problem

This app uses [flutter_chat_ui](https://github.com/flyerhq/flutter_chat_ui) to display a streaming chat with Google Gemini. When you send a message, the AI response streams in token by token.

**Try it:** Send multiple messages (e.g. _"Write a detailed essay about the history of the internet"_) and notice the scroll UX issues as the responses stream in.

## Your Task

Compare the scroll behavior between this app and the reference implementation: https://iman-admin.github.io/chat-scroll-demo/

Identify the UX issues and fix them. Your solution must match the scroll behavior of the reference implementation.

**Test it thoroughly before you start coding.** Pay attention to every detail of how auto-scroll engages, disengages, and resumes. Your solution will be scored primarily on how closely it matches this behavior.

You are free to use any AI tools you'd like. What matters is the end result.

## How to Submit

1. Clone this repo into a **private** repository on your own GitHub account.
2. Implement your solution.
3. Deploy your solution to the web (GitHub Pages, Firebase Hosting, or any hosting).
4. Update this README with:
   - A list of the UX issues you identified and fixed. ✅
   - Your deployed URL.
   - A screen recording demonstrating each fix.
5. Add **IMan-admin** as a collaborator to your private repo.
6. Send us the link to your repo.

## Evaluation Criteria

- Does it auto-scroll during streaming?
- Does manual scroll-away pause auto-scroll?
- Does returning to bottom resume auto-scroll?
- Is the code clean, testable, and well-separated?
- Are edge cases handled?

## UX Issues Identified and Fixed

### 1. **No auto-scroll during token streaming**

- **Issue**: The chat list only auto-scrolled when a new message was **inserted**, not when it was updated. Since the AI response streams as a single `TextStreamMessage` that updates in-place, the user had to manually scroll to see new tokens arriving.
- **Fix**: Integrated `ChatAutoScrollManager` to detect every chunk update and trigger a smooth `animateTo(maxScrollExtent)` scroll in a post-frame callback, keeping the latest content visible as it streams in.

### 2. **No pause when user manually scrolls away**

- **Issue**: Even if auto-scroll existed, there was no mechanism to detect when the user scrolled up during streaming to suppress the auto-scroll. The list would fight the user's scroll position.
- **Fix**: Added scroll-intent detection via `NotificationListener<UserScrollNotification>` to track when the user drags upward (`ScrollDirection.forward`). When detected, auto-scroll is paused until the user explicitly returns to the bottom.

### 3. **No resume when user returns to the bottom**

- **Issue**: Once auto-scroll was paused due to manual scroll-away, there was no way to re-engage it when the user scrolled back down.
- **Fix**: Implemented `_checkIfReturnedToBottom()` which monitors scroll position on every `ScrollUpdateNotification` and `ScrollEndNotification`. When the user's scroll offset is within 20 pixels of the bottom, auto-scroll is automatically re-enabled.

### 4. **Library's conflicting auto-scroll behavior**

- **Issue**: `ChatAnimatedList`'s default `shouldScrollToEndWhenAtBottom: true` interfered with custom per-chunk scroll logic, causing unpredictable scroll conflicts.
- **Fix**: Disabled the library's built-in auto-scroll (`shouldScrollToEndWhenAtBottom: false`) and delegated full scroll control to `ChatAutoScrollManager`, ensuring a single, clear scroll strategy throughout the stream lifecycle.

## Solution Architecture

- **New file**: `lib/chat_auto_scroll_manager.dart` — Context-free, testable scroll manager that owns all auto-scroll state and decisions.
- **Modified**: `lib/gemini_chat_screen.dart` — Wired the manager into the stream lifecycle (start, per-chunk, completion/error) and wrapped the chat list in a `NotificationListener` for user-intent detection.
