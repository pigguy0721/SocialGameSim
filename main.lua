-- ============================================================
-- ソシャゲ運営ローグライク — 借金返済編
-- ============================================================

-- ===== 定数 =====
local FONT_PATH = "fonts/NotoSansJP-Regular.ttf"
local START_MONTH = 4  -- 4月スタート

-- フェーズ・経済定数
local DEV_MONTHS = 24         -- 開発フェーズ: 2年（24ヶ月）
local OPS_MONTHS = 36         -- 運営フェーズ: 3年（36ヶ月）
local TOTAL_MONTHS = 60       -- 合計5年
local INITIAL_DEBT = 2000     -- 初期借金: 2000万円
local DEBT_DEADLINE = 36      -- 借金返済期限: 36ヶ月（運営1年目終了時）
local INTEREST_RATE = 0.03
local AUTO_REPAY_RATIO = 0.30
local ACTIONS_PER_MONTH = 4   -- 月あたりの行動回数

-- リソース初期値
local INITIAL_N = 10
local INITIAL_C = 10
local INITIAL_T = 10

-- リソース名
local resourceNames = {
  N = "知名度",
  C = "コンテンツ",
  T = "技術力",
}
local resourceOrder = { "N", "C", "T" }

-- ===== 太字描画ヘルパー =====
-- 1pxずらして2回描画することでBold風にする
local BOLD_OFFSET = 0.8

function boldPrint(text, x, y)
  love.graphics.print(text, x + BOLD_OFFSET, y)
  love.graphics.print(text, x, y)
end

function boldPrintf(text, x, y, limit, align)
  love.graphics.printf(text, x + BOLD_OFFSET, y, limit, align)
  love.graphics.printf(text, x, y, limit, align)
end

-- ===== ヘルパー関数 =====
function addStat(s, key, minVal, maxVal)
  local gain = math.random(minVal, maxVal)
  local prev = s[key]
  s[key] = math.min(MAX_STAT, s[key] + gain)
  return s[key] - prev
end

function addStatMult(s, key, minVal, maxVal, mult)
  local gain = math.random(math.floor(minVal * mult), math.floor(maxVal * mult))
  local prev = s[key]
  s[key] = math.min(MAX_STAT, s[key] + gain)
  return s[key] - prev
end

function addUsers(s, ratio)
  local gain = math.floor(s.users * ratio)
  s.users = s.users + gain
  return gain
end

function loseUsers(s, ratio)
  local lost = math.floor(s.users * ratio)
  s.users = math.max(0, s.users - lost)
  return lost
end

-- ターン→年月変換
function turnToDate(turn)
  local month = ((turn - 1 + START_MONTH - 1) % 12) + 1
  local year = math.floor((turn - 1 + START_MONTH - 1) / 12) + 1
  return year, month
end

function turnToDateStr(turn)
  local y, m = turnToDate(turn)
  return string.format("%d年目 %d月", y, m)
end

-- ===== 開発期カード =====
local devCards = {
  {
    name = "キャラデザイン制作",
    effectDesc = "コンテンツ力 +8~12\n資金 -100万",
    rarity = "normal",
    energyCost = 15,
    critStat = "content",
    apply = function(s, m)
      local g = addStatMult(s, "content", 8, 12, m)
      s.money = s.money - 100
      return {
        { label = "コンテンツ力", val = g },
        { label = "資金", val = -100, suffix = "万" },
      }
    end,
  },
  {
    name = "シナリオ執筆",
    effectDesc = "コンテンツ力 +10~15",
    rarity = "normal",
    energyCost = 25,
    critStat = "content",
    apply = function(s, m)
      local g = addStatMult(s, "content", 10, 15, m)
      return {
        { label = "コンテンツ力", val = g },
      }
    end,
  },
  {
    name = "サーバー基盤構築",
    effectDesc = "技術力 +10~15\n資金 -150万",
    rarity = "normal",
    energyCost = 15,
    critStat = "tech",
    apply = function(s, m)
      local g = addStatMult(s, "tech", 10, 15, m)
      s.money = s.money - 150
      return {
        { label = "技術力", val = g },
        { label = "資金", val = -150, suffix = "万" },
      }
    end,
  },
  {
    name = "ティザーPV制作",
    effectDesc = "話題性 +10~15\n資金 -100万",
    rarity = "normal",
    energyCost = 10,
    critStat = "hype",
    apply = function(s, m)
      local g = addStatMult(s, "hype", 10, 15, m)
      s.money = s.money - 100
      return {
        { label = "話題性", val = g },
        { label = "資金", val = -100, suffix = "万" },
      }
    end,
  },
  {
    name = "事前登録キャンペーン",
    effectDesc = "話題性 +5~8\n事前登録 +500~1000人\n資金 -50万",
    rarity = "normal",
    energyCost = 10,
    critStat = "hype",
    apply = function(s, m)
      local g = addStatMult(s, "hype", 5, 8, m)
      local prereg = math.random(math.floor(500 * m), math.floor(1000 * m))
      s.preregUsers = s.preregUsers + prereg
      s.money = s.money - 50
      return {
        { label = "話題性", val = g },
        { label = "事前登録", val = prereg, suffix = "人" },
        { label = "資金", val = -50, suffix = "万" },
      }
    end,
  },
  {
    name = "CBT実施",
    effectDesc = "技術力 +5~8\nコンテンツ力 +3~5",
    rarity = "normal",
    energyCost = 20,
    critStat = "tech",
    apply = function(s, m)
      local g1 = addStatMult(s, "tech", 5, 8, m)
      local g2 = addStatMult(s, "content", 3, 5, m)
      return {
        { label = "技術力", val = g1 },
        { label = "コンテンツ力", val = g2 },
      }
    end,
  },
  {
    name = "公式SNS開設",
    effectDesc = "話題性 +3~5",
    rarity = "normal",
    energyCost = 5,
    critStat = "hype",
    apply = function(s, m)
      local g = addStatMult(s, "hype", 3, 5, m)
      return {
        { label = "話題性", val = g },
      }
    end,
  },
  {
    name = "追加融資",
    effectDesc = "資金 +1000万\n借金 +1000万",
    rarity = "rare",
    energyCost = 0,
    apply = function(s, m)
      s.money = s.money + 1000
      s.debt = s.debt + 1000
      return {
        { label = "資金", val = 1000, suffix = "万" },
        { label = "借金", val = 1000, suffix = "万" },
      }
    end,
  },
}

