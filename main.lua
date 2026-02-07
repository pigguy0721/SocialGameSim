-- ============================================================
-- ソシャゲ運営シミュレーション v5（フェーズ＋流行システム）
-- ============================================================

-- ===== 定数 =====
local FONT_PATH = "fonts/NotoSansJP-Regular.ttf"

-- ゲーム期間
local DEV_MONTHS = 24        -- 開発期：24ヶ月
local OPS_MONTHS = 36        -- 運営期：36ヶ月
local TOTAL_MONTHS = 60      -- 合計：60ヶ月
local ACTIONS_PER_MONTH = 4  -- 月あたり行動回数

-- リソース初期値
local INITIAL_N = 10
local INITIAL_C = 10
local INITIAL_T = 10

-- リソース名
local resourceNames = { N = "知名度", C = "コンテンツ", T = "技術力" }
local resourceOrder = { "N", "C", "T" }

-- 太字描画オフセット
local BOLD_OFFSET = 0.8

-- 画面サイズ
local BASE_W = 800
local BASE_H = 600

-- ===== グローバル変数 =====
local gameState = "title"  -- "title" | "game" | "gameover"
local subState = "month_start"  -- "month_start" | "action_select" | "action_result" | "month_end" | "release" | "final"
local state = {}
local selectedIndex = 1
local lastActionResult = {}
local monthEndReport = {}

-- フォント
local titleFont, menuFont, smallFont, tinyFont
local isBorderlessFullscreen = false

-- ===== 太字描画ヘルパー =====
function boldPrint(text, x, y)
  love.graphics.print(text, x + BOLD_OFFSET, y)
  love.graphics.print(text, x, y)
end

function boldPrintf(text, x, y, limit, align)
  love.graphics.printf(text, x + BOLD_OFFSET, y, limit, align)
  love.graphics.printf(text, x, y, limit, align)
end

-- ===== state初期化 =====
function initState()
  state = {
    phase = "dev",           -- "dev" | "ops"
    month = 1,               -- 1〜60

    -- リソース（月初全回復）
    N = INITIAL_N,
    C = INITIAL_C,
    T = INITIAL_T,
    maxN = INITIAL_N,
    maxC = INITIAL_C,
    maxT = INITIAL_T,

    -- 経済
    money = 0,

    -- 隠しパラメータ（非表示）
    trend = 0,               -- 流行指数（-100〜+100）
    decay = 0,               -- 時間減衰
    momentum = 0,            -- 勢い

    -- プレイヤーに見える評価
    storeRating = 3,         -- ★1〜★5
    trendLabel = "",         -- コメント表示

    -- 月進行管理
    currentMonthEvents = {}, -- 当月イベント4件
    futureEvents = {},       -- 未来イベント3件
    actionsRemaining = ACTIONS_PER_MONTH,
    handledEvents = {},      -- 対応済みイベントID

    -- アイテム
    items = {},
  }

  selectedIndex = 1
  subState = "month_start"
  lastActionResult = {}
  monthEndReport = {}
end

-- ===== イベント/行動定義 =====

-- イベント定義（ダミー）
local allEvents = {
  {
    id = "event_bug",
    name = "バグ発見",
    desc = "重大なバグが発覚した",
    type = "minus",
    phase = "both",  -- "dev" | "ops" | "both"
    costN = 0, costC = 0, costT = 5,
    apply = function(s)
      s.money = s.money - 50
      return {
        { label = "資金", val = -50, suffix = "万" },
      }
    end,
  },
  {
    id = "event_pr",
    name = "メディア取材",
    desc = "メディアから取材依頼が来た",
    type = "plus",
    phase = "both",
    costN = 5, costC = 0, costT = 0,
    apply = function(s)
      s.maxN = s.maxN + 1
      return {
        { label = "知名度上限", val = 1 },
      }
    end,
  },
}

