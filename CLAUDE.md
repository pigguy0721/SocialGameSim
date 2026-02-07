# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 言語設定
ターミナル、ドキュメントともに日本語で出力する

## Project Overview

A 2-phase management simulation game where the player develops and operates a social game (gacha game) company. The goal is to survive 60 months (5 years) by managing limited resources. Written entirely in Lua using the LÖVE (Love2D) framework.

**Version**: v5 (rewritten from scratch on 2026-02-07)

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

The entire game is a single file: `main.lua` (~710 lines). There is no module system or file splitting.

### Game Phases (Two-Phase Structure)

1. **Development Phase (`phase = "dev"`)**: 24 months to build the game. No revenue, no expenses. Players allocate resources (N/C/T) to grow maximum resource values and prepare for release.

2. **Release**: At month 24 end, trend index is calculated based on maxN + maxC + random(-20, 20). Initial funding of 5000万円 is provided.

3. **Operations Phase (`phase = "ops"`)**: 36 months to run the live game. Monthly revenue and expenses. Win condition: survive to month 60. Lose condition: money drops below 0.

### Core Resources (N/C/T System)

- **N (知名度, Recognition)**: Used for marketing/PR actions
- **C (コンテンツ, Content)**: Used for content creation actions
- **T (技術力, Tech)**: Used for technical development actions

All resources:
- Reset to max value at month start
- Consumed by actions
- Max values grow through actions (no growth limit per month in v5)
- Initial max: 10 each

### State Machine

- `gameState`: `"title"` | `"game"` | `"gameover"`
- `subState` (within `"game"`): `"month_start"` | `"action_select"` | `"action_result"` | `"month_end"` | `"release"` | `"final"`

### Key Data Structures

**`state` table**: All game state
- Phase & time: `phase`, `month`
- Resources: `N`, `C`, `T`, `maxN`, `maxC`, `maxT`
- Economy: `money`
- Hidden params: `trend`, `decay`, `momentum`
- Visible metrics: `storeRating` (★1-5), `trendLabel`
- Monthly: `currentMonthEvents`, `futureEvents`, `actionsRemaining`, `handledEvents`
- Items: `items` (not yet implemented)

**Event/Action tables**:
- `allEvents`: Event definitions with `id`, `name`, `desc`, `type` (plus/minus), `phase`, costs (N/C/T), `apply(state)` function
- `devActions`: Development phase actions (3 types)
- `opsActions`: Operations phase actions (3 types)

No energy system, no critical hits, no card drawing mechanics.

### Monthly Flow

**Month Start** (`processMonthStart()`):
1. Reset N/C/T to max
2. Reset `actionsRemaining` to 4
3. Generate 4 events for current month
4. Generate 3 future events (preview)

**Action Phase** (4 actions per month):
- Player chooses from: current month events OR standard actions
- Event handling: `handleEvent()` consumes resources, applies effects, marks as handled
- Action execution: `executeAction()` consumes resources, applies effects
- Each choice decrements `actionsRemaining`

**Month End** (`processMonthEnd()`):
1. Penalize unhandled minus events (-100万円 each)
2. Calculate revenue (ops phase only): `(maxN + maxC) * 10 + trend * 5`
3. Deduct maintenance (ops phase only): -200万円
4. Decay trend (ops phase only): -2 per month
5. Update store rating based on trend

**Month Advance** (`advanceMonth()`):
1. Increment month
2. Check win (month > 60) or lose (money < 0)
3. Check phase transition (month 24 → 25 triggers release)
4. Call `processMonthStart()` for next month

### Rendering

All drawing uses Love2D primitives with letterbox scaling (800x600 base resolution). Bold text is faked by drawing twice with a 0.8px offset. No sprite sheets — UI is entirely procedural.

Screens:
- `drawTitleScreen()`: Title screen
- `drawMonthStartScreen()`: Month start with event list
- `drawActionSelectScreen()`: Action selection (events + standard actions)
- `drawActionResultScreen()`: Action execution results
- `drawMonthEndScreen()`: Monthly report with revenue/expenses
- `drawReleaseScreen()`: Release celebration (month 24 end)
- `drawFinalScreen()`: Victory screen (60 months survived)
- `drawGameOverScreen()`: Game over (money < 0)

### Input Handling

- Arrow keys (↑↓): Navigate selection
- Space/Enter: Confirm
- Escape: Return to title / Quit
- F11: Toggle borderless fullscreen

## Language Notes

- All user-facing text is in Japanese
- Font: Noto Sans JP (bundled in `fonts/`)
- Code comments and variable names mix Japanese and English

## Design Philosophy (v5)

- **Simplicity**: Removed energy, critical hits, card drawing — focus on resource management
- **Predictability**: Monthly reset cycle, fixed action count (4/month)
- **Strategic depth**: Limited resources force meaningful choices
- **Two-phase structure**: Building (dev) vs. sustaining (ops) offer different gameplay
- **Hidden complexity**: Trend system provides depth without UI clutter

## Code Structure Notes

~710 lines total, organized as:
1. Constants (lines 1-30)
2. Helper functions: `boldPrint`, `boldPrintf` (lines 32-51)
3. State initialization: `initState()` (lines 53-98)
4. Event/Action definitions (lines 100-240)
5. Monthly flow logic (lines 242-422)
6. LÖVE callbacks: `load`, `keypressed`, `update`, `draw` (lines 424-562)
7. Draw functions (lines 564-730)

Single file structure maintained for easy distribution and deployment.