-- ===== 運営期通常カード =====
local opsNormalCards = {
  {
    name = "新キャラ実装",
    effectDesc = "コンテンツ力 +5~8\n話題性 +3~5\nガチャ売上あり",
    rarity = "normal",
    energyCost = 15,
    critStat = "content",
    apply = function(s, m)
      local g1 = addStatMult(s, "content", 5, 8, m)
      local g2 = addStatMult(s, "hype", 3, 5, m)
      local rev = math.floor(s.users * s.monetize / 1500)
      s.money = s.money + rev
      return {
        { label = "コンテンツ力", val = g1 },
        { label = "話題性", val = g2 },
        { label = "ガチャ売上", val = rev, suffix = "万" },
      }
    end,
  },
  {
    name = "ストーリー更新",
    effectDesc = "コンテンツ力 +10~15\n話題性 +3~5\n課金パック売上あり\n資金 -80万",
    rarity = "normal",
    energyCost = 25,
    critStat = "content",
    apply = function(s, m)
      local g1 = addStatMult(s, "content", 10, 15, m)
      local g2 = addStatMult(s, "hype", 3, 5, m)
      local rev = math.floor(s.users * s.monetize / 1500)
      s.money = s.money + rev - 80
      return {
        { label = "コンテンツ力", val = g1 },
        { label = "話題性", val = g2 },
        { label = "パック売上", val = rev, suffix = "万" },
        { label = "資金", val = -50, suffix = "万" },
      }
    end,
  },
  {
    name = "コラボイベント開催",
    effectDesc = "話題性 +10~18\nユーザー +10%\nコラボガチャ売上あり\n資金 -200万",
    rarity = "normal",
    energyCost = 20,
    critStat = "hype",
    apply = function(s, m)
      local g = addStatMult(s, "hype", 10, 18, m)
      local gu = addUsers(s, 0.10 * m)
      local rev = math.floor(s.users * s.monetize / 1500)
      s.money = s.money + rev - 200
      return {
        { label = "話題性", val = g },
        { label = "ユーザー", val = gu, suffix = "人" },
        { label = "コラボガチャ売上", val = rev, suffix = "万" },
        { label = "資金", val = -150, suffix = "万" },
      }
    end,
  },
  {
    name = "レイドイベント開催",
    effectDesc = "コンテンツ力 +3~5\n話題性 +5~8\n周回課金あり",
    rarity = "normal",
    energyCost = 20,
    critStat = "content",
    apply = function(s, m)
      local g1 = addStatMult(s, "content", 3, 5, m)
      local g2 = addStatMult(s, "hype", 5, 8, m)
      local rev = math.floor(s.users * s.monetize / 1500)
      s.money = s.money + rev
      return {
        { label = "コンテンツ力", val = g1 },
        { label = "話題性", val = g2 },
        { label = "周回課金", val = rev, suffix = "万" },
      }
    end,
  },
  {
    name = "復刻イベント開催",
    effectDesc = "話題性 -2\nユーザー +3%（復帰勢）",
    rarity = "normal",
    energyCost = 5,
    apply = function(s, m)
      s.hype = math.max(0, s.hype - 2)
      local gu = addUsers(s, 0.03 * m)
      return {
        { label = "話題性", val = -2 },
        { label = "復帰ユーザー", val = gu, suffix = "人" },
      }
    end,
  },
  {
    name = "バグ修正",
    effectDesc = "技術力 +5~10",
    rarity = "normal",
    energyCost = 10,
    critStat = "tech",
    apply = function(s, m)
      local g = addStatMult(s, "tech", 5, 10, m)
      return {
        { label = "技術力", val = g },
      }
    end,
  },
  {
    name = "サーバー増強",
    effectDesc = "技術力 +5~8\n資金 -100万",
    rarity = "normal",
    energyCost = 10,
    critStat = "tech",
    apply = function(s, m)
      local g = addStatMult(s, "tech", 5, 8, m)
      s.money = s.money - 100
      return {
        { label = "技術力", val = g },
        { label = "資金", val = -100, suffix = "万" },
      }
    end,
  },
  {
    name = "SNS広報キャンペーン",
    effectDesc = "話題性 +5~10\n資金 -50万",
    rarity = "normal",
    energyCost = 8,
    critStat = "hype",
    apply = function(s, m)
      local g = addStatMult(s, "hype", 5, 10, m)
      s.money = s.money - 50
      return {
        { label = "話題性", val = g },
        { label = "資金", val = -50, suffix = "万" },
      }
    end,
  },
  {
    name = "限定ガチャ投入",
    effectDesc = "ガチャ売上あり\n課金圧 +8~12\n話題性 -3~5",
    rarity = "normal",
    energyCost = 10,
    critStat = "monetize",
    apply = function(s, m)
      local rev = math.floor(s.users * s.monetize / 1500)
      s.money = s.money + rev
      local g = addStatMult(s, "monetize", 8, 12, m)
      local hd = math.random(3, 5)
      s.hype = math.max(0, s.hype - hd)
      return {
        { label = "ガチャ売上", val = rev, suffix = "万" },
        { label = "課金圧", val = g },
        { label = "話題性", val = -hd },
      }
    end,
  },
  {
    name = "石バラマキ",
    effectDesc = "課金圧 -5~10\nユーザー +8%\n話題性 +3~5\n資金 -50万",
    rarity = "normal",
    energyCost = 5,
    critStat = "hype",
    apply = function(s, m)
      local dec = math.random(5, 10)
      s.monetize = math.max(0, s.monetize - dec)
      local gu = addUsers(s, 0.08 * m)
      local g = addStatMult(s, "hype", 3, 5, m)
      s.money = s.money - 50
      return {
        { label = "課金圧", val = -dec },
        { label = "ユーザー", val = gu, suffix = "人" },
        { label = "話題性", val = g },
        { label = "資金", val = -50, suffix = "万" },
      }
    end,
  },
}

-- ===== 運営期レアカード =====
local opsRareCards = {
  {
    name = "大型アップデート",
    effectDesc = "コンテンツ力 +15~20\n技術力 +3~5\n話題性 +8~12\n資金 -300万",
    rarity = "rare",
    energyCost = 25,
    critStat = "content",
    apply = function(s, m)
      local g1 = addStatMult(s, "content", 15, 20, m)
      local g2 = addStatMult(s, "tech", 3, 5, m)
      local g3 = addStatMult(s, "hype", 8, 12, m)
      s.money = s.money - 300
      return {
        { label = "コンテンツ力", val = g1 },
        { label = "技術力", val = g2 },
        { label = "話題性", val = g3 },
        { label = "資金", val = -300, suffix = "万" },
      }
    end,
  },
  {
    name = "有名配信者が紹介",
    effectDesc = "話題性 +15~25\nユーザー +15%",
    rarity = "rare",
    energyCost = 5,
    critStat = "hype",
    apply = function(s, m)
      local g = addStatMult(s, "hype", 15, 25, m)
      local gu = addUsers(s, 0.15 * m)
      return {
        { label = "話題性", val = g },
        { label = "ユーザー", val = gu, suffix = "人" },
      }
    end,
  },
  {
    name = "コラボ先からオファー",
    effectDesc = "話題性 +10~15\nユーザー +10%\n資金 +100万",
    rarity = "rare",
    energyCost = 5,
    critStat = "hype",
    apply = function(s, m)
      local g = addStatMult(s, "hype", 10, 15, m)
      local gu = addUsers(s, 0.10 * m)
      s.money = s.money + 100
      return {
        { label = "話題性", val = g },
        { label = "ユーザー", val = gu, suffix = "人" },
        { label = "資金", val = 100, suffix = "万" },
      }
    end,
  },
  {
    name = "福袋販売",
    effectDesc = "資金 +200万\n話題性 +3~5",
    rarity = "rare",
    energyCost = 5,
    critStat = "monetize",
    apply = function(s, m)
      s.money = s.money + math.floor(200 * m)
      local g = addStatMult(s, "hype", 3, 5, m)
      return {
        { label = "資金", val = math.floor(200 * m), suffix = "万" },
        { label = "話題性", val = g },
      }
    end,
  },
}