-- 開発期行動
local devActions = {
  {
    name = "広報活動",
    desc = "SNSやメディアで宣伝",
    costN = 5, costC = 0, costT = 0,
    apply = function(s)
      s.maxN = s.maxN + 1
      return {
        { label = "知名度上限", val = 1 },
      }
    end,
  },
  {
    name = "コンテンツ制作",
    desc = "ゲーム内容を充実させる",
    costN = 0, costC = 5, costT = 0,
    apply = function(s)
      s.maxC = s.maxC + 1
      return {
        { label = "コンテンツ上限", val = 1 },
      }
    end,
  },
  {
    name = "技術開発",
    desc = "システム基盤を強化",
    costN = 0, costC = 0, costT = 5,
    apply = function(s)
      s.maxT = s.maxT + 1
      return {
        { label = "技術力上限", val = 1 },
      }
    end,
  },
}

-- 運営期行動
local opsActions = {
  {
    name = "広報活動",
    desc = "SNSやメディアで宣伝",
    costN = 5, costC = 0, costT = 0,
    apply = function(s)
      s.maxN = s.maxN + 1
      s.trend = s.trend + 5
      return {
        { label = "知名度上限", val = 1 },
        { label = "流行+", val = 5 },
      }
    end,
  },
  {
    name = "コンテンツ追加",
    desc = "新規イベント・キャラ追加",
    costN = 0, costC = 5, costT = 0,
    apply = function(s)
      s.maxC = s.maxC + 1
      s.trend = s.trend + 3
      return {
        { label = "コンテンツ上限", val = 1 },
        { label = "流行+", val = 3 },
      }
    end,
  },
  {
    name = "技術改善",
    desc = "バグ修正・パフォーマンス向上",
    costN = 0, costC = 0, costT = 5,
    apply = function(s)
      s.maxT = s.maxT + 1
      return {
        { label = "技術力上限", val = 1 },
      }
    end,
  },
}

-- ===== 月進行ロジック =====

