-- ============================================================
-- ソシャゲ運営シミュレーション v5（フェーズ＋流行システム）
-- ============================================================

-- ===== 定数 =====
local FONT_PATH = "fonts/NotoSansJP-Regular.ttf"

-- ゲーム期間
local DEV_MONTHS = 12        -- 開発期：12ヶ月
local OPS_MONTHS = 36        -- 運営期：36ヶ月
local TOTAL_MONTHS = 48      -- 合計：48ヶ月
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

-- オートプレイモード関連
local autoplayRunCount = 0         -- 実行回数
local autoplayCurrentRun = 0       -- 現在の実行番号
local autoplayResults = {}         -- 全プレイの結果を格納
local autoplayInputBuffer = ""     -- 数値入力バッファ（実行回数）
local autoplayDecayInputBuffer = "" -- 数値入力バッファ（流行減衰率）
local autoplayTimer = 0            -- 自動進行タイマー
local autoplayTrendDecay = -2      -- 流行減衰率（設定値）
local autoplayInputField = "count" -- 現在編集中のフィールド ("count" or "decay")

-- フォント
local titleFont, menuFont, smallFont, tinyFont
local isBorderlessFullscreen = false
local isMonthStarted = false  -- 月初フラグ
local itemScrollOffset = 0  -- アイテムスクロールオフセット

-- ===== 太字描画ヘルパー =====
function boldPrint(text, x, y)
  love.graphics.print(text, x + BOLD_OFFSET, y)
  love.graphics.print(text, x, y)
end

function boldPrintf(text, x, y, limit, align)
  love.graphics.printf(text, x + BOLD_OFFSET, y, limit, align)
  love.graphics.printf(text, x, y, limit, align)
end

-- ===== オートプレイ関連関数 =====

-- オートプレイ開始
-- ===== 状態初期化 =====
function initState()
  state = {
    phase = "dev",
    month = 1,
    money = -2000,  -- 初期借金
    N = INITIAL_N,
    C = INITIAL_C,
    T = INITIAL_T,
    maxN = INITIAL_N,
    maxC = INITIAL_C,
    maxT = INITIAL_T,
    trend = 0,
    decay = 0,
    momentum = 0,
    storeRating = 3,
    storeRanking = 50,  -- セルラン（1位～50位+）
    trendLabel = "",
    currentMonthEvents = {},
    futureEvents = {},
    actionsRemaining = ACTIONS_PER_MONTH,
    handledEvents = {},
    items = {},
    recurringRevenue = 0,  -- 恒常収益（毎月発生）
    goals = {
      debtCleared = false,    -- 運営1周年（24ヶ月）で借金完済
      reachedRank1 = false,   -- 運営3周年（48ヶ月）でセルラン1位
    },
  }
end