-- ===== 強制イベント =====
local negativeEvents = {
  {
    name = "緊急メンテナンス",
    effectDesc = "ユーザー -5%\n話題性 -5",
    isNegative = true,
    condition = function(s) return s.tech < 40 end,
    apply = function(s)
      local lost = loseUsers(s, 0.05)
      s.hype = math.max(0, s.hype - 5)
      return {
        { label = "ユーザー", val = -lost, suffix = "人" },
        { label = "話題性", val = -5 },
      }
    end,
  },
  {
    name = "ガチャ確率誤表記発覚",
    effectDesc = "資金 -300万\nユーザー -8%\n話題性 -10",
    isNegative = true,
    condition = function(s) return s.monetize > 50 end,
    apply = function(s)
      s.money = s.money - 300
      local lost = loseUsers(s, 0.08)
      s.hype = math.max(0, s.hype - 10)
      return {
        { label = "資金", val = -300, suffix = "万" },
        { label = "ユーザー", val = -lost, suffix = "人" },
        { label = "話題性", val = -10 },
      }
    end,
  },
  {
    name = "公式SNS失言",
    effectDesc = "話題性 -10",
    isNegative = true,
    condition = function(s) return true end,
    apply = function(s)
      s.hype = math.max(0, s.hype - 10)
      return { { label = "話題性", val = -10 } }
    end,
  },
  {
    name = "競合タイトル登場",
    effectDesc = "ユーザー -10%\n話題性 -8",
    isNegative = true,
    condition = function(s) return s.opsTurn > 6 end,
    apply = function(s)
      local lost = loseUsers(s, 0.10)
      s.hype = math.max(0, s.hype - 8)
      return {
        { label = "ユーザー", val = -lost, suffix = "人" },
        { label = "話題性", val = -8 },
      }
    end,
  },
  {
    name = "サーバーダウン",
    effectDesc = "ユーザー -5%\n資金 -100万",
    isNegative = true,
    condition = function(s) return s.tech < 40 end,
    apply = function(s)
      local lost = loseUsers(s, 0.05)
      s.money = s.money - 100
      return {
        { label = "ユーザー", val = -lost, suffix = "人" },
        { label = "資金", val = -100, suffix = "万" },
      }
    end,
  },
  {
    name = "炎上",
    effectDesc = "ユーザー -8%\n課金圧 -5\n話題性 +5",
    isNegative = true,
    condition = function(s) return s.monetize > 50 end,
    apply = function(s)
      local lost = loseUsers(s, 0.08)
      s.monetize = math.max(0, s.monetize - 5)
      s.hype = math.min(MAX_STAT, s.hype + 5)
      return {
        { label = "ユーザー", val = -lost, suffix = "人" },
        { label = "課金圧", val = -5 },
        { label = "話題性(悪名)", val = 5 },
      }
    end,
  },
  {
    name = "チーター横行",
    effectDesc = "ユーザー -5%\n技術力 -5",
    isNegative = true,
    condition = function(s) return s.tech < 35 and s.users > 3000 end,
    apply = function(s)
      local lost = loseUsers(s, 0.05)
      s.tech = math.max(0, s.tech - 5)
      return {
        { label = "ユーザー", val = -lost, suffix = "人" },
        { label = "技術力", val = -5 },
      }
    end,
  },
  {
    name = "セルラン圏外転落",
    effectDesc = "話題性 -15",
    isNegative = true,
    condition = function(s) return s.lastRevenue < 150 end,
    apply = function(s)
      s.hype = math.max(0, s.hype - 15)
      return { { label = "話題性", val = -15 } }
    end,
  },
}

local positiveEvents = {
  {
    name = "セルラン1位！",
    effectDesc = "話題性 +20\nユーザー +10%",
    isNegative = false,
    condition = function(s) return s.lastRevenue > 500 end,
    apply = function(s)
      s.hype = math.min(MAX_STAT, s.hype + 20)
      local gu = addUsers(s, 0.10)
      return {
        { label = "話題性", val = 20 },
        { label = "ユーザー", val = gu, suffix = "人" },
      }
    end,
  },
  {
    name = "Twitterでバズった",
    effectDesc = "話題性 +15\nユーザー +5%",
    isNegative = false,
    condition = function(s) return s.content > 60 end,
    apply = function(s)
      s.hype = math.min(MAX_STAT, s.hype + 15)
      local gu = addUsers(s, 0.05)
      return {
        { label = "話題性", val = 15 },
        { label = "ユーザー", val = gu, suffix = "人" },
      }
    end,
  },
  {
    name = "二次創作が増加",
    effectDesc = "話題性 +10\nコンテンツ力 +5",
    isNegative = false,
    condition = function(s) return s.content > 50 and s.hype > 40 end,
    apply = function(s)
      s.hype = math.min(MAX_STAT, s.hype + 10)
      s.content = math.min(MAX_STAT, s.content + 5)
      return {
        { label = "話題性", val = 10 },
        { label = "コンテンツ力", val = 5 },
      }
    end,
  },
  {
    name = "ストアフィーチャー",
    effectDesc = "ユーザー +20%",
    isNegative = false,
    condition = function(s) return s.content > 60 and s.tech > 50 end,
    apply = function(s)
      local gu = addUsers(s, 0.20)
      return { { label = "ユーザー", val = gu, suffix = "人" } }
    end,
  },
  {
    name = "攻略wikiが充実",
    effectDesc = "ユーザー離脱率が3ターン低下",
    isNegative = false,
    condition = function(s) return s.users > 5000 end,
    apply = function(s)
      s.churnReduction = 3
      s.churnReductionAmt = 0.02
      return { { label = "離脱率低下", val = -2, suffix = "% (3ターン)" } }
    end,
  },
  {
    name = "投資家から出資",
    effectDesc = "資金 +300万（借金ではない）",
    isNegative = false,
    condition = function(s) return s.users > 8000 and s.money > 0 end,
    apply = function(s)
      s.money = s.money + 300
      return { { label = "資金", val = 300, suffix = "万" } }
    end,
  },
}

-- ===== ゲーム状態 =====
local gameState = "title"
local subState = "select"

local menu = { items = { "スタート", "終了" }, selected = 1 }

local state = {}
local stateSnapshot = {}
local hand = {}
local selectedCard = 1
local lastOutcome = {}
local turnReport = {}
local releaseResult = nil

-- スナップショット取得
local function takeSnapshot()
  stateSnapshot = {
    users = state.users,
    money = state.money,
    debt = state.debt,
    content = state.content,
    tech = state.tech,
    hype = state.hype,
    monetize = state.monetize,
    energy = state.energy,
    preregUsers = state.preregUsers,
  }
end

-- フォント
local titleFont, menuFont, smallFont, tinyFont

-- ===== 初期化 =====
local function initState()
  state = {
    -- フェーズ管理
    phase = "dev",           -- "dev" | "ops"
    month = 1,               -- 1-60（全体の月数）
    yearOfPhase = 1,         -- フェーズ内の年数（1-2 or 1-3）
    monthOfYear = 1,         -- 年内の月数（1-12）

    -- リソース（N/C/T）
    N = INITIAL_N,
    C = INITIAL_C,
    T = INITIAL_T,
    maxN = INITIAL_N,
    maxC = INITIAL_C,
    maxT = INITIAL_T,

    -- 経済
    money = INITIAL_DEBT,
    debt = INITIAL_DEBT,

    -- 運営指標（運営フェーズのみ）
    players = 0,
    cellRank = 0,           -- セルラン順位（1-100, 0=圏外）
    storeRating = 3.0,      -- ストア評価（1.0-5.0）
    monthlySales = 0,

    -- 月進行管理
    currentMonthEvents = {},
    actionsRemaining = ACTIONS_PER_MONTH,

    -- アイテム（後回し）
    items = {},
  }

  selectedCard = 1
  selectedEventIndex = 0    -- 0=通常行動選択中
  subState = "month_start_display"
  hand = {}
  lastOutcome = {}
  monthEndReport = {}
  releaseResult = nil
end

-- ===== 月進行ロジック =====

-- 月初処理
local function processMonthStart()
  -- 1. N/C/T全回復
  state.N = state.maxN
  state.C = state.maxC
  state.T = state.maxT

  -- 2. イベント4件生成（後で実装）
  state.currentMonthEvents = {}  -- TODO: generateMonthlyEvents()

  -- 3. 行動回数リセット
  state.actionsRemaining = ACTIONS_PER_MONTH

  -- 4. 画面遷移
  subState = "month_start_display"
end

-- 月末処理
local function processMonthEnd()
  local report = {}

  -- 1. 未対応リスクイベントの処理（後で実装）

  -- 2. 収支計算（運営フェーズのみ）
  if state.phase == "ops" then
    -- TODO: 収支計算実装
  end

  -- 3. フェーズ移行チェック
  if state.month == DEV_MONTHS then
    -- 開発→運営移行
    subState = "release"
    return report
  elseif state.month == DEBT_DEADLINE then
    -- 運営1年目終了→借金判定
    if state.debt > 0 then
      gameState = "gameover"
      return report
    end
  elseif state.month == TOTAL_MONTHS then
    -- 運営3年目終了→最終評価
    subState = "final_evaluation"
    return report
  end

  -- 4. 次月へ進行
  state.month = state.month + 1
  updateMonthInfo()
  processMonthStart()

  monthEndReport = report
  return report
end

