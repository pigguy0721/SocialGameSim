# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 言語設定
ターミナル、ドキュメントともに日本語で出力する

## Project Overview

A 2-phase management simulation game where the player develops and operates a social game (gacha game) company. The goal is to survive 48 months (4 years) by managing limited resources. Written entirely in Lua using the LÖVE (Love2D) framework.

**Version**: v5.8 (latest update: 2026-02-09)

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

The entire game is a single file: `main.lua` (~2200 lines). There is no module system or file splitting.

### Game Phases (Two-Phase Structure)

1. **Development Phase (`phase = "dev"`)**: 12 months to build the game. No revenue, no expenses. Initial debt: -2000万円. Players allocate resources (N/C/T) to grow maximum resource values and prepare for release.

2. **Release**: At month 12 end, trend index is calculated based on maxN + maxC + random(-20, 20) + (permanent item count × 3). Initial funding of 5000万円 is provided.

3. **Operations Phase (`phase = "ops"`)**: 36 months to run the live game. Revenue from recurring items (regular content/gacha) monthly, limited items (limited content/gacha) on use. Maintenance cost: 200万円/month. Win condition: survive to month 48. Lose condition: money drops below 0.

### Goals (v5.4)
- **1st Anniversary Goal**: Clear debt (money >= 0) by month 24 (ops 12 months)
- **3rd Anniversary Goal**: Reach rank 1 in store ranking by month 48 (ops 36 months)

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
- Hidden params: `trend` (displayed in ops phase), `decay`, `momentum`
- Visible metrics: `storeRating` (★1-5), `storeRanking`, `trendLabel`
- Monthly: `currentMonthEvents`, `futureEvents`, `actionsRemaining`, `handledEvents`
- Items: `items` (revenue items: permanent/limited content/gacha)
- Recurring revenue: `recurringRevenue` (v5.6)

**Event/Action tables**:
- `allEvents`: Event definitions with `id`, `name`, `desc`, `type` (plus/minus), `phase`, costs (N/C/T), `apply(state)` function
- `devActions`: Development phase actions (6 types: stat growth + content/gacha implementation)
- `opsActions`: Operations phase actions (6 types: stat growth + content/gacha implementation)

**Item Usage Restrictions (v5.8)**:
- **Dev phase**: Permanent items (content/gacha) usable but no revenue until ops phase. Limited items not usable.
- **Ops phase**: All items usable without restrictions.

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
2. Add recurring revenue (ops phase only, v5.6): from regular content/gacha items
3. Deduct maintenance (ops phase only): -200万円
4. Decay trend (ops phase only): configurable rate (default -2 per month)
5. Update store rating and ranking based on trend
6. Check goal achievement (v5.4)

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

### Input Handling (v5.7 updated)

- Arrow keys (↑↓): Navigate selection within column
- Left/Right keys (←→): Switch between left column (events/actions) and right column (items)
- Space/Enter: Confirm
- Escape: Return to title / Quit
- F11: Toggle borderless fullscreen

### UI Layout (v5.7 major improvement)

**Two-column layout:**
- **Left column**: Event responses and regular actions
- **Right column**: Future event preview (top) and item list (bottom, scrollable up to 18 items)

**Cursor display:**
- Selected item shows "→ " cursor
- Yellow highlight on selected item

**Selection position memory:**
- Each column remembers last selected position
- When switching columns, returns to previous position
- Resets to position 1 at month start

## Language Notes

- All user-facing text is in Japanese
- Font: Noto Sans JP (bundled in `fonts/`)
- Code comments and variable names mix Japanese and English

## Design Philosophy (v5.8)

- **Simplicity**: Removed energy, critical hits, card drawing — focus on resource management
- **Predictability**: Monthly reset cycle, fixed action count (4/month)
- **Strategic depth**: Limited resources force meaningful choices
- **Two-phase structure**: Building (dev) vs. sustaining (ops) offer different gameplay
- **Hidden complexity**: Trend system (now visible in ops phase for player feedback)
- **Revenue clarity (v5.6→v5.8)**: Events/actions no longer grant money. All revenue from 4 item types only.
- **Dev phase strategy (v5.8)**: Permanent items usable in dev (no revenue) but boost release trend by +3 per item
- **UI optimization (v5.7)**: Two-column layout, cursor display, position memory for comfortable play

## Code Structure Notes

~2200 lines total (as of v5.8), organized as:
1. Constants (lines 1-30)
2. Global variables: game state, selection tracking (lines 31-52)
3. Helper functions: `boldPrint`, `boldPrintf` (lines 54-63)
4. Autoplay system functions (lines 65-200+)
5. State initialization: `initState()` (lines ~70-100)
6. Event/Action definitions (lines ~100-600)
7. Item generation functions (v5.6): `generateContentItem()`, `generateGachaItem()` (lines ~600-700)
8. Monthly flow logic: `processMonthStart()`, `processMonthEnd()`, etc. (lines ~700-1400)
9. LÖVE callbacks: `load`, `keypressed`, `update`, `draw` (lines ~1500-1800)
10. Draw functions: title, settings, autoplay, game screens (lines ~1800-2200)

Single file structure maintained for easy distribution and deployment. Code has grown significantly with feature additions (v5.3-v5.7) but remains maintainable due to clear function organization.