-- ===== イベント定義 =====
local allEvents = {
  -- プラスイベント（開発期）
  {
    id = "dev_plus_1",
    name = "優秀な人材応募",
    desc = "スキル高い人材が応募してきた",
    type = "plus",
    phase = "dev",
    costN = 5, costC = 0, costT = 0,
    apply = function(s)
      s.maxN = s.maxN + 4
      s.maxC = s.maxC + 2
      return {
        { label = "知名度上限", val = 4 },
        { label = "コンテンツ上限", val = 2 },
      }
    end,
  },
  {
    id = "dev_plus_2",
    name = "協力企業からの支援",
    desc = "パートナー企業からリソース支援",
    type = "plus",
    phase = "dev",
    costN = 0, costC = 3, costT = 3,
    apply = function(s)
      s.maxT = s.maxT + 6
      s.money = s.money + 300
      return {
        { label = "技術力上限", val = 6 },
        { label = "資金", val = 300, suffix = "万" },
      }
    end,
  },
  {
    id = "dev_plus_3",
    name = "技術ブレイクスルー",
    desc = "画期的な技術を発見",
    type = "plus",
    phase = "dev",
    costN = 0, costC = 0, costT = 8,
    apply = function(s)
      s.maxT = s.maxT + 10
      s.maxC = s.maxC + 4
      return {
        { label = "技術力上限", val = 10 },
        { label = "コンテンツ上限", val = 4 },
      }
    end,
  },

  -- マイナスイベント（開発期）
  {
    id = "dev_minus_1",
    name = "主要スタッフ退職",
    desc = "キーメンバーが退職を申し出た",
    type = "minus",
    phase = "dev",
    costN = 3, costC = 3, costT = 3,
    apply = function(s)
      s.maxN = s.maxN + 2
      s.maxC = s.maxC + 2
      s.maxT = s.maxT + 2
      return {
        { label = "全リソース上限", val = 2 },
        { text = "引き留め成功" },
      }
    end,
  },
  {
    id = "dev_minus_2",
    name = "開発機材トラブル",
    desc = "重要な機材が故障した",
    type = "minus",
    phase = "dev",
    costN = 0, costC = 0, costT = 5,
    apply = function(s)
      s.maxT = s.maxT + 4
      return {
        { label = "技術力上限", val = 4 },
        { text = "復旧完了" },
      }
    end,
  },

  -- プラスイベント（運営期）
  {
    id = "ops_plus_1",
    name = "バズる投稿",
    desc = "SNSで大きく話題になった",
    type = "plus",
    phase = "ops",
    costN = 8, costC = 0, costT = 0,
    apply = function(s)
      s.trend = s.trend + 30
      s.money = s.money + 400
      return {
        { label = "流行", val = 30 },
        { label = "資金", val = 400, suffix = "万" },
      }
    end,
  },
  {
    id = "ops_plus_2",
    name = "配信者が紹介",
    desc = "有名配信者が好意的に紹介",
    type = "plus",
    phase = "ops",
    costN = 5, costC = 5, costT = 0,
    apply = function(s)
      s.trend = s.trend + 20
      s.maxN = s.maxN + 6
      return {
        { label = "流行", val = 20 },
        { label = "知名度上限", val = 6 },
      }
    end,
  },
  {
    id = "ops_plus_3",
    name = "アワード受賞",
    desc = "ゲームアワードで受賞",
    type = "plus",
    phase = "ops",
    costN = 6, costC = 6, costT = 0,
    apply = function(s)
      s.trend = s.trend + 40
      s.maxN = s.maxN + 8
      s.money = s.money + 600
      return {
        { label = "流行", val = 40 },
        { label = "知名度上限", val = 8 },
        { label = "資金", val = 600, suffix = "万" },
      }
    end,
  },
  {
    id = "ops_plus_4",
    name = "大型アップデート成功",
    desc = "新コンテンツが大好評",
    type = "plus",
    phase = "ops",
    costN = 0, costC = 8, costT = 5,
    apply = function(s)
      s.trend = s.trend + 24
      s.maxC = s.maxC + 6
      s.money = s.money + 500
      return {
        { label = "流行", val = 24 },
        { label = "コンテンツ上限", val = 6 },
        { label = "資金", val = 500, suffix = "万" },
      }
    end,
  },

  -- マイナスイベント（運営期）
  {
    id = "ops_minus_1",
    name = "重大バグ発生",
    desc = "ゲームが起動しない不具合",
    type = "minus",
    phase = "ops",
    costN = 0, costC = 0, costT = 10,
    apply = function(s)
      s.maxT = s.maxT + 8
      s.trend = s.trend + 10
      return {
        { label = "技術力上限", val = 8 },
        { label = "流行", val = 10 },
        { text = "迅速対応で信頼回復" },
      }
    end,
  },
  {
    id = "ops_minus_2",
    name = "炎上騒動",
    desc = "SNSで炎上してしまった",
    type = "minus",
    phase = "ops",
    costN = 10, costC = 0, costT = 0,
    apply = function(s)
      s.maxN = s.maxN + 6
      s.trend = s.trend + 6
      return {
        { label = "知名度上限", val = 6 },
        { label = "流行", val = 6 },
        { text = "鎮火成功" },
      }
    end,
  },
  {
    id = "ops_minus_3",
    name = "サーバーダウン",
    desc = "アクセス集中でサーバー停止",
    type = "minus",
    phase = "ops",
    costN = 0, costC = 0, costT = 8,
    apply = function(s)
      s.maxT = s.maxT + 10
      s.money = s.money + 200
      return {
        { label = "技術力上限", val = 10 },
        { label = "資金", val = 200, suffix = "万（補償）" },
        { text = "復旧完了" },
      }
    end,
  },
  {
    id = "ops_minus_4",
    name = "ライバルゲーム登場",
    desc = "強力な競合タイトルがリリース",
    type = "minus",
    phase = "ops",
    costN = 8, costC = 8, costT = 0,
    apply = function(s)
      s.trend = s.trend + 16
      s.maxN = s.maxN + 4
      s.maxC = s.maxC + 4
      return {
        { label = "流行", val = 16 },
        { label = "知名度上限", val = 4 },
        { label = "コンテンツ上限", val = 4 },
        { text = "差別化成功" },
      }
    end,
  },
  {
    id = "ops_minus_5",
    name = "虚無期間",
    desc = "新コンテンツ不足で飽きられる",
    type = "minus",
    phase = "ops",
    costN = 0, costC = 10, costT = 0,
    apply = function(s)
      s.maxC = s.maxC + 10
      s.trend = s.trend + 12
      return {
        { label = "コンテンツ上限", val = 10 },
        { label = "流行", val = 12 },
        { text = "緊急イベント投入" },
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
      s.maxN = s.maxN + 2
      return {{ label = "知名度上限", val = 2 }}
    end,
  },
  {
    name = "コンテンツ制作",
    desc = "ゲーム内容を充実させる",
    costN = 0, costC = 5, costT = 0,
    apply = function(s)
      s.maxC = s.maxC + 2
      return {{ label = "コンテンツ上限", val = 2 }}
    end,
  },
  {
    name = "技術開発",
    desc = "システムやエンジンを改良",
    costN = 0, costC = 0, costT = 5,
    apply = function(s)
      s.maxT = s.maxT + 2
      return {{ label = "技術力上限", val = 2 }}
    end,
  },
  {
    name = "アイテム調達",
    desc = "有用なリソースを探す",
    costN = 3, costC = 3, costT = 3,
    apply = function(s)
      local item = generateItem()
      table.insert(s.items, item)
      return {{ label = "アイテム獲得", text = item.name }}
    end,
  },
  {
    name = "何もしない",
    desc = "様子を見る",
    costN = 0, costC = 0, costT = 0,
    apply = function(s)
      return {{ text = "様子を見た" }}
    end,
  },
}

-- アイテムテンプレート（施策として再定義）
local itemTemplates = {
  -- 開発期専用施策（7種）
  {
    type = "beta_test",
    namePattern = "βテスト実施",
    minValue = 5,
    maxValue = 10,
    minValue2 = 3,
    maxValue2 = 5,
    phase = "dev",
    descPattern = "βテスト実施（技術+%d/コンテンツ+%d）",
  },
  {
    type = "preregist",
    namePattern = "事前登録キャンペーン",
    minValue = 8,
    maxValue = 15,
    phase = "dev",
    descPattern = "事前登録キャンペーン（知名度+%d）",
  },
  {
    type = "pv_creation",
    namePattern = "PV制作",
    minValue = 6,
    maxValue = 12,
    minValue2 = 2,
    maxValue2 = 4,
    phase = "dev",
    descPattern = "PV制作（知名度+%d/コンテンツ+%d）",
  },
  {
    type = "influencer_dev",
    namePattern = "インフルエンサー契約",
    minValue = 10,
    maxValue = 18,
    phase = "dev",
    descPattern = "インフルエンサー契約（知名度+%d）",
  },
  {
    type = "voice_recording",
    namePattern = "ボイス収録",
    minValue = 8,
    maxValue = 15,
    phase = "dev",
    descPattern = "ボイス収録（コンテンツ+%d）",
  },
  {
    type = "crowdfunding",
    namePattern = "クラウドファンディング",
    minValue = 200,
    maxValue = 600,
    minValue2 = 3,
    maxValue2 = 6,
    phase = "dev",
    descPattern = "クラウドファンディング（資金+%d万/知名度+%d）",
  },
  {
    type = "store_aso",
    namePattern = "ストアページ最適化",
    minValue = 4,
    maxValue = 8,
    phase = "dev",
    descPattern = "ストアページ最適化（知名度+%d）",
  },

  -- 運営期専用施策（12種）
  -- 注：limited_gachaは新システムで実装されるため削除
  --{
  --  type = "limited_gacha",
  --  namePattern = "限定ガチャ実装",
  --  minValue = 8,
  --  maxValue = 15,
  --  minValue2 = 200,
  --  maxValue2 = 400,
  --  phase = "ops",
  --  descPattern = "限定ガチャ実装（流行+%d/資金+%d万）",
  --},
  -- 収益系アイテムは新システムで実装
  --{
  --  type = "collab_event",
  --  namePattern = "コラボイベント",
  --  minValue = 15,
  --  maxValue = 25,
  --  minValue2 = 3,
  --  maxValue2 = 8,
  --  minValue3 = 100,
  --  maxValue3 = 300,
  --  phase = "ops",
  --  descPattern = "コラボイベント（流行+%d/知名度+%d/資金+%d万）",
  --},
  {
    type = "tv_ad",
    namePattern = "TV広告出稿",
    minValue = 10,
    maxValue = 20,
    minValue2 = 5,
    maxValue2 = 12,
    minValue3 = -500,
    maxValue3 = -300,
    phase = "ops",
    descPattern = "TV広告出稿（知名度+%d/流行+%d/資金%d万）",
  },
  {
    type = "web_ad",
    namePattern = "Web広告キャンペーン",
    minValue = 5,
    maxValue = 10,
    minValue2 = 3,
    maxValue2 = 8,
    minValue3 = -200,
    maxValue3 = -100,
    phase = "ops",
    descPattern = "Web広告キャンペーン（知名度+%d/流行+%d/資金%d万）",
  },
  --{
  --  type = "anniversary",
  --  namePattern = "周年イベント",
  --  minValue = 20,
  --  maxValue = 35,
  --  minValue2 = 300,
  --  maxValue2 = 600,
  --  phase = "ops",
  --  descPattern = "周年イベント（流行+%d/資金+%d万）",
  --},
  --{
  --  type = "new_character",
  --  namePattern = "新キャラ追加",
  --  minValue = 3,
  --  maxValue = 8,
  --  minValue2 = 5,
  --  maxValue2 = 10,
  --  minValue3 = 80,
  --  maxValue3 = 150,
  --  phase = "ops",
  --  descPattern = "新キャラ追加（コンテンツ+%d/流行+%d/資金+%d万）",
  --},
  --{
  --  type = "limited_event",
  --  namePattern = "期間限定イベント",
  --  minValue = 2,
  --  maxValue = 5,
  --  minValue2 = 8,
  --  maxValue2 = 15,
  --  minValue3 = 50,
  --  maxValue3 = 120,
  --  phase = "ops",
  --  descPattern = "期間限定イベント（コンテンツ+%d/流行+%d/資金+%d万）",
  --},
  {
    type = "real_event",
    namePattern = "リアルイベント開催",
    minValue = 8,
    maxValue = 15,
    minValue2 = 10,
    maxValue2 = 18,
    minValue3 = -400,
    maxValue3 = -200,
    phase = "ops",
    descPattern = "リアルイベント開催（知名度+%d/流行+%d/資金%d万）",
  },
  {
    type = "influencer_ops",
    namePattern = "インフルエンサー案件",
    minValue = 6,
    maxValue = 12,
    minValue2 = 8,
    maxValue2 = 15,
    phase = "ops",
    descPattern = "インフルエンサー案件（知名度+%d/流行+%d）",
  },
  {
    type = "bug_fix_marathon",
    namePattern = "バグ修正大会",
    minValue = 5,
    maxValue = 12,
    minValue2 = 3,
    maxValue2 = 8,
    phase = "ops",
    descPattern = "バグ修正大会（技術+%d/流行+%d）",
  },
  {
    type = "gacha_pity",
    namePattern = "ガチャ天井実装",
    minValue = 10,
    maxValue = 20,
    minValue2 = 3,
    maxValue2 = 6,
    minValue3 = -150,
    maxValue3 = -50,
    phase = "ops",
    descPattern = "ガチャ天井実装（流行+%d/技術+%d/資金%d万）",
  },
  {
    type = "raid_boss",
    namePattern = "レイドボス追加",
    minValue = 4,
    maxValue = 8,
    minValue2 = 2,
    maxValue2 = 5,
    minValue3 = 6,
    maxValue3 = 12,
    phase = "ops",
    descPattern = "レイドボス追加（コンテンツ+%d/技術+%d/流行+%d）",
  },

  -- 両フェーズ共通施策（4種）
  {
    type = "money",
    namePattern = "資金調達",
    minValue = 100,
    maxValue = 500,
    phase = "both",
    descPattern = "資金調達（資金+%d万）",
  },
  {
    type = "hire_staff",
    namePattern = "スタッフ増員",
    minValue = 2,
    maxValue = 5,
    phase = "both",
    descPattern = "スタッフ増員（全リソース+%d）",
  },
  {
    type = "tech_infra",
    namePattern = "技術基盤強化",
    minValue = 5,
    maxValue = 12,
    phase = "both",
    descPattern = "技術基盤強化（技術+%d）",
  },
  {
    type = "outsource",
    namePattern = "外注リソース",
    minValue = 5,
    maxValue = 10,
    minValue2 = -300,
    maxValue2 = -100,
    phase = "both",
    descPattern = "外注リソース（コンテンツ+%d/資金%d万）",
  },
}

-- アイテム生成（フェーズフィルタリング対応）
function generateItem()
  -- 現在のフェーズに適したテンプレートをフィルタリング
  local eligibleTemplates = {}
  for _, template in ipairs(itemTemplates) do
    if template.phase == "both" or template.phase == state.phase then
      table.insert(eligibleTemplates, template)
    end
  end

  -- 適したテンプレートがない場合は汎用の資金調達
  if #eligibleTemplates == 0 then
    local value = math.random(100, 500)
    return {
      type = "money",
      name = "資金調達",
      value = value,
      desc = string.format("資金+%d万", value),
    }
  end

  -- ランダムにテンプレート選択
  local template = eligibleTemplates[math.random(1, #eligibleTemplates)]

  -- 複数値の生成
  local value = math.random(template.minValue, template.maxValue)
  local value2 = nil
  local value3 = nil

  if template.minValue2 then
    value2 = math.random(template.minValue2, template.maxValue2)
  end
  if template.minValue3 then
    value3 = math.random(template.minValue3, template.maxValue3)
  end

  -- 説明文生成
  local desc
  if value3 then
    desc = string.format(template.descPattern, value, value2, value3)
  elseif value2 then
    desc = string.format(template.descPattern, value, value2)
  else
    desc = string.format(template.descPattern, value)
  end

  return {
    type = template.type,
    name = template.namePattern,
    value = value,
    value2 = value2,
    value3 = value3,
    desc = desc,
  }
end

-- コンテンツアイテム生成（恒常 or 限定）
function generateContentItem()
  local isPermanent = math.random() < 0.5  -- 50%の確率で恒常

  if isPermanent then
    -- 恒常コンテンツ：毎月安定収益（小額）
    local revenue = math.random(30, 60)  -- 30-60万/月
    local trend = math.random(3, 8)
    return {
      type = "permanent_content",
      name = "恒常コンテンツ",
      revenue = revenue,
      trend = trend,
      desc = string.format("恒常コンテンツ（収益+%d万/月・流行+%d）", revenue, trend),
    }
  else
    -- 限定コンテンツ：当月のみ大きな収益
    local revenue = math.random(300, 600)  -- 300-600万（恒常の10倍程度）
    local trend = math.random(15, 30)
    return {
      type = "limited_content",
      name = "限定コンテンツ",
      revenue = revenue,
      trend = trend,
      desc = string.format("限定コンテンツ（収益+%d万・流行+%d）", revenue, trend),
    }
  end
end

-- ガチャアイテム生成（恒常 or 限定）
function generateGachaItem()
  local isPermanent = math.random() < 0.5  -- 50%の確率で恒常

  if isPermanent then
    -- 恒常ガチャ：毎月変動収益（小額、±30%）
    local baseRevenue = math.random(40, 80)  -- 40-80万/月ベース
    local trend = math.random(5, 12)
    return {
      type = "permanent_gacha",
      name = "恒常ガチャ",
      baseRevenue = baseRevenue,
      trend = trend,
      desc = string.format("恒常ガチャ（収益+%d万/月±30%%・流行+%d）", baseRevenue, trend),
    }
  else
    -- 限定ガチャ：当月のみ大きな変動収益、流行減少
    local baseRevenue = math.random(500, 1000)  -- 500-1000万ベース
    local variance = 0.4  -- ±40%
    local actualRevenue = math.floor(baseRevenue * (1 + (math.random() * 2 - 1) * variance))
    local trendLoss = math.random(-20, -10)
    return {
      type = "limited_gacha",
      name = "限定ガチャ",
      revenue = actualRevenue,
      trend = trendLoss,
      desc = string.format("限定ガチャ（収益+%d万・流行%d）", actualRevenue, trendLoss),
    }
  end
end

-- アイテム使用（25種類対応）
function useItem(item)
  local result = {}

  -- 開発期専用施策
  if item.type == "beta_test" then
    state.maxT = state.maxT + item.value
    state.maxC = state.maxC + item.value2
    table.insert(result, { label = "技術力上限", val = item.value })
    table.insert(result, { label = "コンテンツ上限", val = item.value2 })

  elseif item.type == "preregist" then
    state.maxN = state.maxN + item.value
    table.insert(result, { label = "知名度上限", val = item.value })

  elseif item.type == "pv_creation" then
    state.maxN = state.maxN + item.value
    state.maxC = state.maxC + item.value2
    table.insert(result, { label = "知名度上限", val = item.value })
    table.insert(result, { label = "コンテンツ上限", val = item.value2 })

  elseif item.type == "influencer_dev" then
    state.maxN = state.maxN + item.value
    table.insert(result, { label = "知名度上限", val = item.value })

  elseif item.type == "voice_recording" then
    state.maxC = state.maxC + item.value
    table.insert(result, { label = "コンテンツ上限", val = item.value })

  elseif item.type == "crowdfunding" then
    state.money = state.money + item.value
    state.maxN = state.maxN + item.value2
    table.insert(result, { label = "資金", val = item.value, suffix = "万" })
    table.insert(result, { label = "知名度上限", val = item.value2 })

  elseif item.type == "store_aso" then
    state.maxN = state.maxN + item.value
    table.insert(result, { label = "知名度上限", val = item.value })

  -- 運営期専用施策
  elseif item.type == "limited_gacha" then
    state.trend = state.trend + item.value
    state.money = state.money + item.value2
    table.insert(result, { label = "流行", val = item.value })
    table.insert(result, { label = "資金", val = item.value2, suffix = "万" })

  elseif item.type == "collab_event" then
    state.trend = state.trend + item.value
    state.maxN = state.maxN + item.value2
    state.money = state.money + item.value3
    table.insert(result, { label = "流行", val = item.value })
    table.insert(result, { label = "知名度上限", val = item.value2 })
    table.insert(result, { label = "資金", val = item.value3, suffix = "万" })

  elseif item.type == "tv_ad" then
    state.maxN = state.maxN + item.value
    state.trend = state.trend + item.value2
    state.money = state.money + item.value3  -- マイナス値
    table.insert(result, { label = "知名度上限", val = item.value })
    table.insert(result, { label = "流行", val = item.value2 })
    table.insert(result, { label = "資金", val = item.value3, suffix = "万" })

  elseif item.type == "web_ad" then
    state.maxN = state.maxN + item.value
    state.trend = state.trend + item.value2
    state.money = state.money + item.value3  -- マイナス値
    table.insert(result, { label = "知名度上限", val = item.value })
    table.insert(result, { label = "流行", val = item.value2 })
    table.insert(result, { label = "資金", val = item.value3, suffix = "万" })

  elseif item.type == "anniversary" then
    state.trend = state.trend + item.value
    state.money = state.money + item.value2
    table.insert(result, { label = "流行", val = item.value })
    table.insert(result, { label = "資金", val = item.value2, suffix = "万" })

  elseif item.type == "new_character" then
    state.maxC = state.maxC + item.value
    state.trend = state.trend + item.value2
    state.money = state.money + item.value3
    table.insert(result, { label = "コンテンツ上限", val = item.value })
    table.insert(result, { label = "流行", val = item.value2 })
    table.insert(result, { label = "資金", val = item.value3, suffix = "万" })

  elseif item.type == "limited_event" then
    state.maxC = state.maxC + item.value
    state.trend = state.trend + item.value2
    state.money = state.money + item.value3
    table.insert(result, { label = "コンテンツ上限", val = item.value })
    table.insert(result, { label = "流行", val = item.value2 })
    table.insert(result, { label = "資金", val = item.value3, suffix = "万" })

  elseif item.type == "real_event" then
    state.maxN = state.maxN + item.value
    state.trend = state.trend + item.value2
    state.money = state.money + item.value3  -- マイナス値
    table.insert(result, { label = "知名度上限", val = item.value })
    table.insert(result, { label = "流行", val = item.value2 })
    table.insert(result, { label = "資金", val = item.value3, suffix = "万" })

  elseif item.type == "influencer_ops" then
    state.maxN = state.maxN + item.value
    state.trend = state.trend + item.value2
    table.insert(result, { label = "知名度上限", val = item.value })
    table.insert(result, { label = "流行", val = item.value2 })

  elseif item.type == "bug_fix_marathon" then
    state.maxT = state.maxT + item.value
    state.trend = state.trend + item.value2
    table.insert(result, { label = "技術力上限", val = item.value })
    table.insert(result, { label = "流行", val = item.value2 })

  elseif item.type == "gacha_pity" then
    state.trend = state.trend + item.value
    state.maxT = state.maxT + item.value2
    state.money = state.money + item.value3  -- マイナス値
    table.insert(result, { label = "流行", val = item.value })
    table.insert(result, { label = "技術力上限", val = item.value2 })
    table.insert(result, { label = "資金", val = item.value3, suffix = "万" })

  elseif item.type == "raid_boss" then
    state.maxC = state.maxC + item.value
    state.maxT = state.maxT + item.value2
    state.trend = state.trend + item.value3
    table.insert(result, { label = "コンテンツ上限", val = item.value })
    table.insert(result, { label = "技術力上限", val = item.value2 })
    table.insert(result, { label = "流行", val = item.value3 })

  -- 両フェーズ共通施策
  elseif item.type == "money" then
    state.money = state.money + item.value
    table.insert(result, { label = "資金", val = item.value, suffix = "万" })

  elseif item.type == "hire_staff" then
    state.maxN = state.maxN + item.value
    state.maxC = state.maxC + item.value
    state.maxT = state.maxT + item.value
    table.insert(result, { label = "知名度上限", val = item.value })
    table.insert(result, { label = "コンテンツ上限", val = item.value })
    table.insert(result, { label = "技術力上限", val = item.value })

  elseif item.type == "tech_infra" then
    state.maxT = state.maxT + item.value
    table.insert(result, { label = "技術力上限", val = item.value })

  elseif item.type == "outsource" then
    state.maxC = state.maxC + item.value
    state.money = state.money + item.value2  -- マイナス値
    table.insert(result, { label = "コンテンツ上限", val = item.value })
    table.insert(result, { label = "資金", val = item.value2, suffix = "万" })

  -- 新規収益システム
  elseif item.type == "permanent_content" then
    -- 恒常コンテンツ：毎月安定収益
    state.recurringRevenue = state.recurringRevenue + item.revenue
    state.trend = state.trend + item.trend
    table.insert(result, { label = "恒常収益", val = item.revenue, suffix = "万/月" })
    table.insert(result, { label = "流行", val = item.trend })

  elseif item.type == "limited_content" then
    -- 限定コンテンツ：当月のみ大きな収益
    state.money = state.money + item.revenue
    state.trend = state.trend + item.trend
    table.insert(result, { label = "資金", val = item.revenue, suffix = "万" })
    table.insert(result, { label = "流行", val = item.trend })

  elseif item.type == "permanent_gacha" then
    -- 恒常ガチャ：毎月変動収益（±30%）
    local variance = 0.3
    local actualRevenue = math.floor(item.baseRevenue * (1 + (math.random() * 2 - 1) * variance))
    state.recurringRevenue = state.recurringRevenue + actualRevenue
    state.trend = state.trend + item.trend
    table.insert(result, { label = "恒常収益", val = actualRevenue, suffix = "万/月±30%" })
    table.insert(result, { label = "流行", val = item.trend })

  elseif item.type == "limited_gacha" then
    -- 限定ガチャ：当月のみ大きな収益、流行減少
    state.money = state.money + item.revenue
    state.trend = state.trend + item.trend
    table.insert(result, { label = "資金", val = item.revenue, suffix = "万" })
    table.insert(result, { label = "流行", val = item.trend })
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
      s.maxN = s.maxN + 2
      s.trend = s.trend + 10
      return {
        { label = "知名度上限", val = 2 },
        { label = "流行", val = 10 },
      }
    end,
  },
  {
    name = "コンテンツ追加",
    desc = "新しいゲーム内容を追加",
    costN = 0, costC = 5, costT = 0,
    apply = function(s)
      s.maxC = s.maxC + 2
      s.trend = s.trend + 6
      return {
        { label = "コンテンツ上限", val = 2 },
        { label = "流行", val = 6 },
      }
    end,
  },
  {
    name = "技術改善",
    desc = "システムを最適化",
    costN = 0, costC = 0, costT = 5,
    apply = function(s)
      s.maxT = s.maxT + 2
      return {{ label = "技術力上限", val = 2 }}
    end,
  },
  {
    name = "アイテム調達",
    desc = "有用なリソースを探す",
    costN = 3, costC = 3, costT = 3,
    apply = function(s)
      local item = generateItem()
      table.insert(s.items, item)
      return {{ label = "アイテム獲得", text = item.name }}
    end,
  },
  {
    name = "コンテンツ実装",
    desc = "恒常または限定コンテンツを実装",
    costN = 0, costC = 8, costT = 2,
    apply = function(s)
      local item = generateContentItem()
      table.insert(s.items, item)
      return {{ label = "コンテンツ獲得", text = item.name }}
    end,
  },
  {
    name = "ガチャ実装",
    desc = "恒常または限定ガチャを実装",
    costN = 2, costC = 5, costT = 5,
    apply = function(s)
      local item = generateGachaItem()
      table.insert(s.items, item)
      return {{ label = "ガチャ獲得", text = item.name }}
    end,
  },
  {
    name = "何もしない",
    desc = "様子を見る",
    costN = 0, costC = 0, costT = 0,
    apply = function(s)
      return {{ text = "様子を見た" }}
    end,
  },
}

-- ===== オートプレイモード関数 =====

function startAutoplay(count)
  autoplayRunCount = count
  autoplayCurrentRun = 0
  autoplayResults = {}
  autoplayTimer = 0
  gameState = "autoplay_running"

  -- 全ゲームを同期的に実行
  for i = 1, count do
    autoplayCurrentRun = i
    runSingleAutoplayGame()
  end

  -- 結果表示へ
  showAutoplayResults()
end

-- 1ゲーム全体を同期的に実行
function runSingleAutoplayGame()
  -- シード設定（再現性のため）
  math.randomseed(os.time() + autoplayCurrentRun)

  -- ゲーム状態初期化
  initState()

  -- ゲームループ
  while true do
    -- 月初処理
    state.N = state.maxN
    state.C = state.maxC
    state.T = state.maxT
    state.actionsRemaining = ACTIONS_PER_MONTH

    -- イベント生成
    generateMonthEvents()

    -- 4回の行動実行
    for action_num = 1, ACTIONS_PER_MONTH do
      if state.actionsRemaining > 0 then
        local choices = getAvailableChoices()
        if #choices > 0 then
          local choice = choices[math.random(#choices)]
          executeAutoChoice(choice)
        else
          break
        end
      end
    end

    -- 月末処理
    processMonthEndLogic()

    -- リリース判定（12ヶ月目終了後）
    if state.month == DEV_MONTHS and state.phase == "dev" then
      executeRelease()
    end

    -- ゲーム終了判定
    state.month = state.month + 1

    -- クリア判定
    if state.month > TOTAL_MONTHS then
      recordAutoplayResult("clear")
      return
    end

    -- ゲームオーバー判定（運営2年目以降のみ）
    if state.money < 0 and state.phase == "ops" and state.month > DEV_MONTHS + 12 then
      recordAutoplayResult("gameover")
      return
    end
  end
end

-- イベント生成（processMonthStartから分離）
function generateMonthEvents()
  state.currentMonthEvents = {}
  state.handledEvents = {}

  local eligibleEvents = {}
  for _, evt in ipairs(allEvents) do
    if evt.phase == state.phase or evt.phase == "both" then
      table.insert(eligibleEvents, evt)
    end
  end

  if #eligibleEvents > 0 then
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
end

-- 月末処理のロジック部分のみ（processMonthEndから分離）
function processMonthEndLogic()
  -- 未対応マイナスイベントへのペナルティ
  local unhandledMinusCount = 0
  for _, evt in ipairs(state.currentMonthEvents) do
    if evt.type == "minus" then
      local handled = false
      for _, id in ipairs(state.handledEvents) do
        if id == evt.id then
          handled = true
          break
        end
      end
      if not handled then
        unhandledMinusCount = unhandledMinusCount + 1
      end
    end
  end

  if unhandledMinusCount > 0 then
    state.money = state.money - (unhandledMinusCount * 100)
  end

  -- 運営期のみ：収益・維持費・減衰
  if state.phase == "ops" then
    -- 恒常収益（毎月発生）
    state.money = state.money + state.recurringRevenue

    -- 維持費（運営期のみ）
    state.money = state.money - 200

    -- 流行減衰
    state.trend = state.trend + autoplayTrendDecay  -- 設定可能な減衰率

    -- ストア評価更新
    if state.trend >= 100 then
      state.storeRating = 5.0
    elseif state.trend >= 70 then
      state.storeRating = 4.5
    elseif state.trend >= 50 then
      state.storeRating = 4.0
    elseif state.trend >= 30 then
      state.storeRating = 3.5
    elseif state.trend >= 15 then
      state.storeRating = 3.0
    elseif state.trend >= 5 then
      state.storeRating = 2.5
    else
      state.storeRating = 2.0
    end

    -- セルランク計算
    local rankScore = state.trend + state.storeRating * 10
    state.storeRanking = math.max(1, math.min(50, math.floor(51 - rankScore / 3)))

    -- 目標達成判定
    if state.month == DEV_MONTHS + 12 and state.money >= 0 then
      state.goals.debtCleared = true
    end
    if state.month == TOTAL_MONTHS and state.storeRanking == 1 then
      state.goals.reachedRank1 = true
    end
  end
end

-- 選択可能な行動リストを取得
function getAvailableChoices()
  local choices = {}

  -- 1. 未対応イベント
  for _, evt in ipairs(state.currentMonthEvents) do
    local handled = false
    for _, id in ipairs(state.handledEvents) do
      if id == evt.id then
        handled = true
        break
      end
    end

    if not handled and canAffordAction(evt) then
      table.insert(choices, {type = "event", data = evt})
    end
  end

  -- 2. 通常行動
  local actions = state.phase == "dev" and devActions or opsActions
  for _, act in ipairs(actions) do
    if canAffordAction(act) then
      table.insert(choices, {type = "action", data = act})
    end
  end

  -- 3. アイテム（行動消費なし）
  for idx, item in ipairs(state.items) do
    table.insert(choices, {type = "item", data = item, index = idx})
  end

  return choices
end

-- 選択を実行
function executeAutoChoice(choice)
  if choice.type == "event" then
    local result = handleEvent(choice.data)
    lastActionResult = result
  elseif choice.type == "action" then
    local result = executeAction(choice.data)
    lastActionResult = result
  elseif choice.type == "item" then
    local result = useItem(choice.data)
    lastActionResult = result
    table.remove(state.items, choice.index)
  end

  -- 月末判定（アイテムは行動消費なし）
  if choice.type ~= "item" and state.actionsRemaining == 0 then
    processMonthEnd()
    subState = "month_end"
  end
end

-- オートプレイの結果を記録
function recordAutoplayResult(result)
  local record = {
    runNumber = autoplayCurrentRun,
    result = result,  -- "clear" or "gameover"
    finalMonth = state.month,
    finalMoney = state.money,
    finalTrend = state.trend,
    maxN = state.maxN,
    maxC = state.maxC,
    maxT = state.maxT,
    storeRating = state.storeRating,
    storeRanking = state.storeRanking or 0,
    debtCleared = state.goals.debtCleared,
    rank1Achieved = state.goals.reachedRank1
  }

  table.insert(autoplayResults, record)
end

-- 結果表示画面へ遷移
function showAutoplayResults()
  gameState = "autoplay_result"

  -- CSV出力
  writeAutoplayCSV()
end

-- オートプレイ結果を集計
function aggregateResults()
  local clearCount = 0
  local totalMoney = 0
  local totalMonth = 0
  local maxMoney = -999999
  local minMoney = 999999

  for _, result in ipairs(autoplayResults) do
    if result.result == "clear" then
      clearCount = clearCount + 1
    end
    totalMoney = totalMoney + result.finalMoney
    totalMonth = totalMonth + result.finalMonth
    maxMoney = math.max(maxMoney, result.finalMoney)
    minMoney = math.min(minMoney, result.finalMoney)
  end

  local avgMoney = totalMoney / #autoplayResults
  local avgMonth = totalMonth / #autoplayResults
  local clearRate = (clearCount / #autoplayResults) * 100

  return {
    clearCount = clearCount,
    clearRate = clearRate,
    avgMoney = avgMoney,
    avgMonth = avgMonth,
    maxMoney = maxMoney,
    minMoney = minMoney
  }
end

-- オートプレイ結果をCSV出力
function writeAutoplayCSV()
  local csv = "流行減衰率,実行番号,結果,最終月,最終資金,流行,maxN,maxC,maxT,ストア評価,セルラン,借金完済,セルラン1位\n"

  for _, result in ipairs(autoplayResults) do
    csv = csv .. string.format(
      "%d,%d,%s,%d,%d,%d,%d,%d,%d,%.1f,%d,%s,%s\n",
      autoplayTrendDecay,
      result.runNumber,
      result.result,
      result.finalMonth,
      result.finalMoney,
      result.finalTrend,
      result.maxN,
      result.maxC,
      result.maxT,
      result.storeRating,
      result.storeRanking,
      result.debtCleared and "達成" or "未達成",
      result.rank1Achieved and "達成" or "未達成"
    )
  end

  -- タイムスタンプ付きファイル名で保存
  local filename = "autoplay_results_" .. os.date("%Y%m%d_%H%M%S") .. ".csv"
  local success, errorMsg = love.filesystem.write(filename, csv)

  if success then
    print("CSV保存完了: " .. love.filesystem.getSaveDirectory() .. "/" .. filename)
  else
    print("エラー: CSV保存失敗 - " .. errorMsg)
    -- フォールバック：標準出力にダンプ
    print(csv)
  end
end

-- 月初処理
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

  -- subStateを直接設定
  subState = "action_select"
  selectedIndex = 1
  isMonthStarted = true
  lastActionResult = {}  -- 前回の結果をクリア
end

function processMonthEnd()
  monthEndReport = {}

  -- 未対応マイナスイベントへのペナルティ
  local unhandledMinusCount = 0
  for _, evt in ipairs(state.currentMonthEvents) do
    if evt.type == "minus" then
      local handled = false
      for _, id in ipairs(state.handledEvents) do
        if id == evt.id then
          handled = true
          break
        end
      end
      if not handled then
        unhandledMinusCount = unhandledMinusCount + 1
      end
    end
  end

  if unhandledMinusCount > 0 then
    local penalty = unhandledMinusCount * 100
    state.money = state.money - penalty
    table.insert(monthEndReport, { label = "未対応ペナルティ", val = -penalty, suffix = "万" })
  end

  -- 運営期の月次収支
  if state.phase == "ops" then
    -- 恒常収益（毎月発生）
    if state.recurringRevenue > 0 then
      state.money = state.money + state.recurringRevenue
      table.insert(monthEndReport, { label = "恒常収益", val = state.recurringRevenue, suffix = "万" })
    end

    -- 維持費（運営期のみ）
    local maintenance = 200
    state.money = state.money - maintenance
    table.insert(monthEndReport, { label = "維持費", val = -maintenance, suffix = "万" })

    -- 流行の時間減衰（設定可能）
    state.trend = state.trend + autoplayTrendDecay
    table.insert(monthEndReport, { label = "流行減衰", val = autoplayTrendDecay })

    -- ストア評価更新
    if state.trend >= 40 then
      state.storeRating = 5
      state.trendLabel = "SNSで話題"
    elseif state.trend >= 20 then
      state.storeRating = 4
      state.trendLabel = "堅調"
    elseif state.trend >= 0 then
      state.storeRating = 3
      state.trendLabel = "まあまあ"
    elseif state.trend >= -20 then
      state.storeRating = 2
      state.trendLabel = "新規流入が鈍化"
    else
      state.storeRating = 1
      state.trendLabel = "やや過疎"
    end

    -- セルラン計算（流行指数とストア評価から算出）
    local rankScore = state.trend + state.storeRating * 10
    if rankScore >= 80 then
      state.storeRanking = 1
    elseif rankScore >= 60 then
      state.storeRanking = math.random(2, 5)
    elseif rankScore >= 40 then
      state.storeRanking = math.random(6, 10)
    elseif rankScore >= 20 then
      state.storeRanking = math.random(11, 20)
    elseif rankScore >= 0 then
      state.storeRanking = math.random(21, 35)
    else
      state.storeRanking = math.random(36, 50)
    end

    -- 目標達成チェック
    -- 運営1周年（24ヶ月）で借金完済
    if state.month == 24 and state.money >= 0 then
      state.goals.debtCleared = true
      table.insert(monthEndReport, { text = "★目標達成★ 運営1周年で借金完済！" })
    end

    -- 運営3周年（48ヶ月）でセルラン1位
    if state.month == 48 and state.storeRanking == 1 then
      state.goals.reachedRank1 = true
      table.insert(monthEndReport, { text = "★目標達成★ 運営3周年でセルラン1位！" })
    end
  end

  table.insert(monthEndReport, { label = "最終資金", val = state.money, suffix = "万" })
end

function advanceMonth()
  state.month = state.month + 1

  -- クリア判定
  if state.month > TOTAL_MONTHS then
    gameState = "gameover"
    subState = "final"
    return
  end

  -- フェーズ移行（12ヶ月目終了後）
  if state.month == DEV_MONTHS + 1 and state.phase == "dev" then
    subState = "release"
    return
  end

  -- サ終判定（運営2年目以降のみ）
  if state.money < 0 and state.phase == "ops" and state.month > DEV_MONTHS + 12 then
    gameState = "gameover"
    return
  end

  processMonthStart()
end

function executeRelease()
  state.phase = "ops"
  -- 流行指数を決定
  state.trend = state.maxN + state.maxC + math.random(-20, 20)
  -- リリース時のボーナスなし（借金-2000のまま運営開始）
end

-- イベント処理
function handleEvent(evt)
  state.N = state.N - evt.costN
  state.C = state.C - evt.costC
  state.T = state.T - evt.costT

  local result = evt.apply(state)

  table.insert(state.handledEvents, evt.id)
  state.actionsRemaining = state.actionsRemaining - 1

  return result
end

-- 行動実行
function executeAction(action)
  state.N = state.N - action.costN
  state.C = state.C - action.costC
  state.T = state.T - action.costT

  local result = action.apply(state)

  state.actionsRemaining = state.actionsRemaining - 1

  return result
end

-- リソースコスト判定
function canAffordAction(action)
  return state.N >= action.costN and state.C >= action.costC and state.T >= action.costT
end

-- ===== LÖVE callbacks =====

function love.load()
  titleFont = love.graphics.newFont(FONT_PATH, 32)
  menuFont = love.graphics.newFont(FONT_PATH, 22)
  smallFont = love.graphics.newFont(FONT_PATH, 16)
  tinyFont = love.graphics.newFont(FONT_PATH, 13)
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
    if key == "space" or key == "return" or key == "1" then
      autoplayCurrentRun = 0  -- オートプレイ状態をリセット
      initState()  -- ゲーム状態を初期化
      gameState = "game"
      processMonthStart()
    elseif key == "2" then
      autoplayCurrentRun = 0  -- オートプレイ状態をリセット
      initState()  -- ゲーム状態を初期化
      gameState = "autoplay_menu"
      autoplayInputBuffer = ""
    elseif key == "3" then
      gameState = "settings"
      autoplayDecayInputBuffer = ""
    end
  elseif gameState == "game" then
    if subState == "action_select" then
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
            -- 月末判定
            if state.actionsRemaining == 0 then
              processMonthEnd()
              subState = "month_end"
            else
              selectedIndex = 1
            end
          end
        else
          local actions = state.phase == "dev" and devActions or opsActions
          local actionIdx = selectedIndex - #unhandledEvents
          if actionIdx >= 1 and actionIdx <= #actions then
            -- 通常行動
            local action = actions[actionIdx]
            if canAffordAction(action) then
              lastActionResult = executeAction(action)
              -- 月末判定
              if state.actionsRemaining == 0 then
                processMonthEnd()
                subState = "month_end"
              else
                selectedIndex = 1
              end
            end
          else
            -- アイテム使用
            local itemIdx = selectedIndex - #unhandledEvents - #actions
            if itemIdx >= 1 and itemIdx <= #state.items then
              local item = state.items[itemIdx]
              lastActionResult = useItem(item)
              table.remove(state.items, itemIdx)
              -- アイテムは行動消費なし
              selectedIndex = 1
            end
          end
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
  elseif gameState == "autoplay_menu" then
    if key == "escape" then
      gameState = "title"
    elseif key == "return" or key == "space" then
      -- 実行開始
      local count = tonumber(autoplayInputBuffer)
      if count == nil or count < 1 then count = 100 end  -- デフォルト100
      if count > 10000 then count = 10000 end

      startAutoplay(count)
    elseif key == "backspace" then
      autoplayInputBuffer = string.sub(autoplayInputBuffer, 1, -2)
    else
      -- 数字入力
      local num = tonumber(key)
      if num and #autoplayInputBuffer < 5 then
        autoplayInputBuffer = autoplayInputBuffer .. key
      end
    end
  elseif gameState == "settings" then
    if key == "escape" then
      gameState = "title"
    elseif key == "return" or key == "space" then
      -- 設定を保存
      local decay = tonumber(autoplayDecayInputBuffer)
      if decay then
        autoplayTrendDecay = decay
      end
      gameState = "title"
    elseif key == "backspace" then
      autoplayDecayInputBuffer = string.sub(autoplayDecayInputBuffer, 1, -2)
    elseif key == "-" or key == "kp-" then
      -- マイナス記号（先頭のみ）
      if #autoplayDecayInputBuffer == 0 then
        autoplayDecayInputBuffer = "-"
      end
    else
      -- 数字入力
      local num = tonumber(key)
      if num and #autoplayDecayInputBuffer < 4 then
        autoplayDecayInputBuffer = autoplayDecayInputBuffer .. key
      end
    end
  elseif gameState == "autoplay_result" then
    if key == "space" or key == "return" or key == "escape" then
      gameState = "title"
      autoplayCurrentRun = 0  -- オートプレイ状態をリセット
    end
  end
end

function love.update(dt)
  -- 特に処理なし（オートプレイは同期的に実行される）
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
  elseif gameState == "settings" then
    drawSettingsScreen()
  elseif gameState == "autoplay_menu" then
    drawAutoplayMenuScreen()
  elseif gameState == "game" then
    -- オートプレイ中は簡易表示
    if autoplayCurrentRun > 0 then
      drawAutoplayRunningScreen()
    else
      -- 通常のゲーム画面
      if subState == "action_select" then
        drawActionSelectScreen()
      elseif subState == "month_end" then
        drawMonthEndScreen()
      elseif subState == "release" then
        drawReleaseScreen()
      end
    end
  elseif gameState == "autoplay_result" then
    drawAutoplayResultScreen()
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
  boldPrintf("ソシャゲ運営シミュレーション v5", 0, 180, BASE_W, "center")

  love.graphics.setFont(smallFont)
  boldPrintf("1: ゲーム開始", 0, 280, BASE_W, "center")
  boldPrintf("2: オートプレイモード", 0, 310, BASE_W, "center")
  boldPrintf("3: ゲーム設定", 0, 340, BASE_W, "center")

  -- 現在の設定を表示
  love.graphics.setColor(0.7, 0.7, 0.7)
  love.graphics.setFont(tinyFont)
  boldPrintf("現在の設定: 流行減衰率 = " .. autoplayTrendDecay .. "/月", 0, 400, BASE_W, "center")

  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(smallFont)
  boldPrintf("F11: Toggle Fullscreen", 0, 450, BASE_W, "center")
  boldPrintf("ESC: Quit", 0, 480, BASE_W, "center")
end

function drawSettingsScreen()
  love.graphics.setFont(titleFont)
  love.graphics.setColor(1, 1, 1)
  boldPrintf("ゲーム設定", 0, 100, BASE_W, "center")

  love.graphics.setFont(menuFont)
  love.graphics.setColor(0.8, 0.8, 0.8)
  boldPrintf("この設定は手動プレイとオートプレイ両方に適用されます", 0, 160, BASE_W, "center")

  -- 流行減衰率入力
  local decayY = 250
  love.graphics.setFont(menuFont)
  love.graphics.setColor(1, 1, 1)
  boldPrint("流行減衰率（/月）:", 250, decayY)

  -- 入力ボックス
  love.graphics.setColor(0.5, 0.5, 0.2)
  love.graphics.rectangle("fill", 480, decayY - 5, 140, 35)
  love.graphics.setColor(1, 1, 1)
  local decayText = autoplayDecayInputBuffer == "" and tostring(autoplayTrendDecay) or autoplayDecayInputBuffer
  boldPrint(decayText .. "_", 490, decayY)

  -- 説明テキスト
  love.graphics.setFont(smallFont)
  love.graphics.setColor(0.7, 0.7, 0.7)
  boldPrint("※現在の値: " .. autoplayTrendDecay .. "/月", 250, 320)
  boldPrint("※マイナスで減少、プラスで増加", 250, 350)
  boldPrint("※デフォルト: -2/月", 250, 380)

  -- 操作説明
  love.graphics.setFont(smallFont)
  love.graphics.setColor(1, 1, 0)
  boldPrintf("Enter: 設定を保存  ESC: キャンセル", 0, 500, BASE_W, "center")
end

function drawAutoplayMenuScreen()
  love.graphics.setFont(titleFont)
  love.graphics.setColor(1, 1, 1)
  boldPrintf("オートプレイモード", 0, 150, BASE_W, "center")

  love.graphics.setFont(menuFont)
  boldPrintf("実行回数を入力してください（1～10000）", 0, 250, BASE_W, "center")

  -- 入力ボックス表示
  love.graphics.setColor(0.5, 0.5, 0.2)
  love.graphics.rectangle("fill", 300, 300, 200, 40)
  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(menuFont)
  local countText = autoplayInputBuffer == "" and "100" or autoplayInputBuffer
  boldPrint(countText .. "_", 320, 310)

  -- 現在の設定を表示
  love.graphics.setFont(smallFont)
  love.graphics.setColor(0.8, 0.8, 0.8)
  boldPrintf("使用される設定: 流行減衰率 = " .. autoplayTrendDecay .. "/月", 0, 380, BASE_W, "center")
  boldPrintf("※設定を変更する場合は「3: ゲーム設定」から", 0, 410, BASE_W, "center")

  love.graphics.setFont(smallFont)
  love.graphics.setColor(1, 1, 0)
  boldPrintf("Enter: 実行開始  ESC: タイトルに戻る", 0, 480, BASE_W, "center")
end

function drawAutoplayRunningScreen()
  love.graphics.setFont(titleFont)
  love.graphics.setColor(1, 1, 1)
  boldPrintf("オートプレイ実行中...", 0, 200, BASE_W, "center")

  love.graphics.setFont(menuFont)
  local progress = string.format("%d / %d 回完了", autoplayCurrentRun - 1, autoplayRunCount)
  boldPrintf(progress, 0, 280, BASE_W, "center")

  local percentage = ((autoplayCurrentRun - 1) / autoplayRunCount) * 100
  boldPrintf(string.format("%.1f%%", percentage), 0, 320, BASE_W, "center")

  -- プログレスバー
  love.graphics.setColor(0.3, 0.3, 0.3)
  love.graphics.rectangle("fill", 200, 380, 400, 30)
  love.graphics.setColor(0.5, 1, 0.5)
  local barWidth = 400 * (autoplayCurrentRun - 1) / autoplayRunCount
  love.graphics.rectangle("fill", 200, 380, barWidth, 30)
end

function drawAutoplayResultScreen()
  local stats = aggregateResults()

  love.graphics.setFont(titleFont)
  love.graphics.setColor(1, 1, 1)
  boldPrintf("オートプレイ結果", 0, 50, BASE_W, "center")

  love.graphics.setFont(menuFont)
  local y = 150

  boldPrint("実行回数: " .. autoplayRunCount .. "回", 100, y)
  y = y + 35
  love.graphics.setColor(0.8, 0.8, 0.8)
  boldPrint("流行減衰率: " .. autoplayTrendDecay .. "/月", 100, y)
  y = y + 45

  love.graphics.setColor(0.5, 1, 0.5)
  boldPrint("クリア回数: " .. stats.clearCount .. "回 (" .. string.format("%.1f", stats.clearRate) .. "%)", 100, y)
  y = y + 40

  love.graphics.setColor(1, 1, 1)
  boldPrint("平均最終資金: " .. string.format("%.0f", stats.avgMoney) .. "万円", 100, y)
  y = y + 35
  boldPrint("最高資金: " .. stats.maxMoney .. "万円", 100, y)
  y = y + 35
  boldPrint("最低資金: " .. stats.minMoney .. "万円", 100, y)
  y = y + 35
  boldPrint("平均到達月: " .. string.format("%.1f", stats.avgMonth) .. "ヶ月", 100, y)
  y = y + 60

  love.graphics.setFont(smallFont)
  love.graphics.setColor(0.5, 1, 1)
  boldPrint("CSV保存完了: " .. love.filesystem.getSaveDirectory() .. "/autoplay_results_*.csv", 50, y)
  y = y + 40

  love.graphics.setColor(1, 1, 0)
  boldPrintf("Space: タイトルに戻る", 0, 550, BASE_W, "center")
end

function drawActionSelectScreen()
  love.graphics.setFont(menuFont)

  -- 月初フラグに応じた表示
  if isMonthStarted then
    love.graphics.setColor(1, 1, 0)
    boldPrint("★ " .. state.month .. "ヶ月目開始 ★", 50, 30)
    isMonthStarted = false
  else
    love.graphics.setColor(1, 1, 1)
    boldPrint(state.month .. "ヶ月目 - 行動選択", 50, 30)
  end

  love.graphics.setFont(smallFont)
  love.graphics.setColor(1, 1, 1)

  -- リソース表示
  boldPrint("N:" .. state.N .. "/" .. state.maxN .. "  C:" .. state.C .. "/" .. state.maxC .. "  T:" .. state.T .. "/" .. state.maxT, 50, 70)
  boldPrint("資金: " .. state.money .. "万  残り行動: " .. state.actionsRemaining, 50, 100)

  -- 運営期の場合はセルランも表示
  if state.phase == "ops" then
    love.graphics.setFont(tinyFont)
    boldPrint("セルラン: " .. state.storeRanking .. "位  ストア評価: " .. string.rep("★", state.storeRating) .. string.rep("☆", 5 - state.storeRating), 50, 125)
    love.graphics.setFont(smallFont)
  end

  -- 未来イベント予告（右カラム）
  local futureY = state.phase == "ops" and 150 or 130
  if #state.futureEvents > 0 then
    love.graphics.setFont(tinyFont)
    love.graphics.setColor(1, 1, 1)
    boldPrint("今後の予定（3ヶ月先まで）:", 420, futureY)
    for i, futureEvt in ipairs(state.futureEvents) do
      local color = futureEvt.type == "plus" and {0.7, 1, 0.7} or {1, 0.7, 0.7}
      love.graphics.setColor(color)
      boldPrint(futureEvt.month .. "ヶ月目: " .. futureEvt.name, 440, futureY + i * 18)
    end
  end

  -- 前回の行動結果表示エリア
  local resultY = state.phase == "ops" and 175 or 155
  if #lastActionResult > 0 then
    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.5, 1, 1)  -- シアン系
    boldPrint("【前回の結果】", 50, resultY)
    love.graphics.setFont(tinyFont)
    local y = resultY + 22
    -- 最大3行まで表示
    for i = 1, math.min(3, #lastActionResult) do
      local r = lastActionResult[i]
      local text
      if r.text then
        text = "> " .. r.text
      else
        text = "> " .. r.label .. ": " .. (r.val >= 0 and "+" or "") .. r.val .. (r.suffix or "")
      end
      boldPrint(text, 70, y)
      y = y + 18
    end
  end

  -- 選択肢表示
  local y = #lastActionResult > 0 and (state.phase == "ops" and 245 or 225) or (state.phase == "ops" and 200 or 180)
  local idx = 1

  -- 未処理イベント数を計算
  local unhandledEvents = {}
  for i, evt in ipairs(state.currentMonthEvents) do
    local handled = false
    for _, id in ipairs(state.handledEvents) do
      if id == evt.id then
        handled = true
        break
      end
    end
    if not handled then
      table.insert(unhandledEvents, evt)
    end
  end

  -- イベント対応（統合表示）
  if #unhandledEvents > 0 then
    love.graphics.setFont(smallFont)
    love.graphics.setColor(1, 1, 1)
    boldPrint("【イベント対応】", 50, y)
    y = y + 25

    love.graphics.setFont(tinyFont)
    for i, evt in ipairs(unhandledEvents) do
      local nameColor = idx == selectedIndex and {1, 1, 0} or (evt.type == "plus" and {0.5, 1, 0.5} or {1, 0.5, 0.5})
      love.graphics.setColor(nameColor)
      boldPrint((idx) .. ". " .. evt.name .. " (N:" .. evt.costN .. " C:" .. evt.costC .. " T:" .. evt.costT .. ")", 70, y)
      
      -- 詳細説明を追加（グレー）
      love.graphics.setColor(0.7, 0.7, 0.7)
      boldPrint("   " .. evt.desc, 90, y + 13)
      
      y = y + 30
      idx = idx + 1
    end
  end

  -- 通常行動
  y = y + 8
  love.graphics.setFont(smallFont)
  love.graphics.setColor(1, 1, 1)
  boldPrint("【通常行動】", 50, y)
  y = y + 25
  love.graphics.setFont(tinyFont)

  local actions = state.phase == "dev" and devActions or opsActions
  for i, act in ipairs(actions) do
    local color = idx == selectedIndex and {1, 1, 0} or {1, 1, 1}
    love.graphics.setColor(color)
    boldPrint((idx) .. ". " .. act.name .. " (N:" .. act.costN .. " C:" .. act.costC .. " T:" .. act.costT .. ")", 70, y)
    y = y + 20
    idx = idx + 1
  end

  -- アイテム（スクロール表示）
  if #state.items > 0 then
    y = y + 8
    love.graphics.setFont(smallFont)
    love.graphics.setColor(1, 1, 1)
    boldPrint("【アイテム使用】（行動消費なし） " .. #state.items .. "個", 50, y)
    y = y + 25

    -- スクロールオフセット計算
    local maxVisibleItems = 4
    local selectedItemIdx = selectedIndex - #unhandledEvents - #actions

    if selectedItemIdx > 0 and selectedItemIdx <= #state.items then
      if selectedItemIdx > itemScrollOffset + maxVisibleItems then
        itemScrollOffset = selectedItemIdx - maxVisibleItems
      elseif selectedItemIdx <= itemScrollOffset then
        itemScrollOffset = selectedItemIdx - 1
      end
      itemScrollOffset = math.max(0, math.min(itemScrollOffset, math.max(0, #state.items - maxVisibleItems)))
    end

    -- スクロール表示（scissorでクリッピング）
    local itemAreaY = y
    love.graphics.setScissor(50, itemAreaY, 710, 80)
    love.graphics.setFont(tinyFont)

    for i = itemScrollOffset + 1, math.min(itemScrollOffset + maxVisibleItems, #state.items) do
      local item = state.items[i]
      local relativeIdx = i - itemScrollOffset
      local globalIdx = idx + (i - itemScrollOffset - 1)
      local color = globalIdx == selectedIndex and {1, 1, 0} or {0.5, 1, 1}
      love.graphics.setColor(color)
      boldPrint(globalIdx .. ". " .. item.name .. " (" .. item.desc .. ")", 70, itemAreaY + (relativeIdx - 1) * 20)
    end

    love.graphics.setScissor()

    -- スクロールバー表示
    if #state.items > maxVisibleItems then
      love.graphics.setColor(0.3, 0.3, 0.3)
      love.graphics.rectangle("fill", 760, itemAreaY, 5, 80)
      love.graphics.setColor(1, 1, 1)
      local barHeight = 80 * (maxVisibleItems / #state.items)
      local scrollPercent = itemScrollOffset / (#state.items - maxVisibleItems)
      love.graphics.rectangle("fill", 760, itemAreaY + scrollPercent * (80 - barHeight), 5, barHeight)
    end

    idx = idx + #state.items
  end

  love.graphics.setFont(tinyFont)
  love.graphics.setColor(1, 1, 1)
  boldPrint("↑↓: Select  SPACE: Execute", 50, 560)
end

function drawMonthEndScreen()
  love.graphics.setFont(menuFont)
  love.graphics.setColor(1, 1, 1)
  boldPrint(state.month .. "ヶ月目 - 月末レポート", 50, 30)

  love.graphics.setFont(smallFont)
  local y = 100
  for _, r in ipairs(monthEndReport) do
    if r.text then
      -- 目標達成などのテキストメッセージ
      love.graphics.setColor(1, 1, 0)  -- 黄色で強調
      boldPrint(r.text, 70, y)
      love.graphics.setColor(1, 1, 1)
    else
      local text = r.label .. ": " .. (r.val >= 0 and "+" or "") .. r.val .. (r.suffix or "")
      boldPrint(text, 70, y)
    end
    y = y + 30
  end

  if state.phase == "ops" then
    y = y + 20
    love.graphics.setColor(1, 1, 1)
    boldPrint("セルラン: " .. state.storeRanking .. "位", 70, y)
    y = y + 30
    boldPrint("ストア評価: " .. string.rep("★", state.storeRating) .. string.rep("☆", 5 - state.storeRating), 70, y)
    y = y + 30
    boldPrint("状況: " .. state.trendLabel, 70, y)
  end

  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(tinyFont)
  boldPrint("Press SPACE to continue", 50, 500)
end

function drawReleaseScreen()
  love.graphics.setFont(menuFont)
  love.graphics.setColor(1, 1, 1)
  boldPrint("リリース！", 50, 100)

  love.graphics.setFont(smallFont)
  boldPrint("開発期が終了しました。", 50, 180)
  boldPrint("これから運営期に入ります。", 50, 220)

  love.graphics.setFont(tinyFont)
  boldPrint("Press SPACE to continue", 50, 500)
end

function drawFinalScreen()
  love.graphics.setFont(menuFont)
  love.graphics.setColor(1, 1, 1)
  boldPrint("48ヶ月完走！", 50, 100)

  love.graphics.setFont(smallFont)
  boldPrint("最終資金: " .. state.money .. "万円", 50, 180)
  boldPrint("最終セルラン: " .. state.storeRanking .. "位", 50, 220)

  -- 目標達成状況
  local y = 280
  love.graphics.setFont(smallFont)
  love.graphics.setColor(1, 1, 0)
  boldPrint("【目標達成状況】", 50, y)
  y = y + 40

  love.graphics.setFont(smallFont)
  if state.goals.debtCleared then
    love.graphics.setColor(0.5, 1, 0.5)  -- 緑
    boldPrint("✓ 運営1周年で借金完済", 70, y)
  else
    love.graphics.setColor(1, 0.5, 0.5)  -- 赤
    boldPrint("✗ 運営1周年で借金完済", 70, y)
  end
  y = y + 35

  if state.goals.reachedRank1 then
    love.graphics.setColor(0.5, 1, 0.5)  -- 緑
    boldPrint("✓ 運営3周年でセルラン1位", 70, y)
  else
    love.graphics.setColor(1, 0.5, 0.5)  -- 赤
    boldPrint("✗ 運営3周年でセルラン1位", 70, y)
  end

  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(tinyFont)
  boldPrint("ESC: Return to Title", 50, 500)
end

function drawGameOverScreen()
  love.graphics.setFont(menuFont)
  love.graphics.setColor(1, 1, 1)
  boldPrint("サービス終了", 50, 100)

  love.graphics.setFont(smallFont)
  boldPrint("資金が尽きました。", 50, 180)

  love.graphics.setFont(tinyFont)
  boldPrint("ESC: Return to Title", 50, 500)
end