-- 月情報の更新
local function updateMonthInfo()
  if state.month <= DEV_MONTHS then
    state.phase = "dev"
    state.yearOfPhase = math.floor((state.month - 1) / 12) + 1
  else
    state.phase = "ops"
    state.yearOfPhase = math.floor((state.month - DEV_MONTHS - 1) / 12) + 1
  end
  state.monthOfYear = ((state.month - 1) % 12) + 1
end

-- ===== カード抽選 =====
local function drawOneCard(exclude)
  local pool, rarePool
  if state.phase == "dev" then
    pool = devCards
    rarePool = nil
  else
    pool = opsNormalCards
    rarePool = opsRareCards
  end

  local useRare = rarePool and math.random(100) <= 15
  local source = useRare and rarePool or pool

  for _ = 1, 10 do
    local card = source[math.random(#source)]
    local dup = false
    for _, ex in ipairs(exclude) do
      if ex.name == card.name then dup = true; break end
    end
    if not dup then return card end
  end
  return pool[1]
end

local function drawHand()
  hand = {}
  for i = 1, 3 do
    hand[i] = drawOneCard(hand)
  end
  selectedCard = 1
end

-- ===== 強制イベント抽選 =====
local function rollForcedEvent()
  if state.phase ~= "ops" then return nil end
  if math.random() > FORCED_EVENT_CHANCE then return nil end

  local eligNeg, eligPos = {}, {}
  for _, e in ipairs(negativeEvents) do
    if e.condition(state) then table.insert(eligNeg, e) end
  end
  for _, e in ipairs(positiveEvents) do
    if e.condition(state) then table.insert(eligPos, e) end
  end

  if #eligNeg == 0 and #eligPos == 0 then return nil end

  local pool
  if #eligNeg == 0 then pool = eligPos
  elseif #eligPos == 0 then pool = eligNeg
  elseif math.random() < 0.5 then pool = eligNeg
  else pool = eligPos
  end

  return pool[math.random(#pool)]
end

-- ===== ターン開始処理 =====
local function processTurnStart()
  local report = {}

  if state.phase == "dev" then
    -- 開発期: 利子のみ
    local interest = math.floor(state.debt * INTEREST_RATE)
    state.money = state.money - interest
    table.insert(report, { label = "利子", val = -interest, suffix = "万" })

    -- 体力回復
    local prev = state.energy
    state.energy = math.min(MAX_ENERGY, state.energy + ENERGY_RECOVERY)
    local rec = state.energy - prev
    if rec > 0 then
      table.insert(report, { label = "体力回復", val = rec })
    end

    -- 残りターン表示
    local remain = DEV_TURNS - state.turn + 1
    table.insert(report, { label = "リリースまで", val = remain, suffix = "ターン" })

  elseif state.phase == "ops" then
    state.opsTurn = state.opsTurn + 1

    -- 売上
    local revenue = math.floor(state.users * state.monetize / REVENUE_DIVISOR)
    state.money = state.money + revenue
    state.lastRevenue = revenue
    table.insert(report, { label = "売上", val = revenue, suffix = "万" })

    -- 維持費
    local maint = math.floor(state.users / MAINT_USER_DIVISOR) + MAINT_BASE + state.opsTurn * MAINT_TURN_COEFF
    state.money = state.money - maint
    table.insert(report, { label = "維持費", val = -maint, suffix = "万" })

    -- 利子
    if state.debt > 0 then
      local interest = math.floor(state.debt * INTEREST_RATE)
      state.money = state.money - interest
      table.insert(report, { label = "利子", val = -interest, suffix = "万" })
    end

    -- 自動返済
    local net = revenue - maint - math.floor(state.debt * INTEREST_RATE)
    if net > 0 and state.debt > 0 then
      local repay = math.min(math.floor(net * AUTO_REPAY_RATIO), state.debt)
      state.debt = state.debt - repay
      state.money = state.money - repay
      table.insert(report, { label = "返済", val = -repay, suffix = "万" })
    end

    -- 新規流入
    local inflow = math.floor(state.users * (state.hype / 500))
    state.users = state.users + inflow

    -- 離脱
    local baseChurn = 0.07 + state.monetize / 400 - state.content / 1000
    if state.churnReduction > 0 then
      baseChurn = baseChurn - state.churnReductionAmt
      state.churnReduction = state.churnReduction - 1
    end
    local churnRate = math.max(0, baseChurn + state.opsTurn * 0.002)
    local churn = math.floor(state.users * churnRate)
    state.users = math.max(0, state.users - churn)

    local netUsers = inflow - churn
    local sign = netUsers >= 0 and "+" or ""
    table.insert(report, {
      label = "ユーザー", val = netUsers, suffix = "人",
      text = sign .. netUsers .. "人"
    })

    -- 話題性減衰
    local hypeDecay = 5 + math.floor((state.opsTurn - 1) / 8)
    hypeDecay = math.min(hypeDecay, state.hype)
    state.hype = math.max(0, state.hype - hypeDecay)
    if hypeDecay > 0 then
      table.insert(report, { label = "話題性減衰", val = -hypeDecay })
    end

    -- コンテンツ力減衰（マンネリ化）
    local contentDecay = 2 + math.floor((state.opsTurn - 1) / 12)
    contentDecay = math.min(contentDecay, state.content)
    state.content = math.max(0, state.content - contentDecay)
    if contentDecay > 0 then
      table.insert(report, { label = "マンネリ化", val = -contentDecay })
    end

    -- 体力回復
    local prev = state.energy
    state.energy = math.min(MAX_ENERGY, state.energy + ENERGY_RECOVERY)
    local rec = state.energy - prev
    if rec > 0 then
      table.insert(report, { label = "体力回復", val = rec })
    end
  end

  turnReport = report
end

-- ===== リリース判定 =====
local function executeRelease()
  local baseUsers = state.content * 100 + state.hype * 50 + state.preregUsers

  local bonus = 1.0
  if state.content >= 50 and state.tech >= 40 then
    bonus = 1.3
  elseif state.content >= 30 and state.tech >= 20 then
    bonus = 1.0
  elseif state.content < 20 or state.tech < 15 then
    bonus = 0.5
  else
    bonus = 0.7
  end

  state.users = math.max(500, math.floor(baseUsers * bonus))
  state.phase = "ops"
  state.opsTurn = 0
  if state.monetize < 10 then state.monetize = 10 end

  releaseResult = {
    baseUsers = math.floor(baseUsers),
    bonus = bonus,
    finalUsers = state.users,
    content = state.content,
    tech = state.tech,
    hype = state.hype,
    preregUsers = state.preregUsers,
    money = state.money,
    debt = state.debt,
  }
  return releaseResult
end

-- ===== カード実行 =====
local function executeCard(card)
  takeSnapshot()
  local outcome = {
    cardName = card.name,
    rarity = card.rarity,
    success = true,
    critical = false,
    results = {},
    message = "",
  }

  -- 大成功判定
  local critRate = calculateCriticalRate(card)
  local isCritical = math.random() < critRate
  local mult = isCritical and CRITICAL_MULTIPLIER or 1.0

  outcome.results = card.apply(state, mult)
  if isCritical then
    outcome.critical = true
    outcome.message = "大成功！"
  else
    outcome.message = "成功！"
  end

  -- 体力消費
  state.energy = math.max(0, state.energy - card.energyCost)
  if card.energyCost > 0 then
    table.insert(outcome.results, { label = "体力", val = -card.energyCost })
  end

  return outcome
end

-- ===== 休養実行 =====
local function executeRest()
  takeSnapshot()
  local prev = state.energy
  state.energy = math.min(MAX_ENERGY, state.energy + 30)
  local gain = state.energy - prev
  return {
    cardName = "休養",
    rarity = "rest",
    success = true,
    critical = false,
    results = { { label = "体力", val = gain } },
    message = "ゆっくり休んだ！",
  }
end

-- ===== 勝敗判定 =====
local function checkGameOver()
  if state.phase == "dev" then
    return state.money <= 0
  else
    return state.users <= 0 or state.money <= 0
  end
end

local function checkWin()
  return state.phase == "ops" and state.debt <= 0
end

local function getGameOverReason()
  if state.phase == "dev" then
    return "開発資金が尽きた..."
  elseif state.users <= 0 and state.money <= 0 then
    return "ユーザーゼロ＆資金枯渇..."
  elseif state.users <= 0 then
    return "ユーザーがいなくなった..."
  else
    return "資金が尽きた..."
  end
end

-- ===== 次ターン遷移ヘルパー =====
local function advanceToNextTurn()
  state.turn = state.turn + 1

  -- 開発期→運営期への遷移チェック
  if state.phase == "dev" and state.turn > DEV_TURNS then
    executeRelease()
    subState = "release"
    return
  end

  processTurnStart()

  if checkGameOver() then
    gameState = "gameover"
    return
  end

  if checkWin() then
    subState = "win"
    return
  end

  -- 強制イベント判定
  local event = rollForcedEvent()
  if event then
    takeSnapshot()
    lastOutcome = {
      cardName = event.name,
      rarity = event.isNegative and "disaster" or "lucky",
      success = true,
      critical = false,
      results = event.apply(state),
      message = event.isNegative and "発生！" or "朗報！",
    }
    subState = "forced_event"
    return
  end

  drawHand()
  subState = "select"
end

-- ===== Love2D コールバック =====
function love.load()
  love.window.setTitle("ソシャゲ運営ローグライク — 借金返済編")
  love.window.setMode(800, 600, { resizable = true, fullscreen = false })
  love.graphics.setDefaultFilter("linear", "linear")

  math.randomseed(os.time())
  math.random(); math.random(); math.random()

  titleFont = love.graphics.newFont(FONT_PATH, 32)
  menuFont  = love.graphics.newFont(FONT_PATH, 22)
  smallFont = love.graphics.newFont(FONT_PATH, 16)
  tinyFont  = love.graphics.newFont(FONT_PATH, 13)

  initState()
end

function love.keypressed(key)
  -- F11でボーダーレスフルスクリーン切り替え
  if key == "f11" then
    isBorderlessFullscreen = not isBorderlessFullscreen
    if isBorderlessFullscreen then
      local _, _, flags = love.window.getMode()
      local dw, dh = love.window.getDesktopDimensions(flags.display or 1)
      love.window.setMode(dw, dh, { resizable = false, borderless = true, fullscreen = false })
      love.window.setPosition(0, 0, flags.display or 1)
    else
      love.window.setMode(800, 600, { resizable = true, borderless = false, fullscreen = false })
    end
    return
  end

  if gameState == "title" then
    if key == "up" then
      menu.selected = menu.selected - 1
      if menu.selected < 1 then menu.selected = #menu.items end
    elseif key == "down" then
      menu.selected = menu.selected + 1
      if menu.selected > #menu.items then menu.selected = 1 end
    elseif key == "return" or key == "space" then
      if menu.selected == 1 then
        initState()
        processTurnStart()
        drawHand()
        gameState = "game"
        subState = "select"
      elseif menu.selected == 2 then
        love.event.quit()
      end
    end

  elseif gameState == "game" then
    if subState == "select" then
      if key == "left" then
        if selectedCard == 4 then selectedCard = 3
        else
          selectedCard = selectedCard - 1
          if selectedCard < 1 then selectedCard = 3 end
        end
      elseif key == "right" then
        if selectedCard == 4 then selectedCard = 1
        else
          selectedCard = selectedCard + 1
          if selectedCard > 3 then selectedCard = 1 end
        end
      elseif key == "down" then
        selectedCard = 4
      elseif key == "up" then
        if selectedCard == 4 then selectedCard = 2 end
      elseif key == "return" or key == "space" then
        if selectedCard == 4 then
          lastOutcome = executeRest()
          subState = "outcome"
        else
          local card = hand[selectedCard]
          if state.energy < card.energyCost and card.energyCost > 0 then
            return
          end
          lastOutcome = executeCard(card)
          subState = "outcome"
        end
      elseif key == "escape" then
        gameState = "title"
        menu.selected = 1
      end

    elseif subState == "outcome" then
      if key == "return" or key == "space" then
        if checkGameOver() then
          gameState = "gameover"
        elseif checkWin() then
          subState = "win"
        else
          advanceToNextTurn()
        end
      end

    elseif subState == "forced_event" then
      if key == "return" or key == "space" then
        if checkGameOver() then
          gameState = "gameover"
        elseif checkWin() then
          subState = "win"
        else
          drawHand()
          subState = "select"
        end
      end

    elseif subState == "release" then
      if key == "return" or key == "space" then
        processTurnStart()
        local event = rollForcedEvent()
        if event then
          takeSnapshot()
          lastOutcome = {
            cardName = event.name,
            rarity = event.isNegative and "disaster" or "lucky",
            success = true,
            critical = false,
            results = event.apply(state),
            message = event.isNegative and "発生！" or "朗報！",
          }
          subState = "forced_event"
        else
          drawHand()
          subState = "select"
        end
      end

    elseif subState == "win" then
      if key == "return" or key == "space" then
        gameState = "title"
        menu.selected = 1
      end
    end

  elseif gameState == "gameover" then
    if key == "return" or key == "space" then
      gameState = "title"
      menu.selected = 1
    end
  end
end

function love.update(dt)
end

-- ===== 描画 =====
local BASE_W, BASE_H = 800, 600
local isBorderlessFullscreen = false

function love.draw()
  local realW, realH = love.graphics.getDimensions()
  local scaleX = realW / BASE_W
  local scaleY = realH / BASE_H
  local scale = math.min(scaleX, scaleY)
  local offsetX = (realW - BASE_W * scale) / 2
  local offsetY = (realH - BASE_H * scale) / 2

  love.graphics.push()
  love.graphics.translate(offsetX, offsetY)
  love.graphics.scale(scale, scale)

  if gameState == "title" then
    drawTitleScreen()
  elseif gameState == "game" then
    if subState == "select" then
      drawSelectScreen()
    elseif subState == "outcome" then
      drawOutcomeScreen()
    elseif subState == "forced_event" then
      drawForcedEventScreen()
    elseif subState == "release" then
      drawReleaseScreen()
    elseif subState == "win" then
      drawWinScreen()
    end
  elseif gameState == "gameover" then
    drawGameOverScreen()
  end

  love.graphics.pop()

  -- レターボックス
  if offsetX > 0 then
    love.graphics.setColor(0, 0, 0)
    love.graphics.rectangle("fill", 0, 0, offsetX, realH)
    love.graphics.rectangle("fill", realW - offsetX, 0, offsetX, realH)
  end
  if offsetY > 0 then
    love.graphics.setColor(0, 0, 0)
    love.graphics.rectangle("fill", 0, 0, realW, offsetY)
    love.graphics.rectangle("fill", 0, realH - offsetY, realW, offsetY)
  end
end

-- ===== 描画: タイトル =====
function drawTitleScreen()
  local w, h = BASE_W, BASE_H
  love.graphics.clear(0.06, 0.06, 0.12)

  love.graphics.setFont(titleFont)
  love.graphics.setColor(1, 0.4, 0.4)
  boldPrintf("ソシャゲ運営ローグライク", 0, h * 0.15, w, "center")

  love.graphics.setFont(menuFont)
  love.graphics.setColor(1, 0.85, 0.3)
  boldPrintf("— 借金返済編 —", 0, h * 0.15 + 45, w, "center")

  love.graphics.setFont(smallFont)
  love.graphics.setColor(0.6, 0.6, 0.7)
  boldPrintf("借金してソシャゲを作り、運営して完済せよ！", 0, h * 0.15 + 80, w, "center")

  love.graphics.setFont(tinyFont)
  love.graphics.setColor(0.5, 0.5, 0.6)
  boldPrintf(
    string.format("開発期%dヶ月 → リリース → 運営期（借金%d万を返済）", DEV_TURNS, INITIAL_DEBT),
    0, h * 0.15 + 105, w, "center"
  )

  love.graphics.setFont(menuFont)
  for i, item in ipairs(menu.items) do
    local y = h * 0.55 + (i - 1) * 45
    if i == menu.selected then
      love.graphics.setColor(1, 1, 0)
      boldPrintf("> " .. item .. " <", 0, y, w, "center")
    else
      love.graphics.setColor(0.7, 0.7, 0.7)
      boldPrintf(item, 0, y, w, "center")
    end
  end

  love.graphics.setFont(tinyFont)
  love.graphics.setColor(0.4, 0.4, 0.4)
  boldPrintf("↑↓: 選択  Enter: 決定", 0, h - 30, w, "center")
end

-- ===== 描画: カード選択画面 =====
function drawSelectScreen()
  local w = BASE_W
  love.graphics.clear(0.08, 0.08, 0.14)

  love.graphics.setFont(smallFont)

  -- フェーズ + ターン
  local phaseStr = state.phase == "dev" and "【開発期】" or "【運営期】"
  love.graphics.setColor(state.phase == "dev" and {0.4, 0.8, 1} or {0.4, 1, 0.6})
  boldPrint(phaseStr .. " " .. turnToDateStr(state.turn), 15, 8)

  -- ユーザー or 事前登録
  if state.phase == "dev" then
    love.graphics.setColor(0.4, 0.9, 1)
    boldPrint(string.format("事前登録: %d人", state.preregUsers), 250, 8)
  else
    love.graphics.setColor(0.4, 0.9, 1)
    boldPrint(string.format("ユーザー: %d人", state.users), 250, 8)
  end

  -- 資金
  local moneyColor = state.money < 200 and {1, 0.3, 0.3} or {1, 0.9, 0.3}
  love.graphics.setColor(moneyColor)
  boldPrint(string.format("資金: %d万", state.money), 440, 8)

  -- 借金
  if state.debt > 0 then
    love.graphics.setColor(1, 0.4, 0.4)
    boldPrint(string.format("借金: %d万", state.debt), 580, 8)
  else
    love.graphics.setColor(0.4, 1, 0.4)
    boldPrint("借金: 完済！", 580, 8)
  end

  -- 区切り
  love.graphics.setColor(0.25, 0.25, 0.35)
  love.graphics.line(10, 32, w - 10, 32)

  -- 4ステータス + 体力
  love.graphics.setFont(tinyFont)
  local sx = 15
  for i, key in ipairs(statOrder) do
    local x = sx + (i - 1) * 140
    drawStatMini(x, 38, statNames[key], state[key], MAX_STAT)
  end
  drawBarSimple(575, 36, 90, 14, state.energy, MAX_ENERGY, "体力", {0.3, 0.8, 0.3})

  -- 区切り
  love.graphics.setColor(0.25, 0.25, 0.35)
  love.graphics.line(10, 56, w - 10, 56)

  -- 収支レポート
  love.graphics.setFont(tinyFont)
  local ry = 61
  love.graphics.setColor(0.6, 0.6, 0.7)
  boldPrint("【今月】", 15, ry)
  local rx = 75
  for _, r in ipairs(turnReport) do
    local text
    if r.text then
      text = r.label .. ": " .. r.text
    else
      local s = r.val >= 0 and "+" or ""
      text = r.label .. " " .. s .. r.val .. (r.suffix or "")
    end
    if r.val >= 0 then
      love.graphics.setColor(0.4, 0.9, 0.5)
    else
      love.graphics.setColor(1, 0.5, 0.4)
    end
    boldPrint(text, rx, ry)
    rx = rx + tinyFont:getWidth(text) + 12
    if rx > w - 60 then
      rx = 75
      ry = ry + 16
    end
  end

  -- 区切り
  local cardTop = 92
  love.graphics.setColor(0.25, 0.25, 0.35)
  love.graphics.line(10, cardTop - 4, w - 10, cardTop - 4)

  -- カード3枚
  love.graphics.setFont(tinyFont)
  love.graphics.setColor(0.9, 0.9, 1)
  boldPrint("【行動カードを選べ】", 15, cardTop)

  local cardW = 230
  local cardH = 390
  local gap = 20
  local totalW = cardW * 3 + gap * 2
  local startX = (w - totalW) / 2
  local cardY = cardTop + 20

  for i, card in ipairs(hand) do
    local cx = startX + (i - 1) * (cardW + gap)
    local isSelected = (i == selectedCard)
    local canUse = card.energyCost == 0 or state.energy >= card.energyCost
    drawCard(cx, cardY, cardW, cardH, card, isSelected, canUse)
  end

  -- 休養ボタン
  local restY = cardY + cardH + 8
  local restW = totalW
  local restH = 36
  local restX = startX
  local restSelected = (selectedCard == 4)

  love.graphics.setColor(restSelected and {0.18, 0.25, 0.18} or {0.12, 0.15, 0.12})
  love.graphics.rectangle("fill", restX, restY, restW, restH, 6, 6)

  love.graphics.setLineWidth(restSelected and 3 or 1)
  love.graphics.setColor(restSelected and {0.4, 1, 0.4} or {0.3, 0.5, 0.3})
  love.graphics.rectangle("line", restX, restY, restW, restH, 6, 6)

  love.graphics.setFont(smallFont)
  love.graphics.setColor(restSelected and {0.4, 1, 0.4} or {0.5, 0.7, 0.5})
  boldPrintf("↓ 休養（体力 +30）", restX, restY + 8, restW, "center")

  -- 操作説明
  love.graphics.setFont(tinyFont)
  love.graphics.setColor(0.4, 0.4, 0.5)
  boldPrintf("←→: カード選択  ↓: 休養  Enter: 決定  Esc: タイトル", 0, 580, w, "center")
end

-- ===== 描画: カード1枚 =====
function drawCard(x, y, w, h, card, isSelected, canUse)
  local borderColor
  if card.rarity == "rare" then
    borderColor = {1, 0.85, 0.2}
  else
    borderColor = {0.5, 0.5, 0.7}
  end

  local bgColor
  if isSelected then
    bgColor = {0.18, 0.18, 0.3}
  else
    bgColor = {0.12, 0.12, 0.2}
  end
  if not canUse then
    bgColor = {0.08, 0.08, 0.1}
  end

  love.graphics.setColor(bgColor)
  love.graphics.rectangle("fill", x, y, w, h, 8, 8)

  love.graphics.setLineWidth(isSelected and 3 or 1)
  love.graphics.setColor(isSelected and {1, 1, 0.5} or borderColor)
  love.graphics.rectangle("line", x, y, w, h, 8, 8)

  -- レアリティラベル
  love.graphics.setFont(tinyFont)
  if card.rarity == "rare" then
    love.graphics.setColor(1, 0.85, 0.2)
    boldPrintf("★ レア", x, y + 6, w, "center")
  end

  -- カード名
  love.graphics.setFont(menuFont)
  if not canUse then
    love.graphics.setColor(0.4, 0.4, 0.4)
  elseif card.rarity == "rare" then
    love.graphics.setColor(1, 0.95, 0.7)
  else
    love.graphics.setColor(1, 1, 1)
  end
  boldPrintf(card.name, x + 5, y + 24, w - 10, "center")

  -- 区切り線
  love.graphics.setColor(borderColor[1], borderColor[2], borderColor[3], 0.3)
  love.graphics.line(x + 10, y + 54, x + w - 10, y + 54)

  -- 効果テキスト
  love.graphics.setFont(tinyFont)
  love.graphics.setColor(not canUse and {0.4, 0.4, 0.4} or {0.7, 0.9, 1})
  boldPrintf(card.effectDesc, x + 10, y + 62, w - 20, "center")

  -- 大成功率
  if card.critStat then
    local critRate = math.floor(calculateCriticalRate(card) * 100)
    love.graphics.setFont(tinyFont)
    love.graphics.setColor(1, 0.85, 0.3)
    boldPrintf(string.format("大成功率 %d%%", critRate), x, y + h - 55, w, "center")
  end

  -- 体力不足
  if not canUse then
    love.graphics.setFont(tinyFont)
    love.graphics.setColor(1, 0.3, 0.3)
    boldPrintf("体力不足！", x, y + h - 38, w, "center")
  end

  -- 体力コスト
  if card.energyCost > 0 then
    love.graphics.setFont(tinyFont)
    love.graphics.setColor(0.6, 0.6, 0.6)
    boldPrintf(string.format("体力 -%d", card.energyCost), x, y + h - 22, w, "center")
  end
end

-- ===== 描画: 結果画面 =====
function drawOutcomeScreen()
  local w, h = BASE_W, BASE_H
  love.graphics.clear(0.08, 0.08, 0.14)

  local boxX, boxY, boxW, boxH = 60, 20, w - 120, h - 40
  love.graphics.setColor(0.12, 0.12, 0.22)
  love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 10, 10)

  local borderCol = lastOutcome.critical and {1, 0.85, 0.2} or {0.4, 0.4, 0.6}
  love.graphics.setColor(borderCol)
  love.graphics.setLineWidth(lastOutcome.critical and 3 or 2)
  love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 10, 10)

  -- カード名
  love.graphics.setFont(menuFont)
  if lastOutcome.rarity == "rare" then
    love.graphics.setColor(1, 0.9, 0.4)
  elseif lastOutcome.rarity == "rest" then
    love.graphics.setColor(0.4, 0.9, 0.4)
  else
    love.graphics.setColor(0.8, 0.8, 1)
  end
  boldPrintf(lastOutcome.cardName, boxX, boxY + 15, boxW, "center")

  -- 成功メッセージ
  love.graphics.setFont(menuFont)
  if lastOutcome.critical then
    love.graphics.setColor(1, 0.85, 0.2)
  else
    love.graphics.setColor(0.3, 1, 0.4)
  end
  boldPrintf(lastOutcome.message, boxX, boxY + 48, boxW, "center")

  -- 結果
  love.graphics.setFont(smallFont)
  local dy = boxY + 85
  for _, r in ipairs(lastOutcome.results) do
    local sign = r.val >= 0 and "+" or ""
    local suffix = r.suffix or ""
    love.graphics.setColor(r.val >= 0 and {0.3, 1, 0.5} or {1, 0.5, 0.4})
    boldPrintf(
      string.format("%s %s%d%s", r.label, sign, r.val, suffix),
      boxX, dy, boxW, "center"
    )
    dy = dy + 26
  end

  -- ビフォーアフター表示
  dy = dy + 10
  drawBeforeAfter(boxX, dy, boxW)

  love.graphics.setFont(smallFont)
  love.graphics.setColor(0.5, 0.5, 0.6)
  boldPrintf("[Enterで続ける]", boxX, boxY + boxH - 35, boxW, "center")
end

-- ===== 描画: 強制イベント画面 =====
function drawForcedEventScreen()
  local w, h = BASE_W, BASE_H
  love.graphics.clear(0.08, 0.08, 0.14)

  local boxX, boxY, boxW, boxH = 60, 20, w - 120, h - 40
  love.graphics.setColor(0.12, 0.12, 0.22)
  love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 10, 10)

  local isNeg = lastOutcome.rarity == "disaster"
  local borderCol = isNeg and {1, 0.3, 0.3} or {0.3, 0.8, 1}
  love.graphics.setColor(borderCol)
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 10, 10)

  -- ヘッダー
  love.graphics.setFont(smallFont)
  love.graphics.setColor(borderCol)
  boldPrintf(
    isNeg and "【トラブル発生！】" or "【朗報！】",
    boxX, boxY + 15, boxW, "center"
  )

  -- イベント名
  love.graphics.setFont(menuFont)
  love.graphics.setColor(isNeg and {1, 0.4, 0.4} or {0.4, 0.9, 1})
  boldPrintf(lastOutcome.cardName, boxX, boxY + 45, boxW, "center")

  -- 結果
  love.graphics.setFont(smallFont)
  local dy = boxY + 85
  for _, r in ipairs(lastOutcome.results) do
    local sign = r.val >= 0 and "+" or ""
    local suffix = r.suffix or ""
    love.graphics.setColor(r.val >= 0 and {0.3, 1, 0.5} or {1, 0.5, 0.4})
    boldPrintf(
      string.format("%s %s%d%s", r.label, sign, r.val, suffix),
      boxX, dy, boxW, "center"
    )
    dy = dy + 26
  end

  -- ビフォーアフター表示
  dy = dy + 10
  drawBeforeAfter(boxX, dy, boxW)

  love.graphics.setFont(smallFont)
  love.graphics.setColor(0.5, 0.5, 0.6)
  boldPrintf("[Enterでカード選択へ]", boxX, boxY + boxH - 35, boxW, "center")
