# LinguaTutor — Setup Guide

## What You Get

A universal macOS + iOS SwiftUI app that:
- Teaches **Marathi**, **Swedish**, and **Punjabi** at CEFR levels A1–C2
- 30-minute daily sessions (random language, weighted toward your weakest areas)
- 7 exercise types: Vocabulary, Grammar, Translation, Reading, Writing, Speaking, Listening
- Full CEFR placement tests + per-skill tests
- Voice input via Apple Speech (Marathi, Swedish, Punjabi all supported)
- Connects to **Claude API** (Haiku for drills, Sonnet for deep evaluation)
- **Token-efficient design**: one cached system prompt per session saves ~90% of system prompt costs

---

## Step 1 — Create the Xcode Project

1. Open **Xcode** (requires Xcode 15+)
2. **File → New → Project**
3. Select **Multiplatform → App**
4. Product Name: `LinguaTutor`
5. Bundle Identifier: `com.yourname.linguatutor`
6. Interface: **SwiftUI**, Language: **Swift**
7. Leave "Use Core Data" unchecked
8. Save to `/Users/gauravchatrath/Documents/app/LinguaTutor/`

---

## Step 2 — Replace / Add Source Files

Delete the generated `ContentView.swift` from the project.

Drag all `.swift` files from `LinguaTutor/` into the Xcode project:

```
LinguaTutorApp.swift          ← replace existing
Models/Models.swift
Services/AnthropicService.swift
Services/SkillTemplates.swift
Services/SpeechService.swift
Services/SessionManager.swift
Storage/ProgressStore.swift
Views/Dashboard/DashboardView.swift
Views/Lesson/LessonView.swift
Views/Lesson/ExerciseView.swift
Views/Test/TestView.swift
Views/Settings/SettingsView.swift
```

When prompted, choose **"Add to target: LinguaTutor"** for all files.

---

## Step 3 — Configure Info.plist

In Xcode's project navigator, select the `LinguaTutor` target → **Info** tab.

Add these two keys (or edit `Info.plist` directly with the file in this folder):

| Key | Value |
|-----|-------|
| `NSMicrophoneUsageDescription` | LinguaTutor uses the microphone for speaking exercises. |
| `NSSpeechRecognitionUsageDescription` | LinguaTutor uses speech recognition to evaluate your pronunciation. |

---

## Step 4 — Add Capabilities (for macOS)

For macOS target, enable:
- **Hardened Runtime** → check **Audio Input** and **Speech Recognition**

In Xcode: Target → Signing & Capabilities → + Capability → add these.

---

## Step 5 — Set Your API Key

Build and run the app. On first launch you'll see the onboarding screen.

Paste your **Anthropic API key** (from [console.anthropic.com](https://console.anthropic.com)) and tap **Save Key**, then **Test** to verify.

---

## Architecture — Token Efficiency

```
Session start
  └─ generateLesson()  →  LESSON|sv|A1|vocab
       ↓
     Sonnet (one-time, ~800 tokens)
     System prompt (~520 tokens) → CACHED for 5 min

Per exercise
  └─ evaluateExercise()  →  EVAL|vocab|sv|A1|Hej|Hello
       ↓
     Haiku (fast, cheap)
     System prompt → CACHE HIT (0.1× cost, ~50 tokens billed instead of 520)
```

**Cost per 30-min session (approx):**
- 1× lesson generation: ~$0.004 (Sonnet)
- 8 drill evaluations: ~$0.002 total (Haiku + cache hits)
- **Total: ~$0.006 per session**

---

## Supported Speech Locales

| Language | Locale | Script |
|----------|--------|--------|
| Marathi  | mr-IN  | Devanagari (मराठी) |
| Swedish  | sv-SE  | Latin |
| Punjabi  | pa-IN  | Gurmukhi (ਪੰਜਾਬੀ) |

Speech recognition requires internet on first use (Apple downloads language models on-device).

---

## File Overview

| File | Purpose |
|------|---------|
| `Models.swift` | Language, CEFRLevel, Exercise, ExerciseResult, LanguageProgress |
| `AnthropicService.swift` | API calls, prompt caching, model routing (Haiku/Sonnet) |
| `SkillTemplates.swift` | Master system prompt + compact command builders |
| `SpeechService.swift` | Apple Speech recognition + AVSpeechSynthesizer |
| `SessionManager.swift` | 30-min timer, exercise sequence, language weighting |
| `ProgressStore.swift` | UserDefaults persistence, streak, token savings |
| `DashboardView.swift` | Home screen with stats and language cards |
| `LessonView.swift` | Session state machine UI |
| `ExerciseView.swift` | Per-type exercise inputs (text, voice, listening) |
| `TestView.swift` | Placement + skill tests with automatic level update |
| `SettingsView.swift` | API key, level overrides, reset |
