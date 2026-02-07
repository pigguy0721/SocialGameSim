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

-- イベント定義
local allEvents = {
  -- 開発期プラスイベント
  {
    id = "dev_media",
    name = "メディア取材",
    desc = "ゲーム雑誌から取材依頼",
    type = "plus",
    phase = "dev",
    costN = 5, costC = 0, costT = 0,
    apply = function(s)
      s.maxN = s.maxN + 2
      return {
        { label = "知名度上限", val = 2 },
      }
    end,
  },
  {
    id = "dev_creator",
    name = "有名クリエイター参加",
    desc = "著名クリエイターが協力を申し出た",
    type = "plus",
    phase = "dev",
    costN = 3, costC = 5, costT = 0,
    apply = function(s)
      s.maxC = s.maxC + 3
      s.maxN = s.maxN + 1
      return {
        { label = "コンテンツ上限", val = 3 },
        { label = "知名度上限", val = 1 },
      }
    end,
  },
  {
    id = "dev_smooth",
    name = "開発順調",
    desc = "予定より開発が順調に進んでいる",
    type = "plus",
    phase = "dev",
    costN = 0, costC = 3, costT = 3,
    apply = function(s)
      s.maxC = s.maxC + 1
      s.maxT = s.maxT + 1
      return {
        { label = "コンテンツ上限", val = 1 },
        { label = "技術力上限", val = 1 },
      }
    end,
  },
  {
    id = "dev_prototype",
    name = "試遊会が好評",
    desc = "内部試遊会で高評価",
    type = "plus",
    phase = "dev",
    costN = 0, costC = 5, costT = 0,
    apply = function(s)
      s.maxC = s.maxC + 2
      return {
        { label = "コンテンツ上限", val = 2 },
      }
    end,
  },
  {
    id = "dev_investment",
    name = "追加投資",
    desc = "投資家から追加資金を獲得",
    type = "plus",
    phase = "dev",
    costN = 5, costC = 0, costT = 0,
    apply = function(s)
      s.money = s.money + 300
      return {
        { label = "資金", val = 300, suffix = "万" },
      }
    end,
  },

  -- 開発期マイナスイベント
  {
    id = "dev_bug",
    name = "重大バグ発見",
    desc = "深刻なバグが発覚した",
    type = "minus",
    phase = "dev",
    costN = 0, costC = 0, costT = 8,
    apply = function(s)
      s.money = s.money - 100
      return {
        { label = "資金", val = -100, suffix = "万" },
      }
    end,
  },
  {
    id = "dev_quit",
    name = "スタッフ退職",
    desc = "主要スタッフが退職した",
    type = "minus",
    phase = "dev",
    costN = 3, costC = 3, costT = 3,
    apply = function(s)
      s.money = s.money - 150
      return {
        { label = "資金", val = -150, suffix = "万" },
      }
    end,
  },
  {
    id = "dev_spec_change",
    name = "仕様変更",
    desc = "大幅な仕様変更が必要に",
    type = "minus",
    phase = "dev",
    costN = 0, costC = 10, costT = 5,
    apply = function(s)
      s.money = s.money - 200
      return {
        { label = "資金", val = -200, suffix = "万" },
      }
    end,
  },
  {
    id = "dev_competitor",
    name = "競合タイトル発表",
    desc = "類似ゲームが先行発表された",
    type = "minus",
    phase = "dev",
    costN = 8, costC = 0, costT = 0,
    apply = function(s)
      s.maxN = math.max(5, s.maxN - 2)
      return {
        { label = "知名度上限", val = -2 },
      }
    end,
  },

  -- 運営期プラスイベント
  {
    id = "ops_viral",
    name = "バズる",
    desc = "SNSで大きな話題に",
    type = "plus",
    phase = "ops",
    costN = 5, costC = 0, costT = 0,
    apply = function(s)
      s.trend = s.trend + 15
      s.maxN = s.maxN + 2
      return {
        { label = "流行", val = 15 },
        { label = "知名度上限", val = 2 },
      }
    end,
  },
  {
    id = "ops_collab",
    name = "コラボ決定",
    desc = "人気作品とのコラボが決定",
    type = "plus",
    phase = "ops",
    costN = 8, costC = 5, costT = 0,
    apply = function(s)
      s.trend = s.trend + 20
      s.maxC = s.maxC + 2
      return {
        { label = "流行", val = 20 },
        { label = "コンテンツ上限", val = 2 },
      }
    end,
  },
  {
    id = "ops_review",
    name = "好意的レビュー",
    desc = "有名レビューサイトで高評価",
    type = "plus",
    phase = "ops",
    costN = 3, costC = 0, costT = 0,
    apply = function(s)
      s.trend = s.trend + 10
      return {
        { label = "流行", val = 10 },
      }
    end,
  },
  {
    id = "ops_event_success",
    name = "イベント盛況",
    desc = "ゲーム内イベントが大成功",
    type = "plus",
    phase = "ops",
    costN = 0, costC = 8, costT = 0,
    apply = function(s)
      s.trend = s.trend + 12
      s.money = s.money + 200
      return {
        { label = "流行", val = 12 },
        { label = "資金", val = 200, suffix = "万" },
      }
    end,
  },
  {
    id = "ops_popular_char",
    name = "新キャラが人気",
    desc = "新キャラクターが予想外のヒット",
    type = "plus",
    phase = "ops",
    costN = 0, costC = 5, costT = 0,
    apply = function(s)
      s.trend = s.trend + 8
      s.money = s.money + 150
      return {
        { label = "流行", val = 8 },
        { label = "資金", val = 150, suffix = "万" },
      }
    end,
  },

  -- 運営期マイナスイベント
  {
    id = "ops_flame",
    name = "炎上",
    desc = "不適切な表現で炎上",
    type = "minus",
    phase = "ops",
    costN = 10, costC = 5, costT = 0,
    apply = function(s)
      s.trend = s.trend - 25
      s.money = s.money - 300
      return {
        { label = "流行", val = -25 },
        { label = "資金", val = -300, suffix = "万" },
      }
    end,
  },
  {
    id = "ops_major_bug",
    name = "大型バグ発生",
    desc = "進行不能バグが発生",
    type = "minus",
    phase = "ops",
    costN = 0, costC = 0, costT = 10,
    apply = function(s)
      s.trend = s.trend - 15
      s.money = s.money - 200
      return {
        { label = "流行", val = -15 },
        { label = "資金", val = -200, suffix = "万" },
      }
    end,
  },
  {
    id = "ops_server_down",
    name = "サーバーダウン",
    desc = "サーバーが長時間停止",
    type = "minus",
    phase = "ops",
    costN = 0, costC = 0, costT = 8,
    apply = function(s)
      s.trend = s.trend - 10
      s.money = s.money - 250
      return {
        { label = "流行", val = -10 },
        { label = "資金", val = -250, suffix = "万" },
      }
    end,
  },
  {
    id = "ops_new_competitor",
    name = "強力な競合出現",
    desc = "大手が類似ゲームをリリース",
    type = "minus",
    phase = "ops",
    costN = 5, costC = 5, costT = 0,
    apply = function(s)
      s.trend = s.trend - 20
      return {
        { label = "流行", val = -20 },
      }
    end,
  },
  {
    id = "ops_user_leave",
    name = "ユーザー離反",
    desc = "虚無期間でユーザーが離れる",
    type = "minus",
    phase = "ops",
    costN = 0, costC = 8, costT = 0,
    apply = function(s)
      s.trend = s.trend - 12
      return {
        { label = "流行", val = -12 },
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
  {
    name = "外注依頼",
    desc = "外部リソースを活用",
    costN = 2, costC = 3, costT = 2,
    apply = function(s)
      s.maxC = s.maxC + 2
      s.money = s.money - 100
      return {
        { label = "コンテンツ上限", val = 2 },
        { label = "資金", val = -100, suffix = "万" },
      }
    end,
  },
  {
    name = "市場調査",
    desc = "ユーザーニーズを調査",
    costN = 4, costC = 2, costT = 0,
    apply = function(s)
      s.maxN = s.maxN + 1
      s.maxC = s.maxC + 1
      return {
        { label = "知名度上限", val = 1 },
        { label = "コンテンツ上限", val = 1 },
      }
    end,
  },
  {
    name = "テストプレイ",
    desc = "内部テストでバグ修正",
    costN = 0, costC = 3, costT = 4,
    apply = function(s)
      s.maxT = s.maxT + 2
      return {
        { label = "技術力上限", val = 2 },
      }
    end,
  },
  {
    name = "アイテム調達",
    desc = "ランダムなアイテムを獲得",
    costN = 3, costC = 3, costT = 3,
    apply = function(s)
      local item = generateItem()
      table.insert(s.items, item)
      return {
        { label = "獲得", val = 0, text = item.name .. "（" .. item.desc .. "）" },
      }
    end,
  },
}

-- ===== アイテムシステム =====

-- アイテムテンプレート
local itemTemplates = {
  {
    type = "money",
    namePattern = "資金調達",
    minValue = 100,
    maxValue = 500,
    descPattern = "資金+%d万",
  },
  {
    type = "resource_n",
    namePattern = "PRキット",
    minValue = 3,
    maxValue = 8,
    descPattern = "知名度上限+%d",
  },
  {
    type = "resource_c",
    namePattern = "企画案",
    minValue = 3,
    maxValue = 8,
    descPattern = "コンテンツ上限+%d",
  },
  {
    type = "resource_t",
    namePattern = "技術資料",
    minValue = 3,
    maxValue = 8,
    descPattern = "技術力上限+%d",
  },
  {
    type = "trend",
    namePattern = "バズネタ",
    minValue = 5,
    maxValue = 20,
    descPattern = "流行+%d",
  },
}

-- アイテム生成
function generateItem()
  local template = itemTemplates[math.random(1, #itemTemplates)]
  local value = math.random(template.minValue, template.maxValue)
  return {
    type = template.type,
    name = template.namePattern,
    value = value,
    desc = string.format(template.descPattern, value),
  }
end

-- アイテム使用
function useItem(item)
  local result = {}

  if item.type == "money" then
    state.money = state.money + item.value
    table.insert(result, { label = "資金", val = item.value, suffix = "万" })
  elseif item.type == "resource_n" then
    state.maxN = state.maxN + item.value
    table.insert(result, { label = "知名度上限", val = item.value })
  elseif item.type == "resource_c" then
    state.maxC = state.maxC + item.value
    table.insert(result, { label = "コンテンツ上限", val = item.value })
  elseif item.type == "resource_t" then
    state.maxT = state.maxT + item.value
    table.insert(result, { label = "技術力上限", val = item.value })
  elseif item.type == "trend" then
    state.trend = state.trend + item.value
    table.insert(result, { label = "流行", val = item.value })
  end

  return result
end

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
        { label = "流行", val = 5 },
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
        { label = "流行", val = 3 },
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
  {
    name = "キャンペーン開催",
    desc = "ログインボーナス強化",
    costN = 4, costC = 2, costT = 0,
    apply = function(s)
      s.trend = s.trend + 8
      s.money = s.money - 100
      return {
        { label = "流行", val = 8 },
        { label = "資金", val = -100, suffix = "万" },
      }
    end,
  },
  {
    name = "ガチャ追加",
    desc = "新規ガチャをリリース",
    costN = 3, costC = 4, costT = 2,
    apply = function(s)
      s.trend = s.trend + 6
      s.money = s.money + 150
      return {
        { label = "流行", val = 6 },
        { label = "資金", val = 150, suffix = "万" },
      }
    end,
  },
  {
    name = "イベント開催",
    desc = "期間限定イベントを実施",
    costN = 2, costC = 6, costT = 3,
    apply = function(s)
      s.maxC = s.maxC + 1
      s.trend = s.trend + 7
      return {
        { label = "コンテンツ上限", val = 1 },
        { label = "流行", val = 7 },
      }
    end,
  },
  {
    name = "生放送配信",
    desc = "公式生放送で情報発信",
    costN = 6, costC = 2, costT = 0,
    apply = function(s)
      s.maxN = s.maxN + 1
      s.trend = s.trend + 4
      return {
        { label = "知名度上限", val = 1 },
        { label = "流行", val = 4 },
      }
    end,
  },
  {
    name = "アイテム調達",
    desc = "ランダムなアイテムを獲得",
    costN = 3, costC = 3, costT = 3,
    apply = function(s)
      local item = generateItem()
      table.insert(s.items, item)
      return {
        { label = "獲得", val = 0, text = item.name .. "（" .. item.desc .. "）" },
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

  -- イベント生成（フェーズに応じて4件）
  state.currentMonthEvents = {}
  state.handledEvents = {}

  -- 現在のフェーズに適したイベントを抽出
  local eligibleEvents = {}
  for _, evt in ipairs(allEvents) do
    if evt.phase == state.phase or evt.phase == "both" then
      table.insert(eligibleEvents, evt)
    end
  end

  -- ランダムに4件選択（重複なし）
  if #eligibleEvents > 0 then
    local selected = {}
    for i = 1, math.min(4, #eligibleEvents) do
      local idx = math.random(1, #eligibleEvents)
      local evt = eligibleEvents[idx]
      local copy = {
        id = evt.id .. "_" .. state.month .. "_" .. i,
        name = evt.name,
        desc = evt.desc,
        type = evt.type,
        costN = evt.costN,
        costC = evt.costC,
        costT = evt.costT,
        apply = evt.apply,
      }
      table.insert(state.currentMonthEvents, copy)
      table.remove(eligibleEvents, idx)
    end
  end

  -- 未来イベント更新（3ヶ月先まで予告）
  state.futureEvents = {}
  for offset = 1, 3 do
    local futureMonth = state.month + offset
    if futureMonth <= TOTAL_MONTHS then
      -- 将来のフェーズを判定
      local futurePhase = futureMonth <= DEV_MONTHS and "dev" or "ops"

      -- 適したイベントから1つランダム選択
      local futureEligible = {}
      for _, evt in ipairs(allEvents) do
        if evt.phase == futurePhase or evt.phase == "both" then
          table.insert(futureEligible, evt)
        end
      end

      if #futureEligible > 0 then
        local evt = futureEligible[math.random(1, #futureEligible)]
        table.insert(state.futureEvents, {
          month = futureMonth,
          name = evt.name,
          type = evt.type,
        })
      end
    end
  end
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
    -- 時間減衰計算（月経過で加速）
    local opsMonth = state.month - DEV_MONTHS
    local baseDecay = 1.0
    local decayAccel = opsMonth * 0.01  -- 月ごとに1%悪化
    state.decay = baseDecay - decayAccel

    -- 流行が高いほど減衰を緩和
    if state.trend > 50 then
      state.decay = state.decay + 0.2
    elseif state.trend > 20 then
      state.decay = state.decay + 0.1
    elseif state.trend < -20 then
      state.decay = state.decay - 0.1
    end
    state.decay = math.max(0.3, math.min(1.0, state.decay))

    -- 流行補正（-100〜+100 → 0.5〜1.5）
    local trendBonus = 1.0 + (state.trend / 200)
    trendBonus = math.max(0.5, math.min(1.5, trendBonus))

    -- 勢い計算
    state.momentum = (state.maxN + state.maxC) * trendBonus * state.decay

    -- 課金率（技術力が影響）
    local chargeRate = 0.15 + (state.maxT * 0.002)
    chargeRate = math.min(0.3, chargeRate)

    -- 収益計算
    local revenue = math.floor(state.momentum * chargeRate * 100)
    state.money = state.money + revenue
    table.insert(monthEndReport, { label = "収益", val = revenue, suffix = "万" })

    -- 維持費（ユーザー規模に応じて変動）
    local baseCost = 150
    local scaleCost = math.floor(state.momentum * 0.5)
    local cost = baseCost + scaleCost
    state.money = state.money - cost
    table.insert(monthEndReport, { label = "維持費", val = -cost, suffix = "万" })
  end

  -- 流行減衰（月経過で加速）
  if state.phase == "ops" then
    local opsMonth = state.month - DEV_MONTHS
    local trendDecay = 2 + math.floor(opsMonth / 6)  -- 6ヶ月ごとに+1
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
      -- 選択処理
      if key == "up" then
        selectedIndex = math.max(1, selectedIndex - 1)
      elseif key == "down" then
        local actions = state.phase == "dev" and devActions or opsActions
        local unhandledEvents = 0
        for _, evt in ipairs(state.currentMonthEvents) do
          local handled = false
          for _, id in ipairs(state.handledEvents) do
            if id == evt.id then handled = true break end
          end
          if not handled then unhandledEvents = unhandledEvents + 1 end
        end
        local maxIdx = unhandledEvents + #actions + #state.items
        selectedIndex = math.min(maxIdx, selectedIndex + 1)
      elseif key == "space" or key == "return" then
        -- 未対応イベント数をカウント
        local unhandledEvents = {}
        for _, evt in ipairs(state.currentMonthEvents) do
          local handled = false
          for _, id in ipairs(state.handledEvents) do
            if id == evt.id then handled = true break end
          end
          if not handled then table.insert(unhandledEvents, evt) end
        end

        -- 行動実行
        if selectedIndex <= #unhandledEvents then
          -- イベント対応
          local evt = unhandledEvents[selectedIndex]
          if canAffordAction(evt) then
            lastActionResult = handleEvent(evt)
            subState = "action_result"
          end
        else
          local actions = state.phase == "dev" and devActions or opsActions
          local actionIdx = selectedIndex - #unhandledEvents
          if actionIdx >= 1 and actionIdx <= #actions then
            -- 通常行動
            local action = actions[actionIdx]
            if canAffordAction(action) then
              lastActionResult = executeAction(action)
              subState = "action_result"
            end
          else
            -- アイテム使用
            local itemIdx = selectedIndex - #unhandledEvents - #actions
            if itemIdx >= 1 and itemIdx <= #state.items then
              local item = state.items[itemIdx]
              lastActionResult = useItem(item)
              table.remove(state.items, itemIdx)
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

  -- 今月のイベント一覧
  boldPrint("今月のイベント:", 50, 140)
  for i, evt in ipairs(state.currentMonthEvents) do
    local color = evt.type == "plus" and {0.5, 1, 0.5} or {1, 0.5, 0.5}
    love.graphics.setColor(color)
    boldPrint((i) .. ". " .. evt.name .. " - " .. evt.desc, 70, 140 + i * 30)
  end

  -- 未来イベント予告
  if #state.futureEvents > 0 then
    love.graphics.setColor(1, 1, 1)
    boldPrint("今後の予定:", 420, 140)
    for i, futureEvt in ipairs(state.futureEvents) do
      local color = futureEvt.type == "plus" and {0.7, 1, 0.7} or {1, 0.7, 0.7}
      love.graphics.setColor(color)
      boldPrint(futureEvt.month .. "ヶ月目: " .. futureEvt.name, 440, 140 + i * 25)
    end
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

  -- アイテム
  if #state.items > 0 then
    y = y + 10
    love.graphics.setColor(1, 1, 1)
    boldPrint("【アイテム使用】（行動消費なし）", 50, y)
    y = y + 30
    for i, item in ipairs(state.items) do
      local color = idx == selectedIndex and {1, 1, 0} or {0.5, 1, 1}
      love.graphics.setColor(color)
      boldPrint((idx) .. ". " .. item.name .. " (" .. item.desc .. ")", 70, y)
      y = y + 25
      idx = idx + 1
    end
  end

  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(tinyFont)
  boldPrint("↑↓: Select  SPACE: Execute", 50, 500)
  if #state.items > 0 then
    boldPrint("アイテム: " .. #state.items .. "個所持", 50, 520)
  end
end

function drawActionResultScreen()
  love.graphics.setFont(menuFont)
  love.graphics.setColor(1, 1, 1)
  boldPrint("行動結果", 50, 30)

  love.graphics.setFont(smallFont)
  local y = 100
  for _, r in ipairs(lastActionResult) do
    local text
    if r.text then
      text = r.label .. ": " .. r.text
    else
      text = r.label .. ": " .. (r.val >= 0 and "+" or "") .. r.val .. (r.suffix or "")
    end
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