end

-- ===== 描画: リリース画面 =====
function drawReleaseScreen()
  local w, h = BASE_W, BASE_H
  love.graphics.clear(0.06, 0.06, 0.15)

  love.graphics.setFont(titleFont)
  love.graphics.setColor(1, 0.85, 0.3)
  boldPrintf("リリース！", 0, 30, w, "center")

  love.graphics.setFont(menuFont)
  love.graphics.setColor(0.8, 0.8, 0.9)
  boldPrintf("あなたのソシャゲがついにリリースされた！", 0, 80, w, "center")

  if releaseResult then
    local r = releaseResult
    love.graphics.setFont(smallFont)
    local sy = 140
    local cx = w / 2 - 150

    love.graphics.setColor(0.6, 0.6, 0.7)
    boldPrint(string.format("コンテンツ力: %d", r.content), cx, sy)
    boldPrint(string.format("技術力: %d", r.tech), cx, sy + 25)
    boldPrint(string.format("話題性: %d", r.hype), cx, sy + 50)
    boldPrint(string.format("事前登録: %d人", r.preregUsers), cx, sy + 75)

    -- 計算式
    sy = sy + 115
    love.graphics.setColor(0.5, 0.5, 0.6)
    boldPrintf(
      string.format("基本ユーザー = %d×100 + %d×50 + %d = %d人",
        r.content, r.hype, r.preregUsers, r.baseUsers),
      0, sy, w, "center"
    )

    sy = sy + 28
    local bonusStr
    if r.bonus >= 1.3 then bonusStr = "好評スタート！ (×1.3)"
    elseif r.bonus >= 1.0 then bonusStr = "普通のスタート (×1.0)"
    elseif r.bonus >= 0.7 then bonusStr = "やや低評価... (×0.7)"
    else bonusStr = "大炎上スタート... (×0.5)"
    end
    love.graphics.setColor(r.bonus >= 1.0 and {0.4, 1, 0.5} or {1, 0.5, 0.4})
    boldPrintf(bonusStr, 0, sy, w, "center")

    -- 最終ユーザー数
    sy = sy + 50
    love.graphics.setFont(titleFont)
    love.graphics.setColor(0.4, 0.9, 1)
    boldPrintf(string.format("初期ユーザー: %d人", r.finalUsers), 0, sy, w, "center")

    -- 残り情報
    sy = sy + 60
    love.graphics.setFont(smallFont)
    love.graphics.setColor(1, 0.9, 0.3)
    boldPrintf(string.format("残り資金: %d万  借金残高: %d万", r.money, r.debt), 0, sy, w, "center")
  end

  love.graphics.setFont(smallFont)
  love.graphics.setColor(0.5, 0.5, 0.6)
  boldPrintf("[Enterで運営期を開始]", 0, h - 50, w, "center")
