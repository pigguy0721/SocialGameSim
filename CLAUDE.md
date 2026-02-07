# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 言語設定
ターミナル、ドキュメントともに日本語で出力する

## Project Overview

A card-selection roguelike game where the player manages a social game (gacha game) company. The goal is to repay debt by developing and operating a mobile game. Written entirely in Lua using the LÖVE (Love2D) framework.

## Running the Game

```bash
love .
```

Requires Love2D installed on the system.

## Building for Distribution

```bash
# Create .love archive
7z a -tzip game.love main.lua fonts/ imgs/

# Create standalone exe (combine with love.exe)
cat /path/to/love.exe game.love > SosyageRoguelike.exe
# Copy required DLLs (love.dll, lua51.dll, SDL2.dll, etc.) to same folder
```

## Architecture

The entire game is a single file: `main.lua` (~1850 lines). There is no module system or file splitting.

### Game Phases (Two-Phase Structure)

1. **Development Phase (`phase = "dev"`)**: 24 turns to build the game using borrowed money (initial debt: 5000). No revenue. Cards focus on building stats (content, tech, hype) and pre-registration users.
2. **Release Judgment**: At turn 25, stats determine initial user count via formula: `(content*100 + hype*50 + preregUsers) * bonus_multiplier`
3. **Operations Phase (`phase = "ops"`)**: Run the live game. Revenue comes from users, expenses from maintenance and interest. Auto-repays 30% of net profit. Win condition: debt reaches 0.

### State Machine

- `gameState`: `"title"` | `"game"` | `"gameover"`
- `subState` (within `"game"`): `"select"` | `"outcome"` | `"forced_event"` | `"release"` | `"win"`

### Key Data Structures

- `state` table: All game state (phase, turn, users, money, debt, content/tech/hype/monetize stats, energy)
- `stateSnapshot`: Captured before card execution for before/after diff display
- Card tables: `devCards`, `opsNormalCards`, `opsRareCards`, `negativeEvents`, `positiveEvents` — each card has `name`, `effectDesc`, `rarity`, `energyCost`, `apply(state, multiplier)` returning result entries
- Cards use a critical hit system: `critStat` field links to a stat, higher stat = higher crit rate (10% base, +0.3% per stat point, max 30%)

### Turn Flow (Operations Phase)

`processTurnStart()` calculates: revenue → maintenance → interest → auto-repay → user inflow → user churn → hype decay → content decay → energy recovery. Then `rollForcedEvent()` may trigger a conditional event (50% chance). Finally player picks a card from `drawHand()`.

### Rendering

All drawing uses Love2D primitives with letterbox scaling (800x600 base resolution). Bold text is faked by drawing twice with a 0.8px offset. No sprite sheets — UI is entirely procedural.

## Language Notes

- All user-facing text is in Japanese
- Font: Noto Sans JP (bundled in `fonts/`)
- Code comments and variable names mix Japanese and English
