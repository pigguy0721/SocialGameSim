# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 言語設定
ターミナル、ドキュメントともに日本語で出力する

## Project Overview

A simplified social game management simulation where the player operates a social game company for 36 months (3 years). The goal is to survive by managing limited resources while avoiding bankruptcy. Written entirely in Lua using the LÖVE (Love2D) framework.

**Version**: Simple version (based on simple_gacha_sim_spec.md)
**Last update**: 2026-02-09

## Running the Game

```bash
love .
```

Requires Love2D installed on the system.

## Building for Distribution

```bash
# Create .love archive
7z a -tzip game.love main.lua fonts/

# Create standalone exe (combine with love.exe)
cat /path/to/love.exe game.love > SosyageSimSimple.exe
# Copy required DLLs (love.dll, lua51.dll, SDL2.dll, etc.) to same folder
```

## Architecture

The entire game is a single file: `main.lua` (~1270 lines). There is no module system or file splitting.

### New Features (v2.0)

**Game Settings System**:
- Comprehensive parameter configuration (5 categories, 20+ parameters)
- Save/load config to `config.lua`
- Reset to defaults with R key

**Autoplay Mode**:
- AI-driven automated testing (10 / 10,000 / 1,000,000 runs)
- CSV export with detailed game logs
- Statistics summary (survival rate, average survival months, etc.)
- Simple AI strategy: randomly performs 1-3 actions per month
- **Result screen** displayed after completion with comprehensive statistics

### Game Structure (Single Phase)

**36 months total**: Operate the game and survive until month 36.

- **Initial capital**: 2000万円
- **Win condition**: Survive 36 months
- **Lose condition**: Money drops to 0 or below

### Core Systems

#### Action System

Players can take actions **unlimited times per month**, but action costs increase exponentially:

```
cost = 100万円 × (1.4 ^ action_count)
```

Examples:
- 1st action: 100万円
- 2nd action: 140万円
- 3rd action: 196万円
- 4th action: 274万円

#### Three Actions

1. **ガチャ実装 (Gacha Implementation)**
   - Character +1
   - Revenue item (Gacha) acquired (1 month lifespan)
   - Fire risk: Large

2. **コンテンツ実装 (Content Implementation)**
   - Tech +1
   - Revenue buff item (Content) acquired (1 month lifespan)
   - Fire risk: Medium

3. **広告 (Advertisement)**
   - Fame +1
   - User increase buff item (Ad) acquired (1 month lifespan)
   - Fire risk: Small

#### Items (All 1-month lifespan)

- **Gacha items**: Revenue +10%
- **Content items**: Revenue +5%
- **Ad items**: Users +10%

All items expire at month end.

#### Fire System (Controversy/Scandal)

**Fire rate calculation**:
```
fire_rate = 5% + (actions_this_month × 4%)
```

Examples:
- 3 actions → 17%
- 6 actions → 29%
- 10 actions → 45%

**When fire occurs**:
- Money -30%
- Rating -1
- Users -15%

### State Parameters

**Growth Parameters**:
- **character** (キャラ): Increased by gacha
- **tech** (技術力): Increased by content
- **fame** (知名度): Increased by ads

**Status Parameters**:
- **rating** (ユーザ評価): 1-5 stars
- **users** (ユーザ数): Number of users
- **ranking** (セルラン): Store ranking (演出用)
- **money** (資金): Operating capital

### Monthly Flow

1. **Month Start**: Display month number
2. **Action Phase**: Player can take actions until they choose "月末へ進む" or run out of money
3. **Fire Check**: Probability-based controversy check
4. **Month End Processing**:
   - New users: `fame × 100 × (1 + ad_items × 0.1)`
   - User churn: `(6 - rating) × 3%`
   - Revenue: `users × rating_multiplier × gacha_buff × content_buff`
   - Rating multipliers: ★1=0.5, ★2=0.8, ★3=1.0, ★4=1.3, ★5=1.6
   - Items expire
   - Action count resets
5. **Advance to Next Month**

### State Machine

- `gameState`: `"title"` | `"game"` | `"gameover"` | `"clear"`
- `subState` (within `"game"`): `"month_start"` | `"action_select"` | `"action_result"` | `"fire_check"` | `"month_end"`

### Rendering

All drawing uses Love2D primitives with basic layout (800x600 base resolution). Bold text is faked by drawing twice with a 0.8px offset.

Screens:
- `drawTitleScreen()`: Title screen
- `drawMonthStartScreen()`: Month start
- `drawActionSelectScreen()`: Action selection (3 actions + "月末へ進む")
- `drawActionResultScreen()`: Action execution results
- `drawFireCheckScreen()`: Fire check results
- `drawMonthEndScreen()`: Monthly report with revenue/expenses
- `drawGameOverScreen()`: Game over (money < 0)
- `drawClearScreen()`: Victory screen (36 months survived)

### Input Handling

- Arrow keys (↑↓): Navigate selection
- Space/Enter: Confirm
- Escape: Return to title / Quit

## Language Notes

- All user-facing text is in Japanese
- Font: Noto Sans JP (bundled in `fonts/`)
- Code comments and variable names mix Japanese and English

## Design Philosophy

- **Simplicity**: Focused on resource management and risk assessment
- **Risk vs. Reward**: More actions = higher income potential but also higher fire risk
- **Strategic depth**: Balance between gacha/content/ads and financial management
- **Exponential cost**: Forces players to make meaningful decisions about when to stop acting

## Code Structure Notes

~1270 lines total, organized as:
1. Constants (lines 1-8)
2. **Config system** (lines 11-101): Settings definition, save/load, defaults
3. Global variables (lines 104-134)
4. State initialization: `initState()` (lines 139-169)
5. Helper functions: `boldPrint`, `formatMoney`, etc. (lines 172-194)
6. Action cost calculation (lines 197-201)
7. Action definitions (lines 204-243)
8. Action execution (lines 246-269)
9. Fire system (lines 272-302)
10. Month end processing (lines 305-374)
11. Month advance (lines 377-394)
12. **Autoplay system** (lines 397-575): AI execution, CSV export, statistics
13. **Settings UI** (lines 578-637): Config screen logic, parameter adjustment
14. LÖVE callbacks: `load`, `keypressed`, `update`, `draw` (lines 640-840)
15. Draw functions: title, settings, autoplay, game screens (lines 843-1271)

Single file structure maintained for easy distribution and deployment.

### Key Functions

**Settings Management**:
- `saveConfig()`: Writes config to file
- `loadConfig()`: Reads config from file
- `resetConfig()`: Restores default values
- `buildSettingsItems()`: Builds UI structure
- `adjustSetting()`: Modifies parameter values

**Autoplay**:
- `startAutoplay(mode)`: Initializes autoplay session
- `runOneAutoplayGame()`: Executes single game with AI
- `updateAutoplay()`: Processes multiple games per frame
- `saveAutoplayResults()`: Exports CSV and stats
- `calculateAutoplayStats()`: Computes summary statistics