end

-- ===== 描画: 勝利画面 =====
function drawWinScreen()
  local w, h = BASE_W, BASE_H
  love.graphics.clear(0.05, 0.08, 0.05)

  love.graphics.setFont(titleFont)
  love.graphics.setColor(1, 0.85, 0.2)
  boldPrintf("借金完済！", 0, 60, w, "center")

  love.graphics.setFont(menuFont)
  love.graphics.setColor(0.9, 0.9, 0.8)
  boldPrintf("おめでとう！全ての借金を返済した！", 0, 120, w, "center")

  love.graphics.setFont(smallFont)
  love.graphics.setColor(0.7, 0.7, 0.8)
  local sy = 190
  boldPrintf(
    string.format("運営期間: %s (%dターン)", turnToDateStr(state.turn), state.turn),
    0, sy, w, "center"
  )
  boldPrintf(
    string.format("運営期: %dヶ月", state.opsTurn),
    0, sy + 30, w, "center"
  )
  boldPrintf(
    string.format("最終ユーザー: %d人", state.users),
    0, sy + 60, w, "center"
  )
  boldPrintf(
    string.format("最終資金: %d万円", state.money),
    0, sy + 90, w, "center"
  )
  boldPrintf(
    string.format("コンテンツ力: %d  技術力: %d  話題性: %d  課金圧: %d",
      state.content, state.tech, state.hype, state.monetize),
    0, sy + 120, w, "center"
  )

  -- 評価コメント
  love.graphics.setFont(menuFont)
  love.graphics.setColor(1, 0.85, 0.3)
  local comment
  if state.opsTurn <= 24 then
    comment = "素晴らしい経営手腕！\n短期間での完済は見事！"
  elseif state.opsTurn <= 48 then
    comment = "堅実な運営で借金を返した！\nこれからは自由だ！"
  else
    comment = "長い道のりだったが、ついに完済！\nあなたの粘り勝ちだ！"
  end
  boldPrintf(comment, 100, sy + 170, w - 200, "center")

  love.graphics.setFont(smallFont)
  love.graphics.setColor(0.4, 0.4, 0.4)
  boldPrintf("[Enterでタイトルに戻る]", 0, h - 40, w, "center")