function processMonthStart()
  -- N/C/T全回復
  state.N = state.maxN
  state.C = state.maxC
  state.T = state.maxT

  -- 行動回数リセット
  state.actionsRemaining = ACTIONS_PER_MONTH

  -- イベント生成（ダミー：常に2件）
  state.currentMonthEvents = {}
  state.handledEvents = {}
  for i = 1, 2 do
    local evt = allEvents[math.random(1, #allEvents)]
    local copy = {
      id = evt.id .. "_" .. i,
      name = evt.name,
      desc = evt.desc,
      type = evt.type,
      costN = evt.costN,
      costC = evt.costC,
      costT = evt.costT,
      apply = evt.apply,
    }
    table.insert(state.currentMonthEvents, copy)
  end

  -- 未来イベント更新（ダミー）
  state.futureEvents = {
    { month = state.month + 1, name = "イベントA" },
    { month = state.month + 2, name = "イベントB" },
    { month = state.month + 3, name = "イベントC" },
  }
end

function processMonthEnd()
  monthEndReport = {}

  -- 未対応イベントのペナルティ
  for _, evt in ipairs(state.currentMonthEvents) do
    local handled = false
    for _, id in ipairs(state.handledEvents) do
      if id == evt.id then
        handled = true
        break
      end
    end
    if not handled and evt.type == "minus" then
      state.money = state.money - 100
      table.insert(monthEndReport, { label = evt.name .. "放置", val = -100, suffix = "万" })
    end
  end

  -- 運営期の収益計算
  if state.phase == "ops" then
    -- 簡易収益計算（仮）
    local revenue = math.floor((state.maxN + state.maxC) * 10 + state.trend * 5)
    state.money = state.money + revenue
    table.insert(monthEndReport, { label = "収益", val = revenue, suffix = "万" })

    -- 維持費
    local cost = 200
    state.money = state.money - cost
    table.insert(monthEndReport, { label = "維持費", val = -cost, suffix = "万" })
  end

  -- 流行減衰
  if state.phase == "ops" then
    local trendDecay = 2
    state.trend = math.max(-100, state.trend - trendDecay)
  end

  -- ストア評価更新（仮）
  if state.phase == "ops" then
    if state.trend > 50 then
      state.storeRating = 5
      state.trendLabel = "SNSで話題"
    elseif state.trend > 20 then
      state.storeRating = 4
      state.trendLabel = "堅調"
    elseif state.trend > -20 then
      state.storeRating = 3
      state.trendLabel = "普通"
    elseif state.trend > -50 then
      state.storeRating = 2
      state.trendLabel = "新規流入が鈍化"
    else
      state.storeRating = 1
      state.trendLabel = "やや過疎"
    end
  end
end

function advanceMonth()
  state.month = state.month + 1

  if state.month > TOTAL_MONTHS then
    -- ゲームクリア
    gameState = "gameover"
    subState = "final"
    return
  end

  -- フェーズ移行（24ヶ月目終了後）
  if state.month == DEV_MONTHS + 1 and state.phase == "dev" then
    subState = "release"
    return
  end

  -- サ終判定
  if state.money < 0 and state.phase == "ops" then
    gameState = "gameover"
    return
  end

  processMonthStart()
  subState = "month_start"
end

-- リリース処理
function executeRelease()
  -- 流行指数決定
  state.trend = state.maxN + state.maxC + math.random(-20, 20)
  state.trend = math.max(-100, math.min(100, state.trend))

  -- 初期資金
  state.money = 5000

  -- フェーズ移行
  state.phase = "ops"

  return {
    trend = state.trend,
    money = state.money,
  }
end

-- 行動実行
function canAffordAction(action)
  return state.N >= action.costN and state.C >= action.costC and state.T >= action.costT
end

function executeAction(action)
  -- コスト消費
  state.N = state.N - action.costN
  state.C = state.C - action.costC
  state.T = state.T - action.costT

  -- 効果適用
  local result = action.apply(state)

  -- 行動回数減少
  state.actionsRemaining = state.actionsRemaining - 1

  return result
end

function handleEvent(event)
  -- コスト消費
  state.N = state.N - event.costN
  state.C = state.C - event.costC
  state.T = state.T - event.costT

  -- 効果適用
  local result = event.apply(state)

  -- 対応済み記録
  table.insert(state.handledEvents, event.id)

  -- 行動回数減少
  state.actionsRemaining = state.actionsRemaining - 1

  return result
end

-- ===== LÖVE callbacks =====

function love.load()
  love.window.setTitle("ソシャゲ運営シミュレーション v5")
  love.window.setMode(800, 600, { resizable = true })

  -- フォント読み込み
  titleFont = love.graphics.newFont(FONT_PATH, 32)
  menuFont = love.graphics.newFont(FONT_PATH, 22)
  smallFont = love.graphics.newFont(FONT_PATH, 16)
  tinyFont = love.graphics.newFont(FONT_PATH, 13)

  math.randomseed(os.time())
  initState()
end

function love.keypressed(key)
  if key == "escape" then
    if gameState == "game" then
      gameState = "title"
      initState()
    else
      love.event.quit()
    end
  end

  if key == "f11" then
    isBorderlessFullscreen = not isBorderlessFullscreen
    love.window.setFullscreen(isBorderlessFullscreen, "desktop")
  end

  if gameState == "title" then
    if key == "space" or key == "return" then
      gameState = "game"
      processMonthStart()
      subState = "month_start"
    end
  elseif gameState == "game" then
    if subState == "month_start" then
      if key == "space" or key == "return" then
        subState = "action_select"
        selectedIndex = 1
      end
    elseif subState == "action_select" then
      -- 選択処理（仮）
      if key == "up" then
        selectedIndex = math.max(1, selectedIndex - 1)
      elseif key == "down" then
        local maxIdx = #state.currentMonthEvents + 3  -- イベント + 通常行動
        selectedIndex = math.min(maxIdx, selectedIndex + 1)
      elseif key == "space" or key == "return" then
        -- 行動実行
        if selectedIndex <= #state.currentMonthEvents then
          -- イベント対応
          local evt = state.currentMonthEvents[selectedIndex]
          if canAffordAction(evt) then
            lastActionResult = handleEvent(evt)
            subState = "action_result"
          end
        else
          -- 通常行動
          local actions = state.phase == "dev" and devActions or opsActions
          local actionIdx = selectedIndex - #state.currentMonthEvents
          if actionIdx >= 1 and actionIdx <= #actions then
            local action = actions[actionIdx]
            if canAffordAction(action) then
              lastActionResult = executeAction(action)
              subState = "action_result"
            end
          end
        end
      end
    elseif subState == "action_result" then
      if key == "space" or key == "return" then
        if state.actionsRemaining > 0 then
          subState = "action_select"
          selectedIndex = 1
        else
          processMonthEnd()
          subState = "month_end"
        end
      end
    elseif subState == "month_end" then
      if key == "space" or key == "return" then
        advanceMonth()
      end
    elseif subState == "release" then
      if key == "space" or key == "return" then
        executeRelease()
        advanceMonth()
      end
    end
  end
end

function love.update(dt)
  -- 必要に応じて更新処理
end

function love.draw()
  -- Letterbox scaling
  local realW, realH = love.graphics.getDimensions()
  local scaleX = realW / BASE_W
  local scaleY = realH / BASE_H
  local scale = math.min(scaleX, scaleY)
  local offsetX = (realW - BASE_W * scale) / 2
  local offsetY = (realH - BASE_H * scale) / 2

  love.graphics.push()
  love.graphics.translate(offsetX, offsetY)
  love.graphics.scale(scale, scale)

  -- 背景
  love.graphics.clear(0.1, 0.1, 0.15)

  if gameState == "title" then
    drawTitleScreen()
  elseif gameState == "game" then
    if subState == "month_start" then
      drawMonthStartScreen()
    elseif subState == "action_select" then
      drawActionSelectScreen()
    elseif subState == "action_result" then
      drawActionResultScreen()
    elseif subState == "month_end" then
      drawMonthEndScreen()
    elseif subState == "release" then
      drawReleaseScreen()
    end
  elseif gameState == "gameover" then
    if subState == "final" then
      drawFinalScreen()
    else
      drawGameOverScreen()
    end
  end

  love.graphics.pop()
end

-- ===== 描画関数 =====

function drawTitleScreen()
  love.graphics.setFont(titleFont)
  love.graphics.setColor(1, 1, 1)
  boldPrintf("ソシャゲ運営シミュレーション v5", 0, 200, BASE_W, "center")

  love.graphics.setFont(smallFont)
  boldPrintf("Press SPACE to Start", 0, 350, BASE_W, "center")
end

function drawMonthStartScreen()
  love.graphics.setFont(menuFont)
  love.graphics.setColor(1, 1, 1)
  boldPrint("月初: " .. state.month .. "ヶ月目", 50, 30)

  love.graphics.setFont(smallFont)
  boldPrint("フェーズ: " .. (state.phase == "dev" and "開発期" or "運営期"), 50, 70)
  boldPrint("資金: " .. state.money .. "万円", 50, 100)

  -- イベント一覧
  boldPrint("今月のイベント:", 50, 140)
  for i, evt in ipairs(state.currentMonthEvents) do
    local color = evt.type == "plus" and {0.5, 1, 0.5} or {1, 0.5, 0.5}
    love.graphics.setColor(color)
    boldPrint((i) .. ". " .. evt.name .. " - " .. evt.desc, 70, 140 + i * 30)
  end

  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(tinyFont)
  boldPrint("Press SPACE to continue", 50, 500)
end

function drawActionSelectScreen()
  love.graphics.setFont(menuFont)
  love.graphics.setColor(1, 1, 1)
  boldPrint(state.month .. "ヶ月目 - 行動選択", 50, 30)

  love.graphics.setFont(smallFont)
  -- リソース表示
  boldPrint("N:" .. state.N .. "/" .. state.maxN .. "  C:" .. state.C .. "/" .. state.maxC .. "  T:" .. state.T .. "/" .. state.maxT, 50, 70)
  boldPrint("資金: " .. state.money .. "万  残り行動: " .. state.actionsRemaining, 50, 100)

  -- 選択肢
  local y = 140
  local idx = 1

  -- イベント
  boldPrint("【イベント対応】", 50, y)
  y = y + 30
  for i, evt in ipairs(state.currentMonthEvents) do
    local handled = false
    for _, id in ipairs(state.handledEvents) do
      if id == evt.id then
        handled = true
        break
      end
    end
    if not handled then
      local color = idx == selectedIndex and {1, 1, 0} or {1, 1, 1}
      love.graphics.setColor(color)
      boldPrint((idx) .. ". " .. evt.name .. " (N:" .. evt.costN .. " C:" .. evt.costC .. " T:" .. evt.costT .. ")", 70, y)
      y = y + 25
      idx = idx + 1
    end
  end

  -- 通常行動
  y = y + 10
  love.graphics.setColor(1, 1, 1)
  boldPrint("【通常行動】", 50, y)
  y = y + 30
  local actions = state.phase == "dev" and devActions or opsActions
  for i, act in ipairs(actions) do
    local color = idx == selectedIndex and {1, 1, 0} or {1, 1, 1}
    love.graphics.setColor(color)
    boldPrint((idx) .. ". " .. act.name .. " (N:" .. act.costN .. " C:" .. act.costC .. " T:" .. act.costT .. ")", 70, y)
    y = y + 25
    idx = idx + 1
  end

  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(tinyFont)
  boldPrint("↑↓: Select  SPACE: Execute", 50, 500)
end

function drawActionResultScreen()
  love.graphics.setFont(menuFont)
  love.graphics.setColor(1, 1, 1)
  boldPrint("行動結果", 50, 30)

  love.graphics.setFont(smallFont)
  local y = 100
  for _, r in ipairs(lastActionResult) do
    local text = r.label .. ": " .. (r.val >= 0 and "+" or "") .. r.val .. (r.suffix or "")
    boldPrint(text, 70, y)
    y = y + 30
  end

  love.graphics.setFont(tinyFont)
  boldPrint("Press SPACE to continue", 50, 500)
end

function drawMonthEndScreen()
  love.graphics.setFont(menuFont)
  love.graphics.setColor(1, 1, 1)
  boldPrint("月末レポート - " .. state.month .. "ヶ月目", 50, 30)

  love.graphics.setFont(smallFont)
  local y = 100
  for _, r in ipairs(monthEndReport) do
    local text = r.label .. ": " .. (r.val >= 0 and "+" or "") .. r.val .. (r.suffix or "")
    boldPrint(text, 70, y)
    y = y + 30
  end

  boldPrint("資金: " .. state.money .. "万円", 70, y + 20)

  if state.phase == "ops" then
    boldPrint("ストア評価: " .. string.rep("★", state.storeRating) .. string.rep("☆", 5 - state.storeRating), 70, y + 50)
    boldPrint("状況: " .. state.trendLabel, 70, y + 80)
  end

  love.graphics.setFont(tinyFont)
  boldPrint("Press SPACE to continue", 50, 500)
end

function drawReleaseScreen()
  love.graphics.setFont(titleFont)
  love.graphics.setColor(1, 1, 0)
  boldPrintf("リリース！", 0, 200, BASE_W, "center")

  love.graphics.setFont(smallFont)
  love.graphics.setColor(1, 1, 1)
  boldPrintf("24ヶ月の開発期間が終了しました", 0, 280, BASE_W, "center")
  boldPrintf("これから運営期に入ります", 0, 310, BASE_W, "center")

  love.graphics.setFont(tinyFont)
  boldPrint("Press SPACE to continue", 50, 500)
end

function drawFinalScreen()
  love.graphics.setFont(titleFont)
  love.graphics.setColor(1, 1, 0)
  boldPrintf("60ヶ月完走！", 0, 200, BASE_W, "center")

  love.graphics.setFont(smallFont)
  love.graphics.setColor(1, 1, 1)
  boldPrintf("最終資金: " .. state.money .. "万円", 0, 280, BASE_W, "center")

  love.graphics.setFont(tinyFont)
  boldPrint("Press ESC to return to title", 50, 500)
end

function drawGameOverScreen()
  love.graphics.setFont(titleFont)
  love.graphics.setColor(1, 0.3, 0.3)
  boldPrintf("サービス終了", 0, 200, BASE_W, "center")

  love.graphics.setFont(smallFont)
  love.graphics.setColor(1, 1, 1)
  boldPrintf(state.month .. "ヶ月目で資金が尽きました", 0, 280, BASE_W, "center")

  love.graphics.setFont(tinyFont)
  boldPrint("Press ESC to return to title", 50, 500)
end