end

-- ===== 描画: ゲームオーバー =====
function drawGameOverScreen()
  local w, h = BASE_W, BASE_H
  love.graphics.clear(0.05, 0.02, 0.02)

  love.graphics.setFont(titleFont)
  love.graphics.setColor(1, 0.2, 0.2)
  boldPrintf("サービス終了", 0, 40, w, "center")

  love.graphics.setFont(menuFont)
  love.graphics.setColor(0.8, 0.5, 0.5)
  boldPrintf(getGameOverReason(), 0, 100, w, "center")

  love.graphics.setFont(smallFont)
  love.graphics.setColor(1, 1, 1)
  local phaseStr = state.phase == "dev" and "開発期" or "運営期"
  boldPrintf(
    string.format("%s %s (%dターン目)", phaseStr, turnToDateStr(state.turn), state.turn),
    0, 160, w, "center"
  )

  love.graphics.setColor(0.6, 0.6, 0.7)
  local sy = 220
  if state.phase == "ops" then
    boldPrintf(
      string.format("運営期間: %dヶ月", state.opsTurn), 0, sy, w, "center")
    sy = sy + 30
  end
  boldPrintf(
    string.format("最終ユーザー: %d人  最終資金: %d万円",
      math.max(0, state.users), state.money),
    0, sy, w, "center"
  )
  sy = sy + 25
  boldPrintf(
    string.format("借金残高: %d万円", state.debt),
    0, sy, w, "center"
  )
  sy = sy + 25
  boldPrintf(
    string.format("コンテンツ力: %d  技術力: %d  話題性: %d  課金圧: %d",
      state.content, state.tech, state.hype, state.monetize),
    0, sy, w, "center"
  )

  love.graphics.setFont(smallFont)
  love.graphics.setColor(0.4, 0.4, 0.4)
  boldPrintf("[Enterでタイトルに戻る]", 0, h - 40, w, "center")
end

-- ===== UI部品 =====
function drawBarSimple(x, y, barW, barH, value, maxVal, label, color)
  local ratio = math.max(0, math.min(1, value / maxVal))
  love.graphics.setFont(tinyFont)
  love.graphics.setColor(1, 1, 1)
  boldPrint(label, x, y + 1)
  local labelW = tinyFont:getWidth(label) + 5
  love.graphics.setColor(0.15, 0.15, 0.25)
  love.graphics.rectangle("fill", x + labelW, y, barW, barH)
  love.graphics.setColor(color)
  love.graphics.rectangle("fill", x + labelW, y, barW * ratio, barH)
  love.graphics.setColor(0.35, 0.35, 0.45)
  love.graphics.rectangle("line", x + labelW, y, barW, barH)
  love.graphics.setColor(1, 1, 1)
  boldPrint(string.format("%d", value), x + labelW + barW + 5, y + 1)
end

function drawStatMini(x, y, label, value, maxVal)
  local barW = 50
  local barH = 12
  local ratio = math.max(0, math.min(1, value / maxVal))

  love.graphics.setColor(0.8, 0.8, 0.9)
  boldPrint(label, x, y)

  local lw = tinyFont:getWidth(label) + 4
  love.graphics.setColor(0.15, 0.15, 0.25)
  love.graphics.rectangle("fill", x + lw, y + 1, barW, barH)

  local r = 1 - ratio * 0.7
  local g = 0.3 + ratio * 0.7
  love.graphics.setColor(r, g, 0.4)
  love.graphics.rectangle("fill", x + lw, y + 1, barW * ratio, barH)

  love.graphics.setColor(0.35, 0.35, 0.45)
  love.graphics.rectangle("line", x + lw, y + 1, barW, barH)

  love.graphics.setColor(1, 1, 1)
  boldPrint(tostring(value), x + lw + barW + 4, y)
end

-- ===== ビフォーアフター差分表示 =====
function drawBeforeAfter(boxX, startY, boxW)
  local snap = stateSnapshot
  if not snap or not snap.money then return startY end

  local items = {}
  -- フェーズに応じて表示項目を変える
  if state.phase == "ops" or (snap.users and snap.users > 0) then
    table.insert(items, { label = "ユーザー", before = snap.users, after = state.users, suffix = "人" })
  end
  if state.phase == "dev" and snap.preregUsers then
    table.insert(items, { label = "事前登録", before = snap.preregUsers, after = state.preregUsers, suffix = "人" })
  end
  table.insert(items, { label = "資金", before = snap.money, after = state.money, suffix = "万" })
  if snap.debt ~= state.debt then
    table.insert(items, { label = "借金", before = snap.debt, after = state.debt, suffix = "万" })
  end
  table.insert(items, { label = "コンテンツ力", before = snap.content, after = state.content, suffix = "" })
  table.insert(items, { label = "技術力", before = snap.tech, after = state.tech, suffix = "" })
  table.insert(items, { label = "話題性", before = snap.hype, after = state.hype, suffix = "" })
  table.insert(items, { label = "課金圧", before = snap.monetize, after = state.monetize, suffix = "" })
  table.insert(items, { label = "体力", before = snap.energy, after = state.energy, suffix = "" })

  -- 変化があった項目のみ表示
  local changed = {}
  for _, item in ipairs(items) do
    if item.before ~= item.after then
      table.insert(changed, item)
    end
  end

  if #changed == 0 then return startY end

  love.graphics.setFont(tinyFont)

  -- ヘッダー
  love.graphics.setColor(0.5, 0.5, 0.6)
  boldPrintf("── ステータス変化 ──", boxX, startY, boxW, "center")
  local dy = startY + 18

  for _, item in ipairs(changed) do
    local diff = item.after - item.before
    local diffSign = diff >= 0 and "+" or ""

    -- ラベル
    love.graphics.setColor(0.7, 0.7, 0.8)
    local labelText = string.format("%-6s", item.label)
    boldPrint(labelText, boxX + 30, dy)

    -- before値
    love.graphics.setColor(0.6, 0.6, 0.6)
    local beforeText = string.format("%d%s", item.before, item.suffix)
    boldPrint(beforeText, boxX + 130, dy)

    -- 矢印
    if diff > 0 then
      love.graphics.setColor(0.3, 1, 0.5)
    elseif diff < 0 then
      love.graphics.setColor(1, 0.4, 0.4)
    else
      love.graphics.setColor(0.6, 0.6, 0.6)
    end
    boldPrint("→", boxX + 220, dy)

    -- after値
    local afterText = string.format("%d%s", item.after, item.suffix)
    boldPrint(afterText, boxX + 240, dy)

    -- 差分
    local diffText = string.format("(%s%d)", diffSign, diff)
    boldPrint(diffText, boxX + 330, dy)

    dy = dy + 17
  end

  return dy
end
