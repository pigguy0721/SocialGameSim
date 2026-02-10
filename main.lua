-- ============================================================
-- ガチャ編成型 経営シミュレーション
-- ============================================================
--[[
  【ゲーム概要】
  プレイヤーは毎月ガチャでキャラクターを獲得し、5枠の編成を組んで
  収益を発生させながら36ヶ月（3年間）の資金生存を目指す経営シミュレーションゲーム。

  【コアループ】
  1. ガチャでキャラ獲得（任意回数）
  2. 5枠に編成を組む
  3. 収益計算（キャラの効果が収益に影響）
  4. 炎上判定（編成バランスが悪いと炎上リスク増）
  5. 維持費支払い
  6. 次月へ（キャラ寿命が減少）

  【ゲームバランスの核心】
  - ガチャを多く引く → 強いキャラが手に入るが資金不足に
  - 編成を偏らせる → 収益増加だが炎上リスク増
  - 安全プレイ → 炎上少ないが収益不足で破産

  リスクとリターンのバランスが重要！
]]

-- ===== 定数定義 =====
-- 【グラフィック】
local FONT_PATH = "fonts/NotoSansJP-Regular.ttf"  -- 日本語フォントのパス

-- 【ゲームバランス - 基本パラメータ】
-- 設定可能なパラメータ（グローバル変数として定義）
WIN_MONTHS = 36           -- クリア条件：36ヶ月生存
INITIAL_MONEY = 3000000   -- 初期資金：300万円
GACHA_COST = 100000       -- ガチャ1回のコスト：10万円
local TEAM_SIZE = 5       -- 編成枠数：5枠（固定）
CHAR_LIFETIME = 3         -- キャラクターの寿命：3ヶ月

-- ===== デバッグモード =====
local DEBUG_MODE = false  -- true にすると追加情報を表示

-- ===== レアリティ確率テーブル（動的生成） =====
--[[
  ガチャで排出されるキャラクターのレアリティと確率
  グローバル変数GACHA_PROB_*から動的に構築
]]
local function buildGachaTable()
  return {
    {rarity="N", prob=GACHA_PROB_N},
    {rarity="R", prob=GACHA_PROB_R},
    {rarity="SR", prob=GACHA_PROB_SR},
    {rarity="SSR", prob=GACHA_PROB_SSR}
  }
end

-- ===== 効果タイプ =====
--[[
  キャラクターが持つ効果の種類（4種類）
  各キャラは1つの効果タイプを持つ

  gacha_boost: ガチャ収益の倍率を上げる（収益に乗算）
  tech_up: 技術力ボーナスを追加（収益に加算）
  content_up: コンテンツ品質の倍率を上げる（収益に乗算）
  buff: 全体の倍率を上げる（収益に乗算）

  【編成バランスの重要性】
  4種類の効果タイプをバランスよく編成すると炎上リスクが下がる！
  特定のタイプに偏ると炎上確率が上昇する。
]]
local effectTypes = {"gacha_boost", "tech_up", "content_up", "buff"}
local effectTypeNames = {
  gacha_boost = "ガチャ強化",    -- 表示名
  tech_up = "技術力UP",          -- 表示名
  content_up = "コンテンツUP",   -- 表示名
  buff = "バフ"                  -- 表示名
}

-- ===== レアリティ別効果量 =====
--[[
  各レアリティの効果量テーブル

  【倍率効果】（gacha_boost, content_up, buff）
  - 1.0 = 効果なし
  - 1.05 = 5%増加
  - 1.50 = 50%増加

  【加算効果】（tech_up）
  - 基礎収益に追加される固定値

  レアリティが高いほど効果が大きい
  N < R < SR < SSR の順に強力
]]
local rarityEffects = {
  N =   {gacha_boost=1.05, tech_up=5000,  content_up=1.05, buff=1.02},   -- ノーマル：効果小
  R =   {gacha_boost=1.10, tech_up=10000, content_up=1.10, buff=1.05},   -- レア：効果中
  SR =  {gacha_boost=1.20, tech_up=20000, content_up=1.20, buff=1.10},   -- スーパーレア：効果大
  SSR = {gacha_boost=1.50, tech_up=50000, content_up=1.50, buff=1.20}    -- 最高レア：効果特大
}

-- ===== レアリティ色（RGB値 0.0-1.0） =====
--[[
  画面表示時のレアリティごとの色
  キャラクター名やレアリティ表示に使用
]]
local rarityColors = {
  N =   {0.7, 0.7, 0.7},     -- グレー（ノーマル）
  R =   {0.3, 0.7, 1.0},     -- 青（レア）
  SR =  {0.9, 0.6, 1.0},     -- 紫（スーパーレア）
  SSR = {1.0, 0.85, 0.2}     -- 金（最高レア）
}

-- ===== キャラクター名リスト =====
--[[
  ガチャで獲得したキャラクターにランダムで割り当てられる名前
  20種類のプリセット名から選ばれ、IDが付与される
  例: "アリス #1", "ベル #2"
]]
local charNames = {
  "アリス", "ベル", "クロエ", "ダイアナ", "エミリー",
  "フィオナ", "グレース", "ハンナ", "アイリス", "ジュリア",
  "カレン", "ルナ", "ミア", "ノエル", "オリビア",
  "ペトラ", "クイーン", "ローズ", "ソフィア", "ティア"
}

-- ===== ゲームバランスパラメータ =====
--[[
  【重要】このパラメータがゲームの難易度を決定する

  BASE_REVENUE: 基礎収益（キャラの効果がない場合の収益）
  BASE_MAINTENANCE: 毎月の固定維持費（自動調整システムで変更される）
  FIRE_PENALTY_MONEY: 炎上時の資金減少率（0.40 = 40%）
  FIRE_PENALTY_REPUTATION: 炎上時の評価減少量
  EMPTY_SLOT_PENALTY: 編成の空き枠1つあたりのバランススコアペナルティ

  【バランス調整の哲学】
  BASE_MAINTENANCEを調整することで、各戦略の生存率を目標範囲に収める
  - NORMAL戦略で生存率35%が基準
  - SAFEは45%、GAMBLEは25%を目標とする
]]
-- 設定可能なゲームバランスパラメータ
BASE_REVENUE = 200000           -- 基礎収益：20万円/月
BASE_MAINTENANCE = 150000       -- 維持費：15万円/月
FIRE_PENALTY_MONEY = 0.40       -- 炎上時の資金減少率：40%
FIRE_PENALTY_REPUTATION = 2     -- 炎上時の評価減少：-2

-- バランススコア関連（グローバル化）
BALANCE_SCORE_MULTIPLIER = 30   -- 標準偏差に乗算する係数
EMPTY_SLOT_PENALTY = 15         -- 空枠1つあたりのペナルティ

-- 炎上確率関連（グローバル化）
FIRE_BALANCE_FACTOR = 0.005     -- バランススコア係数（0.5%）
FIRE_REPUTATION_FACTOR = 0.02   -- 評価係数（2%）
FIRE_MAX_PROBABILITY = 0.80     -- 炎上確率の上限（80%）

-- 初期評価
INITIAL_REPUTATION = 5          -- 初期評価値（0-10）

-- レアリティ確率（グローバル化）
GACHA_PROB_N = 0.60             -- N確率（60%）
GACHA_PROB_R = 0.25             -- R確率（25%）
GACHA_PROB_SR = 0.10            -- SR確率（10%）
GACHA_PROB_SSR = 0.05           -- SSR確率（5%）

-- デフォルト値保存用
local DEFAULT_VALUES = {
  -- 基本設定
  WIN_MONTHS = 36,
  INITIAL_MONEY = 3000000,
  GACHA_COST = 100000,
  CHAR_LIFETIME = 3,
  INITIAL_REPUTATION = 5,
  
  -- 経済設定
  BASE_REVENUE = 200000,
  BASE_MAINTENANCE = 150000,
  
  -- 炎上設定
  FIRE_PENALTY_MONEY = 0.40,
  FIRE_PENALTY_REPUTATION = 2,
  FIRE_BALANCE_FACTOR = 0.005,
  FIRE_REPUTATION_FACTOR = 0.02,
  FIRE_MAX_PROBABILITY = 0.80,
  
  -- バランス設定
  BALANCE_SCORE_MULTIPLIER = 30,
  EMPTY_SLOT_PENALTY = 15,
  
  -- レアリティ確率
  GACHA_PROB_N = 0.60,
  GACHA_PROB_R = 0.25,
  GACHA_PROB_SR = 0.10,
  GACHA_PROB_SSR = 0.05
}

-- ============================================================
-- 描画ヘルパー関数
-- ============================================================

-- ===== 太字描画ヘルパー =====
--[[
  Love2Dには標準で太字フォントがないため、
  同じテキストを少しずらして2回描画することで擬似的な太字を実現

  BOLD_OFFSET: ずらすピクセル数（0.8px）
]]
local BOLD_OFFSET = 0.8

-- 太字でテキストを描画（固定位置）
-- @param text 表示するテキスト
-- @param x X座標
-- @param y Y座標
function boldPrint(text, x, y)
  love.graphics.print(text, x + BOLD_OFFSET, y)  -- わずかにずらして描画
  love.graphics.print(text, x, y)                -- 元の位置に描画
end

-- 太字でテキストを描画（整形あり）
-- @param text 表示するテキスト
-- @param x X座標
-- @param y Y座標
-- @param limit 折り返し幅
-- @param align 配置（"left", "center", "right"）
function boldPrintf(text, x, y, limit, align)
  love.graphics.printf(text, x + BOLD_OFFSET, y, limit, align)
  love.graphics.printf(text, x, y, limit, align)
end

-- ===== フォーマット関数 =====
--[[
  数値を読みやすい形式に変換する関数群

  【フォーマット例】
  1,234,567 → "1.2M円" （100万以上）
  456,789 → "456K円" （1000以上）
  123 → "123円" （1000未満）
]]

-- 金額を読みやすい形式にフォーマット
-- @param num 金額（数値）
-- @return フォーマットされた文字列（例: "1.2M円", "456K円"）
function formatMoney(num)
  if num >= 1000000 then
    -- 100万以上: M（メガ）単位で表示（小数点1桁）
    return string.format("%.1fM円", num / 1000000)
  elseif num >= 1000 then
    -- 1000以上: K（キロ）単位で表示（整数）
    return string.format("%dK円", math.floor(num / 1000))
  else
    -- 1000未満: そのまま表示
    return string.format("%d円", num)
  end
end

-- 数値を読みやすい形式にフォーマット（通貨記号なし）
-- @param num 数値
-- @return フォーマットされた文字列（例: "1.2M", "456K"）
function formatNumber(num)
  if num >= 1000000 then
    return string.format("%.1fM", num / 1000000)
  elseif num >= 1000 then
    return string.format("%dK", math.floor(num / 1000))
  else
    return tostring(num)
  end
end

-- ============================================================
-- ゲーム状態管理
-- ============================================================

--[[
  ゲーム状態管理システムの概要
  
  【画面遷移の構造】
  2層の状態管理システムを採用：
  1. gameState: メイン画面の大分類
  2. subState: 各画面内の詳細状態
  
  【画面遷移フロー】
  
  起動
   ↓
  title (タイトル画面)
   ├→ 手動プレイ → game (ゲーム画面)
   │                ├→ gacha (ガチャ画面)
   │                ├→ formation (編成画面)
   │                └→ month_report (月末レポート)
   │                     ↓
   │                  勝敗判定
   │                     ├→ gameover (ゲームオーバー)
   │                     └→ clear (クリア画面)
   │
   ├→ オートプレイ → autoplay
   │                  ├→ menu (実行回数選択)
   │                  └→ results (結果表示)
   │
   └→ ゲーム設定 → settings
   
  【gameStateの値】
  - "title": タイトル画面（メニュー選択）
  - "game": 手動プレイ中
  - "autoplay": オートプレイモード
  - "settings": ゲーム設定画面
  - "gameover": ゲームオーバー画面
  - "clear": クリア画面
  
  【subStateの値】（gameStateによって異なる）
  game時:
    - "gacha": ガチャ画面（キャラ獲得）
    - "formation": 編成画面（チーム編成）
    - "month_report": 月末レポート（収益・炎上結果）
  
  autoplay時:
    - "menu": 実行回数選択メニュー
    - "results": 結果画面（統計とグラフ）
]]

-- ===== ゲーム状態変数 =====
local gameState = "title"    -- 現在のメイン画面状態
local subState = "select"    -- 現在のサブ画面状態

-- タイトルメニュー
local menu = {
  items = { "手動プレイ", "オートプレイ", "ゲーム設定", "終了" },
  selected = 1  -- 選択中のメニュー項目（1始まり）
}

-- ゲーム進行状態（手動プレイ時）
local state = {}            -- { month, money, reputation, gachaThisMonth }
local chars = {}            -- 所持キャラクター一覧
local team = {}             -- 現在の編成（5枠の配列）
local selectedCharIndex = nil    -- 編成画面で選択中のキャラIndex
local selectedSlotIndex = nil    -- 編成画面で選択中のスロットIndex
local gachaResults = {}     -- 今月引いたガチャ結果の履歴
local monthReport = {}      -- 月末処理の結果レポート

-- ゲーム設定画面（カテゴリ分け）
local settingsMenu = {
  categories = {
    {
      name = "基本設定",
      items = {
        {name="初期資金", key="INITIAL_MONEY", min=1000000, max=10000000, step=500000, format=formatMoney},
        {name="ガチャコスト", key="GACHA_COST", min=50000, max=500000, step=10000, format=formatMoney},
        {name="クリア月数", key="WIN_MONTHS", min=12, max=60, step=6, format=function(v) return string.format("%dヶ月", v) end},
        {name="キャラ寿命", key="CHAR_LIFETIME", min=1, max=6, step=1, format=function(v) return string.format("%dヶ月", v) end},
        {name="初期評価", key="INITIAL_REPUTATION", min=0, max=10, step=1, format=function(v) return string.format("%d", v) end},
      }
    },
    {
      name = "経済設定",
      items = {
        {name="基礎収益", key="BASE_REVENUE", min=100000, max=500000, step=10000, format=formatMoney},
        {name="基礎維持費", key="BASE_MAINTENANCE", min=50000, max=500000, step=10000, format=formatMoney},
      }
    },
    {
      name = "炎上設定",
      items = {
        {name="炎上資金減少率", key="FIRE_PENALTY_MONEY", min=0.1, max=0.8, step=0.05, format=function(v) return string.format("%.0f%%", v*100) end},
        {name="炎上評価減少", key="FIRE_PENALTY_REPUTATION", min=1, max=5, step=1, format=function(v) return string.format("%d", v) end},
        {name="バランス係数", key="FIRE_BALANCE_FACTOR", min=0.001, max=0.01, step=0.001, format=function(v) return string.format("%.3f", v) end},
        {name="評価係数", key="FIRE_REPUTATION_FACTOR", min=0.01, max=0.05, step=0.005, format=function(v) return string.format("%.3f", v) end},
        {name="炎上確率上限", key="FIRE_MAX_PROBABILITY", min=0.5, max=1.0, step=0.05, format=function(v) return string.format("%.0f%%", v*100) end},
      }
    },
    {
      name = "バランス設定",
      items = {
        {name="バランス倍率", key="BALANCE_SCORE_MULTIPLIER", min=10, max=50, step=5, format=function(v) return string.format("%d", v) end},
        {name="空枠ペナルティ", key="EMPTY_SLOT_PENALTY", min=5, max=30, step=5, format=function(v) return string.format("%d", v) end},
      }
    },
    {
      name = "レアリティ確率",
      items = {
        {name="N確率", key="GACHA_PROB_N", min=0.3, max=0.8, step=0.05, format=function(v) return string.format("%.0f%%", v*100) end},
        {name="R確率", key="GACHA_PROB_R", min=0.1, max=0.4, step=0.05, format=function(v) return string.format("%.0f%%", v*100) end},
        {name="SR確率", key="GACHA_PROB_SR", min=0.05, max=0.3, step=0.05, format=function(v) return string.format("%.0f%%", v*100) end},
        {name="SSR確率", key="GACHA_PROB_SSR", min=0.01, max=0.2, step=0.01, format=function(v) return string.format("%.0f%%", v*100) end},
      }
    },
  },
  currentCategory = 1,
  selected = 1
}

-- オートプレイ設定
local autoplayMenu = {
  items = {
    {name="10回実行", runs=10},
    {name="100回実行", runs=100},
    {name="1000回実行", runs=1000},
    {name="10万回実行", runs=100000},  
    {name="戻る", runs=0}
  },
  selected = 1
}
local autoplayResults = nil  -- オートプレイ結果

-- ===== フォント変数 =====
-- 5種類のフォントサイズを使用（後でlove.load()で初期化）
local largeFont    -- 32px タイトル用
local titleFont    -- 28px サブタイトル用
local menuFont     -- 22px メニュー項目用
local smallFont    -- 16px 通常テキスト用
local tinyFont     -- 13px 小さなテキスト用

-- ============================================================
-- ガチャシステム
-- ============================================================

-- キャラクターに付与される一意のID（1から順に増加）
local nextCharId = 1

--[[
  ガチャを1回引く

  【処理の流れ】
  1. ランダムでレアリティを決定（gachaTableの確率に基づく）
  2. ランダムで効果タイプを決定（4種類から均等に1つ）
  3. キャラクターを生成して返す

  @return 生成されたキャラクターテーブル
]]
function rollGacha()
  -- レアリティ抽選（累積確率方式）
  local roll = math.random()  -- 0.0～1.0のランダム値
  local cumProb = 0           -- 累積確率
  local selectedRarity = "N"  -- デフォルトはN

  -- ガチャテーブルを動的に構築
  local gachaTable = buildGachaTable()

  -- 確率テーブルを順に見て、累積確率がrollを超えたらそのレアリティに決定
  for _, entry in ipairs(gachaTable) do
    cumProb = cumProb + entry.prob
    if roll <= cumProb then
      selectedRarity = entry.rarity
      break
    end
  end

  -- 効果タイプをランダムに決定（4種類から均等）
  local effectType = effectTypes[math.random(#effectTypes)]

  -- キャラクター生成
  return createCharacter(selectedRarity, effectType)
end

--[[
  キャラクターオブジェクトを生成

  @param rarity レアリティ（"N", "R", "SR", "SSR"）
  @param effectType 効果タイプ（"gacha_boost", "tech_up", "content_up", "buff"）
  @return 生成されたキャラクターテーブル
]]
function createCharacter(rarity, effectType)
  local char = {
    id = nextCharId,                                    -- 一意のID
    rarity = rarity,                                    -- レアリティ
    effectType = effectType,                            -- 効果タイプ
    effectValue = rarityEffects[rarity][effectType],    -- 効果量（レアリティに基づく）
    lifetime = CHAR_LIFETIME,                           -- 残り寿命（初期値3ヶ月）
    acquiredMonth = state.month,                        -- 獲得した月
    name = charNames[math.random(#charNames)] .. " #" .. nextCharId  -- 名前（ランダム + ID）
  }
  nextCharId = nextCharId + 1
  return char
end

-- ============================================================
-- 編成システム
-- ============================================================

--[[
  編成のバランススコアを計算

  【バランススコアとは】
  編成の偏りを数値化した指標。スコアが高いほど炎上リスクが増加する。
  
  【計算方法】
  1. 4種類の効果タイプ（ガチャ強化、技術力UP、コンテンツUP、バフ）の
     枚数を集計
  2. 標準偏差を計算（分布の偏りを測定）
  3. 標準偏差 × 30 をベーススコアとする
  4. 空枠がある場合、1枠につき+15のペナルティ
  5. 合計スコアを0-100の範囲に収める
  
  【計算例】
  例1: バランス良い編成
    ガチャ強化: 1枚, 技術力UP: 2枚, コンテンツUP: 1枚, バフ: 1枚
    平均: 1.25枚/タイプ
    標準偏差: 0.43
    スコア: 0.43 × 30 = 12.9 → 低スコア（炎上率低）
  
  例2: 偏った編成
    ガチャ強化: 5枚, 技術力UP: 0枚, コンテンツUP: 0枚, バフ: 0枚
    平均: 1.25枚/タイプ
    標準偏差: 2.17
    スコア: 2.17 × 30 = 65.1 → 高スコア（炎上率高）
  
  例3: 空枠あり
    ガチャ強化: 2枚, 空枠: 3枠
    標準偏差スコア: 約30
    空枠ペナルティ: 3 × 15 = 45
    合計スコア: 75 → 非常に高スコア（炎上率非常に高）
  
  【設計意図】
  - バランスの取れた編成を推奨
  - 空枠は大きなペナルティ（キャラを集めるインセンティブ）
  - 完全に偏った編成は非常に危険

  【バランススコアとは】
  編成が4種類の効果タイプをどれだけ偏って配置しているかを数値化したもの。
  スコアが高い = 偏っている = 炎上リスク高
  スコアが低い = バランス良い = 炎上リスク低

  【計算方法】
  1. 各効果タイプの出現回数をカウント
  2. 標準偏差を計算（理想は各タイプ1.25枚、つまり5÷4）
  3. 標準偏差 × 30 = 基本バランススコア
  4. 空枠ペナルティを加算（空枠1つにつき+15）
  5. 最大100にクリップ

  【具体例】
  - バランス良好（各タイプ1-2枚）: スコア 10-30
  - やや偏り（同タイプ3枚）: スコア 40-60
  - 極端な偏り（同タイプ5枚）: スコア 80-100

  @param currentTeam 編成テーブル（5枠の配列、nilは空枠）
  @return バランススコア（0-100）
]]
function calculateTeamBalance(currentTeam)
  -- 各効果タイプの出現回数をカウント
  local typeCounts = {gacha_boost=0, tech_up=0, content_up=0, buff=0}
  local emptySlots = 0

  for i = 1, TEAM_SIZE do
    if currentTeam[i] then
      typeCounts[currentTeam[i].effectType] = typeCounts[currentTeam[i].effectType] + 1
    else
      emptySlots = emptySlots + 1
    end
  end

  -- 標準偏差を計算（統計学的なバラツキの指標）
  local mean = TEAM_SIZE / 4  -- 理想値：5枠を4タイプに均等配分 = 1.25
  local variance = 0

  -- 各タイプの出現回数と理想値の差の2乗を合計
  for _, count in pairs(typeCounts) do
    variance = variance + (count - mean) ^ 2
  end
  variance = variance / 4  -- 分散
  local stdDev = math.sqrt(variance)  -- 標準偏差

  -- バランススコアを計算（標準偏差を係数倍して拡大）
  local balanceScore = math.min(100, stdDev * BALANCE_SCORE_MULTIPLIER)

  -- 空枠ペナルティを加算（空枠は不利）
  balanceScore = balanceScore + (emptySlots * EMPTY_SLOT_PENALTY)

  -- 0-100の範囲に収める
  return math.min(100, balanceScore)
end

-- ============================================================
-- 収益計算システム
-- ============================================================

--[[
  編成に基づいて月次収益を計算

  【収益計算式】
  収益 = (基礎収益 + 技術ボーナス) × ガチャ倍率 × コンテンツ倍率 × バフ倍率 × ランダムブレ

  【各要素の説明】
  - 基礎収益: BASE_REVENUE（固定値、デフォルト20万円）
  - 技術ボーナス: tech_upキャラの効果値の合計（加算）
  - ガチャ倍率: gacha_boostキャラの効果値の積（乗算）
  - コンテンツ倍率: content_upキャラの効果値の積（乗算）
  - バフ倍率: buffキャラの効果値の積（乗算）
  - ランダムブレ: 戦略ごとに変動する運要素

  【計算例】
  編成: SSR ガチャ強化（1.5倍）, SR 技術力UP（+2万）, R バフ（1.05倍）
  
  基礎収益: 20万円
  技術ボーナス: +2万円
  ガチャ倍率: 1.5
  コンテンツ倍率: 1.0（該当キャラなし）
  バフ倍率: 1.05
  ランダムブレ: 1.1（±20%でたまたま+10%）
  
  収益 = (20万 + 2万) × 1.5 × 1.0 × 1.05 × 1.1
       = 22万 × 1.5 × 1.05 × 1.1
       = 38万115円
  
  【ランダムブレの役割】
  同じ編成でも毎月収益が変動することで、運要素を加える。
  - 手動プレイ/オートプレイ: ±20%（デフォルト）
  - SAFE戦略（削除済み）: ±10%（安定）
  - GAMBLE戦略（削除済み）: ±50%（ハイリスク）

  @param currentTeam 編成テーブル（5枠の配列）
  @param varianceAmount 収益ブレの幅（0.20 = ±20%、デフォルト）
  @return 計算された収益（整数値）
]]
function calculateRevenue(currentTeam, varianceAmount)
  varianceAmount = varianceAmount or 0.20  -- デフォルト±20%（NORMAL戦略相当）
  local baseRevenue = BASE_REVENUE

  -- 各効果タイプの累積値を初期化
  local gachaBoost = 1.0      -- ガチャ倍率（乗算）
  local techBonus = 0         -- 技術ボーナス（加算）
  local contentBoost = 1.0    -- コンテンツ倍率（乗算）
  local buffMultiplier = 1.0  -- バフ倍率（乗算）

  -- 編成内の各キャラの効果を集計
  for i = 1, TEAM_SIZE do
    if currentTeam[i] then
      local char = currentTeam[i]
      if char.effectType == "gacha_boost" then
        -- ガチャ強化：倍率を乗算（例: 1.0 × 1.1 × 1.2 = 1.32倍）
        gachaBoost = gachaBoost * char.effectValue
      elseif char.effectType == "tech_up" then
        -- 技術力UP：固定値を加算（例: 0 + 5000 + 10000 = 15000円）
        techBonus = techBonus + char.effectValue
      elseif char.effectType == "content_up" then
        -- コンテンツUP：倍率を乗算
        contentBoost = contentBoost * char.effectValue
      elseif char.effectType == "buff" then
        -- バフ：倍率を乗算
        buffMultiplier = buffMultiplier * char.effectValue
      end
    end
  end

  -- 最終収益を計算
  -- ステップ1: 基礎収益に技術ボーナスを加算
  -- ステップ2: 各種倍率を乗算
  local totalRevenue = (baseRevenue + techBonus) * gachaBoost * contentBoost * buffMultiplier

  -- ランダムブレを適用（収益に運の要素を加える）
  local minVariance = 1.0 - varianceAmount  -- 下限倍率（例: 0.8 = -20%）
  local maxVariance = 1.0 + varianceAmount  -- 上限倍率（例: 1.2 = +20%）
  local variance = minVariance + math.random() * (maxVariance - minVariance)
  totalRevenue = totalRevenue * variance

  -- 整数値に丸めて返す
  return math.floor(totalRevenue)
end

-- ============================================================
-- 炎上システム
-- ============================================================

--[[
  炎上判定を行う

  【炎上とは】
  編成バランスが悪い、または評価が低い状態で発生する負のイベント。
  発生すると資金の40%を失い、評価が2ポイント減少する。

  【炎上確率の計算式】
  炎上確率 = バランススコア × 0.5% + (10 - 評価) × 2%
  
  【計算の内訳】
  1. バランススコアによる基本確率
     - バランススコア0: 0%（完璧なバランス）
     - バランススコア50: 25%（中程度の偏り）
     - バランススコア100: 50%（完全に偏っている）
  
  2. 評価による修正
     - 評価10: 0%（最高評価、炎上リスクなし）
     - 評価5: 10%（中間評価）
     - 評価0: 20%（最低評価、炎上リスク大）
  
  3. 合計確率は0-80%に制限
     - 80%以上にはならない（必ず炎上する状況は作らない）

  【具体例】
  例1: バランス良い編成、高評価
    バランススコア: 20, 評価: 8
    炎上確率 = 20 × 0.005 + (10 - 8) × 0.02 = 0.10 + 0.04 = 14%
    → 低リスク
  
  例2: 偏った編成、中評価
    バランススコア: 50, 評価: 5
    炎上確率 = 50 × 0.005 + (10 - 5) × 0.02 = 0.25 + 0.10 = 35%
    → 中リスク
  
  例3: 非常に偏った編成、低評価
    バランススコア: 80, 評価: 2
    炎上確率 = 80 × 0.005 + (10 - 2) × 0.02 = 0.40 + 0.16 = 56%
    → 高リスク

  【炎上ペナルティ】
  - 資金: 現在資金 × (1 - FIRE_PENALTY_MONEY)
    デフォルト40%減少 → 1000万円が600万円に
  - 評価: 現在評価 - FIRE_PENALTY_REPUTATION
    デフォルト-2ポイント → 評価5が3に

  【ゲームバランスへの影響】
  - 偏った編成は高収益だが炎上リスク大
  - 炎上すると資金が激減 → ガチャが引けない → さらに苦しくなる
  - 評価低下でさらに炎上しやすくなる悪循環
  - バランスの取れた編成が長期的に有利

  @param balanceScore バランススコア（0-100）
  @param reputation 現在の評価（0-10）
  @return 炎上したかどうか（boolean）, 炎上確率（0.0-1.0）
]]
function checkFire(balanceScore, reputation)
  -- バランススコアによる基本炎上確率
  local baseProb = balanceScore * FIRE_BALANCE_FACTOR

  -- 評価による修正（評価が低いほど炎上しやすい）
  local reputationMod = (10 - reputation) * FIRE_REPUTATION_FACTOR

  -- 合計確率
  local totalProb = baseProb + reputationMod

  -- 確率を上限以下に収める
  totalProb = math.max(0, math.min(FIRE_MAX_PROBABILITY, totalProb))

  -- 炎上判定（ランダム抽選）と確率を返す
  return math.random() < totalProb, totalProb
end

-- ============================================================
-- 戦略AI定義
-- ===== 月次処理 =====
function processMonthEnd()
  local report = {}

  -- 編成バランス計算
  local balanceScore = calculateTeamBalance(team)
  table.insert(report, {label="バランススコア", value=math.floor(balanceScore), color={0.9, 0.9, 1}})

  -- 収益計算
  local revenue = calculateRevenue(team)
  state.money = state.money + revenue
  table.insert(report, {label="収益", value=revenue, color={0.3, 1, 0.5}})

  -- 炎上判定
  local fired, fireProb = checkFire(balanceScore, state.reputation)
  if fired then
    local moneyLoss = math.floor(state.money * FIRE_PENALTY_MONEY)
    state.money = state.money - moneyLoss
    state.reputation = math.max(0, state.reputation - FIRE_PENALTY_REPUTATION)
    table.insert(report, {label="炎上！資金損失", value=-moneyLoss, color={1, 0.3, 0.3}})
    table.insert(report, {label="評価低下", value=-FIRE_PENALTY_REPUTATION, color={1, 0.3, 0.3}})
  else
    table.insert(report, {label="炎上確率", value=math.floor(fireProb * 100) .. "%", color={0.9, 0.7, 0.3}})
  end

  -- 維持費
  state.money = state.money - BASE_MAINTENANCE
  table.insert(report, {label="維持費", value=-BASE_MAINTENANCE, color={1, 0.5, 0.4}})

  -- キャラ寿命更新
  local expired = 0
  for i = #chars, 1, -1 do
    chars[i].lifetime = chars[i].lifetime - 1
    if chars[i].lifetime <= 0 then
      -- 編成から削除
      for j = 1, TEAM_SIZE do
        if team[j] and team[j].id == chars[i].id then
          team[j] = nil
        end
      end
      table.remove(chars, i)
      expired = expired + 1
    end
  end

  if expired > 0 then
    table.insert(report, {label="寿命切れキャラ", value=expired, color={0.7, 0.7, 0.7}})
  end

  -- 月を進める
  state.month = state.month + 1

  return report
end

-- ============================================================
-- 設定の保存・読み込み
-- ============================================================

--[[
  設定をファイルに保存
  
  【保存先】
  %APPDATA%/LOVE/helloworld/config.lua（Windows）
  ~/.local/share/love/helloworld/config.lua（Linux）
  
  【保存形式】
  Luaテーブル形式で保存（require()で読み込み可能）
]]
function saveSettings()
  local content = "return {\n"
  
  -- 全カテゴリの全項目を保存
  for _, category in ipairs(settingsMenu.categories) do
    content = content .. string.format("  -- %s\n", category.name)
    for _, item in ipairs(category.items) do
      local value = _G[item.key]
      if type(value) == "number" then
        content = content .. string.format("  %s = %s,\n", item.key, value)
      else
        content = content .. string.format("  %s = \"%s\",\n", item.key, value)
      end
    end
    content = content .. "\n"
  end
  
  content = content .. "}\n"
  
  local success = love.filesystem.write("config.lua", content)
  return success
end

--[[
  設定をファイルから読み込み
  
  【読み込み処理】
  1. config.luaが存在するか確認
  2. ファイルを実行してテーブルを取得
  3. 各パラメータをグローバル変数に設定
  
  【戻り値】
  success: boolean -- 読み込み成功したか
]]
function loadSettings()
  local info = love.filesystem.getInfo("config.lua")
  if not info then
    return false  -- ファイルが存在しない
  end
  
  local chunk, err = love.filesystem.load("config.lua")
  if not chunk then
    print("設定ファイル読み込みエラー:", err)
    return false
  end
  
  local settings = chunk()
  if type(settings) ~= "table" then
    print("設定ファイルの形式が不正です")
    return false
  end
  
  -- 読み込んだ設定をグローバル変数に適用
  for key, value in pairs(settings) do
    if DEFAULT_VALUES[key] ~= nil then  -- 有効なキーのみ
      _G[key] = value
    end
  end
  
  return true
end

-- ===== 初期化 =====
function initState()
  state = {
    month = 1,
    money = INITIAL_MONEY,
    reputation = INITIAL_REPUTATION,
    gachaThisMonth = 0
  }
  chars = {}
  team = {}
  for i = 1, TEAM_SIZE do
    team[i] = nil
  end
  nextCharId = 1
  selectedCharIndex = nil
  selectedSlotIndex = nil
  gachaResults = {}
  monthReport = {}
end

-- ===== 勝敗判定 =====
function checkGameOver()
  return state.money <= 0
end

function checkWin()
  return state.month > WIN_MONTHS
end

-- ============================================================
-- オートプレイシステム
-- ============================================================

--[[
  オートプレイシステムの概要
  
  【目的】
  ゲームバランスの検証と統計的な分析を行うため、
  ランダムAIが自動的にゲームをプレイする機能。
  
  【構成】
  1. runAutoplay(): 1回のゲームを自動実行
  2. executeAutoplay(runCount): 複数回実行して統計集計
  3. 結果画面で生存率と分布グラフを表示
  
  【ランダムAIの戦略】
  - 毎月0-3回のガチャをランダム実行
  - 所持キャラをシャッフルして最大5枚を編成
  - 収益ブレ±20%（手動プレイと同じ）
]]

--[[
  ランダムAIで1回のゲームを実行
  
  【処理フロー】
  1. ゲーム状態を初期化
  2. 36ヶ月ループまたは資金が0以下になるまで
     a. ランダムにガチャ（0-3回）
     b. ランダムに編成（Fisher-Yatesシャッフル）
     c. 月末処理（収益、炎上、維持費、キャラ寿命）
  3. 結果を返す
  
  【戻り値】
  {
    survived: boolean,       -- クリアしたか（36ヶ月生存）
    finalMonth: number,      -- 最終到達月（1-36）
    finalMoney: number       -- 最終資金
  }
  
  【注意点】
  - ローカル変数で独立した状態を管理（グローバル変数を汚染しない）
  - Fisher-Yatesアルゴリズムで公平なシャッフル
  - 炎上判定と寿命処理を手動プレイと同じロジックで実行
]]
function runAutoplay()
  local localState = {
    month = 1,
    money = INITIAL_MONEY,
    reputation = 5,
    gachaThisMonth = 0
  }
  local localChars = {}
  local localTeam = {}
  local nextId = 1

  while localState.month <= WIN_MONTHS and localState.money > 0 do
    -- 月初処理
    localState.gachaThisMonth = 0
    
    -- ランダムにガチャを引く（0-3回）
    local gachaCount = math.random(0, 3)
    for _ = 1, gachaCount do
      if localState.money >= GACHA_COST then
        -- ガチャ実行（動的にテーブル構築）
        local gachaTable = buildGachaTable()
        local randVal = math.random()
        local cumProb = 0
        local rarity = "N"
        for _, entry in ipairs(gachaTable) do
          cumProb = cumProb + entry.prob
          if randVal <= cumProb then
            rarity = entry.rarity
            break
          end
        end
        local effectType = effectTypes[math.random(1, #effectTypes)]
        local char = {
          id = nextId,
          name = charNames[math.random(1, #charNames)] .. " #" .. nextId,
          rarity = rarity,
          effectType = effectType,
          effectValue = rarityEffects[rarity][effectType],
          lifetime = CHAR_LIFETIME
        }
        nextId = nextId + 1
        table.insert(localChars, char)
        localState.money = localState.money - GACHA_COST
        localState.gachaThisMonth = localState.gachaThisMonth + 1
      end
    end

    -- ランダムに編成を組む
    localTeam = {}
    local shuffled = {}
    for _, char in ipairs(localChars) do
      table.insert(shuffled, char)
    end
    -- シャッフル
    for i = #shuffled, 2, -1 do
      local j = math.random(1, i)
      shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    -- 最大5枚選択
    for i = 1, math.min(TEAM_SIZE, #shuffled) do
      localTeam[i] = shuffled[i]
    end

    -- 月末処理
    local balanceScore = calculateTeamBalance(localTeam)
    local revenue = calculateRevenue(localTeam, 0.20)  -- ±20%のブレ
    localState.money = localState.money + revenue

    -- 炎上判定
    local fired, fireProb = checkFire(balanceScore, localState.reputation)
    if fired then
      localState.money = math.floor(localState.money * (1 - FIRE_PENALTY_MONEY))
      localState.reputation = math.max(0, localState.reputation - FIRE_PENALTY_REPUTATION)
    end

    -- 維持費
    localState.money = localState.money - BASE_MAINTENANCE

    -- キャラ寿命減少
    for i = #localChars, 1, -1 do
      localChars[i].lifetime = localChars[i].lifetime - 1
      if localChars[i].lifetime <= 0 then
        table.remove(localChars, i)
      end
    end

    localState.month = localState.month + 1
  end

  -- 結果を返す
  return {
    survived = localState.money > 0 and localState.month > WIN_MONTHS,
    finalMonth = math.min(localState.month - 1, WIN_MONTHS),
    finalMoney = localState.money
  }
end

--[[
  オートプレイを複数回実行して統計を集計
  
  【処理フロー】
  1. 結果データ構造を初期化
  2. runCount回のゲームを実行
  3. 各実行結果から統計を集計
     - 生存率
     - 最終到達月の分布
     - 最終資金の分布（100万円単位で10区間）
     - 平均/最大/最小資金
  4. 統計結果を返す
  
  【パラメータ】
  runCount: number -- 実行回数（10, 100, 1000）
  
  【戻り値】
  {
    totalRuns: number,              -- 総実行回数
    survived: number,               -- 生存回数
    survivalRate: number,           -- 生存率（0.0-1.0）
    monthDistribution: table,       -- {month: count} 最終到達月の分布
    moneyDistribution: table,       -- {bucket: count} 最終資金の分布（10区間）
    avgMoney: number,               -- 平均資金
    maxMoney: number,               -- 最大資金
    minMoney: number                -- 最小資金
  }
  
  【資金分布の区間】
  bucket 1: 0-100万円
  bucket 2: 100-200万円
  ...
  bucket 10: 900万円以上
]]
function executeAutoplay(runCount)
  local results = {
    totalRuns = runCount,
    survived = 0,
    monthDistribution = {},  -- {month: count}
    moneyDistribution = {},  -- {bucket: count}
    maxMoney = -999999999,
    minMoney = 999999999,
    totalMoney = 0,
    survivalRate = 0
  }

  -- 初期化
  for m = 1, WIN_MONTHS do
    results.monthDistribution[m] = 0
  end

  for _ = 1, runCount do
    local result = runAutoplay()
    
    if result.survived then
      results.survived = results.survived + 1
    end

    results.monthDistribution[result.finalMonth] = (results.monthDistribution[result.finalMonth] or 0) + 1
    results.totalMoney = results.totalMoney + result.finalMoney
    results.maxMoney = math.max(results.maxMoney, result.finalMoney)
    results.minMoney = math.min(results.minMoney, result.finalMoney)

    -- 資金分布（10区間）
    local bucket = math.floor(result.finalMoney / 1000000) + 1  -- 100万円単位
    bucket = math.max(1, math.min(10, bucket))
    results.moneyDistribution[bucket] = (results.moneyDistribution[bucket] or 0) + 1
  end

  results.survivalRate = results.survived / runCount
  results.avgMoney = results.totalMoney / runCount

  return results
end

-- ============================================================
-- Love2D コールバック関数
-- ============================================================

--[[
  Love2Dコールバック関数の説明
  
  【主要なコールバック】
  1. love.load()
     - ゲーム起動時に1回だけ実行
     - フォント読み込み、ウィンドウ設定など
  
  2. love.keypressed(key)
     - キーが押された瞬間に実行
     - ゲーム状態に応じた入力処理
  
  3. love.update(dt)
     - 毎フレーム実行（60FPS）
     - 現在は未使用（静的な画面のみ）
  
  4. love.draw()
     - 毎フレーム実行、画面描画
     - レターボックススケーリングで解像度対応
]]

-- ===== 初期化処理 =====
--[[
  ゲーム起動時の初期化
  
  【処理内容】
  1. 日本語フォント（Noto Sans JP）を5サイズ読み込み
     - largeFont: 32px（タイトル用）
     - titleFont: 28px（サブタイトル用）
     - menuFont: 22px（メニュー項目用）
     - smallFont: 16px（通常テキスト用）
     - tinyFont: 13px（小さなテキスト用）
  
  2. ウィンドウタイトル設定
  3. リサイズ可能なウィンドウ設定
  4. フルスクリーンフラグ初期化
]]
function love.load()
  love.window.setTitle("ガチャ編成型 経営シミュレーション")
  love.window.setMode(800, 600, { resizable = true, fullscreen = false })
  love.graphics.setDefaultFilter("linear", "linear")

  math.randomseed(os.time())
  math.random(); math.random(); math.random()

  largeFont = love.graphics.newFont(FONT_PATH, 32)
  titleFont = love.graphics.newFont(FONT_PATH, 28)
  menuFont  = love.graphics.newFont(FONT_PATH, 22)
  smallFont = love.graphics.newFont(FONT_PATH, 16)
  tinyFont  = love.graphics.newFont(FONT_PATH, 13)

  -- 保存された設定を読み込み（存在する場合）
  loadSettings()

  initState()
end

local isBorderlessFullscreen = false

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
        -- 手動プレイ
        initState()
        gameState = "game"
        subState = "gacha"
      elseif menu.selected == 2 then
        -- オートプレイ
        gameState = "autoplay"
        subState = "menu"
        autoplayMenu.selected = 1
      elseif menu.selected == 3 then
        -- ゲーム設定
        gameState = "settings"
        settingsMenu.selected = 1
      elseif menu.selected == 4 then
        -- 終了
        love.event.quit()
      end
    end

  elseif gameState == "settings" then
    local currentItems = settingsMenu.categories[settingsMenu.currentCategory].items
    
    if key == "up" then
      settingsMenu.selected = settingsMenu.selected - 1
      if settingsMenu.selected < 1 then settingsMenu.selected = #currentItems end
    elseif key == "down" then
      settingsMenu.selected = settingsMenu.selected + 1
      if settingsMenu.selected > #currentItems then settingsMenu.selected = 1 end
    elseif key == "tab" or key == "e" then
      -- 次のカテゴリへ
      settingsMenu.currentCategory = settingsMenu.currentCategory + 1
      if settingsMenu.currentCategory > #settingsMenu.categories then
        settingsMenu.currentCategory = 1
      end
      settingsMenu.selected = 1
    elseif key == "q" then
      -- 前のカテゴリへ
      settingsMenu.currentCategory = settingsMenu.currentCategory - 1
      if settingsMenu.currentCategory < 1 then
        settingsMenu.currentCategory = #settingsMenu.categories
      end
      settingsMenu.selected = 1
    elseif key == "left" or key == "right" then
      local item = currentItems[settingsMenu.selected]
      local currentValue = _G[item.key]
      local delta = (key == "right") and item.step or -item.step
      local newValue = currentValue + delta
      -- 範囲チェック
      newValue = math.max(item.min, math.min(item.max, newValue))
      _G[item.key] = newValue
    elseif key == "r" then
      -- 全設定をデフォルトにリセット
      for key, value in pairs(DEFAULT_VALUES) do
        _G[key] = value
      end
    elseif key == "s" then
      -- 設定を保存
      local success = saveSettings()
      if success then
        print("設定を保存しました: " .. love.filesystem.getSaveDirectory() .. "/config.lua")
      else
        print("設定の保存に失敗しました")
      end
    elseif key == "l" then
      -- 設定を読み込み
      local success = loadSettings()
      if success then
        print("設定を読み込みました")
      else
        print("設定の読み込みに失敗しました")
      end
    elseif key == "escape" then
      gameState = "title"
      menu.selected = 1
    end

  elseif gameState == "autoplay" then
    if subState == "menu" then
      if key == "up" then
        autoplayMenu.selected = autoplayMenu.selected - 1
        if autoplayMenu.selected < 1 then autoplayMenu.selected = #autoplayMenu.items end
      elseif key == "down" then
        autoplayMenu.selected = autoplayMenu.selected + 1
        if autoplayMenu.selected > #autoplayMenu.items then autoplayMenu.selected = 1 end
      elseif key == "return" or key == "space" then
        local item = autoplayMenu.items[autoplayMenu.selected]
        if item.runs > 0 then
          -- オートプレイ実行
          autoplayResults = executeAutoplay(item.runs)
          subState = "results"
        else
          -- 戻る
          gameState = "title"
          menu.selected = 1
        end
      elseif key == "escape" then
        gameState = "title"
        menu.selected = 1
      end
    elseif subState == "results" then
      if key == "return" or key == "space" or key == "escape" then
        subState = "menu"
      end
    end

  elseif gameState == "game" then
    if subState == "gacha" then
      if key == "g" then
        -- ガチャを引く
        if state.money >= GACHA_COST then
          local char = rollGacha()
          table.insert(chars, char)
          state.money = state.money - GACHA_COST
          state.gachaThisMonth = state.gachaThisMonth + 1
          table.insert(gachaResults, char)
        end
      elseif key == "return" then
        -- 編成画面へ
        subState = "formation"
        selectedCharIndex = 1
        selectedSlotIndex = 1
      elseif key == "escape" then
        gameState = "title"
        menu.selected = 1
      end

    elseif subState == "formation" then
      if key == "up" then
        selectedCharIndex = math.max(1, selectedCharIndex - 1)
      elseif key == "down" then
        selectedCharIndex = math.min(#chars, selectedCharIndex + 1)
      elseif key == "left" then
        selectedSlotIndex = math.max(1, selectedSlotIndex - 1)
      elseif key == "right" then
        selectedSlotIndex = math.min(TEAM_SIZE, selectedSlotIndex + 1)
      elseif key == "return" or key == "space" then
        -- キャラを編成
        if selectedCharIndex and selectedCharIndex <= #chars then
          team[selectedSlotIndex] = chars[selectedCharIndex]
        end
      elseif key == "delete" or key == "backspace" then
        -- 編成から外す
        team[selectedSlotIndex] = nil
      elseif key == "f" then
        -- 月末処理へ
        monthReport = processMonthEnd()
        gachaResults = {}
        state.gachaThisMonth = 0

        if checkGameOver() then
          gameState = "gameover"
        elseif checkWin() then
          gameState = "clear"
        else
          subState = "month_report"
        end
      elseif key == "escape" then
        gameState = "title"
        menu.selected = 1
      end

    elseif subState == "month_report" then
      if key == "return" or key == "space" then
        subState = "gacha"
      end
    end

  elseif gameState == "gameover" then
    if key == "return" or key == "space" then
      gameState = "title"
      menu.selected = 1
    end

  elseif gameState == "clear" then
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
  elseif gameState == "settings" then
    drawSettingsScreen()
  elseif gameState == "autoplay" then
    if subState == "menu" then
      drawAutoplayMenuScreen()
    elseif subState == "results" then
      drawAutoplayResultsScreen()
    end
  elseif gameState == "game" then
    if subState == "gacha" then
      drawGachaScreen()
    elseif subState == "formation" then
      drawFormationScreen()
    elseif subState == "month_report" then
      drawMonthReportScreen()
    end
  elseif gameState == "gameover" then
    drawGameOverScreen()
  elseif gameState == "clear" then
    drawClearScreen()
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

  love.graphics.setFont(largeFont)
  love.graphics.setColor(1, 0.6, 0.3)
  boldPrintf("ガチャ編成型", 0, h * 0.15, w, "center")

  love.graphics.setFont(titleFont)
  love.graphics.setColor(1, 0.85, 0.3)
  boldPrintf("経営シミュレーション", 0, h * 0.15 + 50, w, "center")

  love.graphics.setFont(smallFont)
  love.graphics.setColor(0.6, 0.6, 0.7)
  boldPrintf("ガチャでキャラを獲得し、5枠編成で36ヶ月生存を目指せ！", 0, h * 0.15 + 90, w, "center")

  love.graphics.setFont(menuFont)
  for i, item in ipairs(menu.items) do
    local y = h * 0.50 + (i - 1) * 45
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

-- ===== 描画: ガチャ画面 =====
function drawGachaScreen()
  local w, h = BASE_W, BASE_H
  love.graphics.clear(0.08, 0.08, 0.14)

  -- ヘッダー
  love.graphics.setFont(smallFont)
  love.graphics.setColor(0.4, 0.8, 1)
  boldPrint(string.format("【%d月目】", state.month), 15, 8)

  love.graphics.setColor(1, 0.9, 0.3)
  boldPrint(string.format("資金: %s", formatMoney(state.money)), 200, 8)

  love.graphics.setColor(0.7, 0.9, 1)
  boldPrint(string.format("評価: %d", state.reputation), 450, 8)

  love.graphics.setColor(0.9, 0.7, 1)
  boldPrint(string.format("所持: %d体", #chars), 600, 8)

  -- 区切り
  love.graphics.setColor(0.25, 0.25, 0.35)
  love.graphics.line(10, 35, w - 10, 35)

  -- ガチャ説明
  love.graphics.setFont(menuFont)
  love.graphics.setColor(1, 1, 1)
  boldPrint("【ガチャ】", 20, 50)

  love.graphics.setFont(smallFont)
  love.graphics.setColor(0.8, 0.8, 0.9)
  boldPrint(string.format("コスト: %s", formatMoney(GACHA_COST)), 20, 85)
  boldPrint(string.format("今月: %d回", state.gachaThisMonth), 20, 110)

  -- ガチャ確率表示
  love.graphics.setFont(tinyFont)
  local gy = 145
  for _, entry in ipairs(gachaTable) do
    love.graphics.setColor(rarityColors[entry.rarity])
    boldPrint(string.format("%s: %.0f%%", entry.rarity, entry.prob * 100), 20, gy)
    gy = gy + 18
  end

  -- ガチャ結果表示
  if #gachaResults > 0 then
    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.9, 0.9, 1)
    boldPrint("【今月の獲得】", 300, 50)

    love.graphics.setFont(tinyFont)
    local ry = 80
    local maxVisible = 20  -- 最大表示行数
    local totalResults = #gachaResults
    
    -- 最新のものを優先表示（古いものから削る）
    local startIndex = math.max(1, totalResults - maxVisible + 1)
    for i = startIndex, totalResults do
      local char = gachaResults[i]
      love.graphics.setColor(rarityColors[char.rarity])
      boldPrint(string.format("[%s] %s - %s", char.rarity, char.name, effectTypeNames[char.effectType]), 300, ry)
      ry = ry + 18
    end
    
    -- スクロール表示
    if totalResults > maxVisible then
      love.graphics.setColor(0.5, 0.5, 0.6)
      boldPrint(string.format("(%d回ガチャ済)", totalResults), 300, ry + 5)
    end
  end

  -- 操作説明
  love.graphics.setFont(smallFont)
  love.graphics.setColor(0.3, 1, 0.5)
  boldPrintf("Gキー: ガチャを引く", 0, h - 80, w, "center")

  love.graphics.setColor(1, 1, 0.5)
  boldPrintf("Enter: 編成画面へ", 0, h - 55, w, "center")

  love.graphics.setFont(tinyFont)
  love.graphics.setColor(0.4, 0.4, 0.5)
  boldPrintf("Esc: タイトルに戻る", 0, h - 30, w, "center")
end

-- ===== 描画: 編成画面 =====
function drawFormationScreen()
  local w, h = BASE_W, BASE_H
  love.graphics.clear(0.08, 0.08, 0.14)

  -- ヘッダー
  love.graphics.setFont(smallFont)
  love.graphics.setColor(0.4, 0.8, 1)
  boldPrint(string.format("【%d月目 - 編成】", state.month), 15, 8)

  love.graphics.setColor(1, 0.9, 0.3)
  boldPrint(string.format("資金: %s", formatMoney(state.money)), 250, 8)

  -- バランススコア
  local balanceScore = calculateTeamBalance(team)
  local balanceColor = balanceScore > 60 and {1, 0.3, 0.3} or balanceScore > 30 and {1, 0.9, 0.3} or {0.3, 1, 0.5}
  love.graphics.setColor(balanceColor)
  boldPrint(string.format("バランス: %d", math.floor(balanceScore)), 500, 8)

  -- 区切り
  love.graphics.setColor(0.25, 0.25, 0.35)
  love.graphics.line(10, 35, w - 10, 35)

  -- 編成表示
  love.graphics.setFont(menuFont)
  love.graphics.setColor(1, 1, 1)
  boldPrint("【編成（5枠）】", 20, 45)

  love.graphics.setFont(tinyFont)
  local ty = 75
  for i = 1, TEAM_SIZE do
    local isSelected = (i == selectedSlotIndex)
    if isSelected then
      love.graphics.setColor(1, 1, 0, 0.3)
      love.graphics.rectangle("fill", 15, ty - 2, 360, 20)
    end

    if team[i] then
      local char = team[i]
      love.graphics.setColor(rarityColors[char.rarity])
      boldPrint(string.format("[%d] [%s] %s - %s (残%dヶ月)",
        i, char.rarity, char.name, effectTypeNames[char.effectType], char.lifetime), 20, ty)
    else
      love.graphics.setColor(0.4, 0.4, 0.4)
      boldPrint(string.format("[%d] (空き)", i), 20, ty)
    end
    ty = ty + 22
  end

  -- ============================================================
  -- 所持キャラ一覧（スクロール対応）
  -- ============================================================
  
  --[[
    所持キャラリストのスクロール実装
    
    【問題】
    所持キャラが増えると画面からはみ出て見えなくなる
    
    【解決策】
    - 最大15行のみ表示
    - 選択中のキャラが常に表示範囲内に収まるよう自動スクロール
    - 選択中のキャラを中央付近に表示することで上下に余裕を持たせる
    
    【スクロール範囲の計算】
    1. 選択中のキャラを中央に配置する位置を計算
       scrollStart = selectedIndex - floor(maxVisible / 2)
    
    2. 範囲外に出ないように調整
       scrollStart = max(1, scrollStart)  -- 上限
       scrollStart = min(scrollStart, total - maxVisible + 1)  -- 下限
    
    3. 終了位置を計算
       scrollEnd = min(scrollStart + maxVisible - 1, total)
    
    【例】
    総キャラ数: 20, 最大表示: 15, 選択: 10
    scrollStart = 10 - 7 = 3
    scrollEnd = 3 + 15 - 1 = 17
    → 3-17番目のキャラを表示（選択中の10は中央付近）
  ]]
  
  love.graphics.setFont(menuFont)
  love.graphics.setColor(1, 1, 1)
  boldPrint("【所持キャラ】", 20, 220)

  love.graphics.setFont(tinyFont)
  local cy = 250
  local maxVisibleChars = 15  -- 最大表示行数
  local totalChars = #chars

  -- スクロール範囲計算（選択中のキャラが必ず表示されるように）
  local scrollStart = 1
  if totalChars > maxVisibleChars then
    -- 選択中のキャラを中央付近に表示
    scrollStart = math.max(1, selectedCharIndex - math.floor(maxVisibleChars / 2))
    scrollStart = math.min(scrollStart, totalChars - maxVisibleChars + 1)
  end
  local scrollEnd = math.min(scrollStart + maxVisibleChars - 1, totalChars)

  -- 表示範囲内のキャラのみ描画
  for i = scrollStart, scrollEnd do
    local char = chars[i]
    local isSelected = (i == selectedCharIndex)
    if isSelected then
      love.graphics.setColor(1, 1, 0, 0.3)
      love.graphics.rectangle("fill", 15, cy - 2, 360, 20)
    end

    love.graphics.setColor(rarityColors[char.rarity])
    boldPrint(string.format("[%s] %s - %s (残%dヶ月)",
      char.rarity, char.name, effectTypeNames[char.effectType], char.lifetime), 20, cy)
    cy = cy + 20
  end

  -- スクロール可能な場合は表示
  if totalChars > maxVisibleChars then
    love.graphics.setColor(0.5, 0.5, 0.6)
    boldPrint(string.format("(%d/%d) ↑↓でスクロール", selectedCharIndex, totalChars), 20, cy + 5)
  end

  -- 炎上確率表示
  local fireProb = select(2, checkFire(balanceScore, state.reputation))
  love.graphics.setFont(smallFont)
  local fireColor = fireProb > 0.4 and {1, 0.2, 0.2} or fireProb > 0.2 and {1, 0.9, 0.3} or {0.3, 1, 0.5}
  love.graphics.setColor(fireColor)
  boldPrint(string.format("炎上確率: %d%%", math.floor(fireProb * 100)), 450, 70)

  -- 予想収益
  local revenue = calculateRevenue(team)
  love.graphics.setColor(0.3, 1, 0.5)
  boldPrint(string.format("予想収益: %s", formatMoney(revenue)), 450, 100)

  -- 維持費
  love.graphics.setColor(1, 0.5, 0.4)
  boldPrint(string.format("維持費: %s", formatMoney(BASE_MAINTENANCE)), 450, 130)

  -- 操作説明
  love.graphics.setFont(tinyFont)
  love.graphics.setColor(0.9, 0.9, 1)
  boldPrint("←→: 編成枠選択  ↑↓: キャラ選択", 450, 190)
  boldPrint("Enter: 編成に配置  Delete: 外す", 450, 210)

  love.graphics.setFont(smallFont)
  love.graphics.setColor(1, 1, 0)
  boldPrintf("Fキー: 月末処理（確定）", 0, h - 55, w, "center")

  love.graphics.setFont(tinyFont)
  love.graphics.setColor(0.4, 0.4, 0.5)
  boldPrintf("Esc: タイトルに戻る", 0, h - 30, w, "center")
end

-- ===== 描画: 月末レポート =====
function drawMonthReportScreen()
  local w, h = BASE_W, BASE_H
  love.graphics.clear(0.08, 0.08, 0.14)

  love.graphics.setFont(titleFont)
  love.graphics.setColor(1, 0.85, 0.3)
  boldPrintf(string.format("%d月 - 月末処理", state.month - 1), 0, 50, w, "center")

  love.graphics.setFont(smallFont)
  local ry = 120
  for _, item in ipairs(monthReport) do
    love.graphics.setColor(item.color)
    if type(item.value) == "number" then
      local sign = item.value >= 0 and "+" or ""
      boldPrintf(string.format("%s: %s%s", item.label, sign,
        (item.label:find("資金") or item.label:find("収益") or item.label:find("維持費") or item.label:find("損失"))
        and formatMoney(math.abs(item.value)) or formatNumber(math.abs(item.value))),
        0, ry, w, "center")
    else
      boldPrintf(string.format("%s: %s", item.label, tostring(item.value)), 0, ry, w, "center")
    end
    ry = ry + 30
  end

  -- 現在資金
  ry = ry + 20
  love.graphics.setFont(menuFont)
  local moneyColor = state.money < 500000 and {1, 0.3, 0.3} or {0.3, 1, 0.5}
  love.graphics.setColor(moneyColor)
  boldPrintf(string.format("現在資金: %s", formatMoney(state.money)), 0, ry, w, "center")

  love.graphics.setFont(smallFont)
  love.graphics.setColor(0.5, 0.5, 0.6)
  boldPrintf("[Enterで次月へ]", 0, h - 40, w, "center")
end

-- ===== 描画: ゲームオーバー =====
function drawGameOverScreen()
  local w, h = BASE_W, BASE_H
  love.graphics.clear(0.05, 0.02, 0.02)

  love.graphics.setFont(largeFont)
  love.graphics.setColor(1, 0.2, 0.2)
  boldPrintf("破産", 0, 80, w, "center")

  love.graphics.setFont(menuFont)
  love.graphics.setColor(0.8, 0.5, 0.5)
  boldPrintf(string.format("%d月目で資金が尽きた...", state.month), 0, 150, w, "center")

  love.graphics.setFont(smallFont)
  love.graphics.setColor(0.6, 0.6, 0.7)
  boldPrintf(string.format("最終資金: %s", formatMoney(state.money)), 0, 220, w, "center")
  boldPrintf(string.format("生存期間: %d/%d ヶ月", state.month - 1, WIN_MONTHS), 0, 250, w, "center")

  love.graphics.setColor(0.4, 0.4, 0.4)
  boldPrintf("[Enterでタイトルに戻る]", 0, h - 40, w, "center")
end

-- ============================================================
-- 描画: ゲーム設定画面
-- ============================================================

--[[
  ゲーム設定画面の描画
  
  【機能】
  8つのゲームパラメータを調整可能：
  1. 初期資金（100万～1000万円）
  2. ガチャコスト（5万～50万円）
  3. 基礎維持費（5万～50万円）
  4. 基礎収益（10万～50万円）
  5. 炎上資金減少率（10%～80%）
  6. 炎上評価減少（1～5）
  7. クリア月数（12～60ヶ月）
  8. キャラ寿命（1～6ヶ月）
  
  【操作】
  - ↑↓: 項目選択
  - ←→: 値変更（min/maxで範囲制限）
  - R: デフォルト値にリセット
  - Esc: タイトルに戻る
  
  【実装のポイント】
  - settingsMenu.itemsにformat関数を持たせて柔軟な表示
  - _G[item.key]でグローバル変数に動的アクセス
  - 選択中の項目は黄色でハイライト
  - デフォルト値を常に表示してリセット可能であることを明示
]]
function drawSettingsScreen()
  local w, h = BASE_W, BASE_H
  love.graphics.clear(0.08, 0.08, 0.15)

  -- タイトル
  love.graphics.setFont(titleFont)
  love.graphics.setColor(0.3, 0.8, 1)
  boldPrintf("ゲーム設定", 0, 30, w, "center")

  -- カテゴリタブ
  love.graphics.setFont(tinyFont)
  local tabWidth = w / #settingsMenu.categories
  for i, category in ipairs(settingsMenu.categories) do
    local x = (i - 1) * tabWidth
    local y = 70
    if i == settingsMenu.currentCategory then
      love.graphics.setColor(0.4, 0.6, 0.9)
      love.graphics.rectangle("fill", x, y, tabWidth, 25)
      love.graphics.setColor(1, 1, 1)
    else
      love.graphics.setColor(0.2, 0.3, 0.4)
      love.graphics.rectangle("fill", x, y, tabWidth, 25)
      love.graphics.setColor(0.6, 0.6, 0.7)
    end
    love.graphics.printf(category.name, x, y + 6, tabWidth, "center")
  end

  -- 操作説明
  love.graphics.setFont(tinyFont)
  love.graphics.setColor(0.6, 0.6, 0.7)
  boldPrintf("Tab/Q/E: カテゴリ切替  ↑↓: 項目  ←→: 値変更  R: デフォルト  S: 保存  L: 読込  Esc: 戻る", 0, 100, w, "center")

  -- 現在のカテゴリの設定項目
  local currentItems = settingsMenu.categories[settingsMenu.currentCategory].items
  love.graphics.setFont(smallFont)
  local startY = 130
  local lineHeight = 35

  for i, item in ipairs(currentItems) do
    local y = startY + (i - 1) * lineHeight
    local value = _G[item.key]

    -- 項目名
    if i == settingsMenu.selected then
      love.graphics.setColor(1, 1, 0)
      boldPrint("> " .. item.name, 150, y)
    else
      love.graphics.setColor(0.8, 0.8, 0.8)
      boldPrint(item.name, 170, y)
    end

    -- 現在の値
    love.graphics.setFont(menuFont)
    if i == settingsMenu.selected then
      love.graphics.setColor(1, 0.9, 0.3)
      boldPrint(item.format(value), 450, y - 2)
    else
      love.graphics.setColor(0.6, 0.6, 0.7)
      boldPrint(item.format(value), 450, y - 2)
    end
  end

  -- デフォルト値表示
  love.graphics.setFont(tinyFont)
  love.graphics.setColor(0.5, 0.5, 0.6)
  local currentItem = currentItems[settingsMenu.selected]
  local defaultValue = DEFAULT_VALUES[currentItem.key]
  boldPrintf(string.format("(デフォルト: %s)", currentItem.format(defaultValue)), 0, h - 60, w, "center")
end

-- ============================================================
-- 描画: オートプレイメニュー画面
-- ============================================================

--[[
  オートプレイメニュー画面の描画
  
  【機能】
  実行回数を選択してオートプレイを開始する画面。
  
  【メニュー項目】
  1. 10回実行 - クイックテスト用（数秒で完了）
  2. 100回実行 - バランス確認用（数十秒）
  3. 1000回実行 - 詳細分析用（数分）
  4. 戻る - タイトルへ戻る
  
  【ランダムAIの説明表示】
  - 毎月0-3回ガチャ
  - ランダム編成
  - 収益ブレ±20%
  
  【操作】
  - ↑↓: 項目選択
  - Enter: 実行開始
  - Esc: タイトルに戻る
]]
function drawAutoplayMenuScreen()
  local w, h = BASE_W, BASE_H
  love.graphics.clear(0.08, 0.08, 0.15)

  -- タイトル
  love.graphics.setFont(titleFont)
  love.graphics.setColor(1, 0.6, 0.3)
  boldPrintf("オートプレイ", 0, 50, w, "center")

  -- 説明
  love.graphics.setFont(tinyFont)
  love.graphics.setColor(0.6, 0.6, 0.7)
  boldPrintf("ランダムAIが自動でプレイし、結果を統計表示します", 0, 100, w, "center")
  boldPrintf(string.format("(毎月0-3回ガチャ、ランダム編成、収益ブレ±20%%)", WIN_MONTHS), 0, 120, w, "center")

  -- メニュー項目
  love.graphics.setFont(menuFont)
  local startY = 200
  for i, item in ipairs(autoplayMenu.items) do
    local y = startY + (i - 1) * 50
    if i == autoplayMenu.selected then
      love.graphics.setColor(1, 1, 0)
      boldPrintf("> " .. item.name .. " <", 0, y, w, "center")
    else
      love.graphics.setColor(0.7, 0.7, 0.7)
      boldPrintf(item.name, 0, y, w, "center")
    end
  end

  love.graphics.setFont(tinyFont)
  love.graphics.setColor(0.4, 0.4, 0.4)
  boldPrintf("↑↓: 選択  Enter: 実行  Esc: タイトル", 0, h - 30, w, "center")
end

-- ============================================================
-- 描画: オートプレイ結果画面
-- ============================================================

--[[
  オートプレイ結果画面の描画
  
  【表示内容】
  1. 生存率（大きく色分け表示）
     - 50%以上: 緑（易しい）
     - 30-50%: 黄（バランス良）
     - 30%未満: 赤（難しい）
  
  2. 統計情報
     - 平均資金
     - 最大資金
     - 最小資金
  
  3. 最終到達月の分布（棒グラフ）
     - 横軸: 1-36ヶ月
     - 縦軸: 回数（正規化）
     - 色: 月数に応じてグラデーション（赤→緑）
     - ラベル: 6ヶ月ごとに表示
  
  4. 最終資金の分布（棒グラフ）
     - 横軸: 100万円単位で10区間
     - 縦軸: 回数（正規化）
     - 色: 青系統
     - ラベル: 各区間の下限値（0M, 1M, 2M, ...）
  
  【棒グラフ描画のアルゴリズム】
  1. 最大値を検出
  2. 各値を最大値で正規化（0.0-1.0）
  3. 正規化した値をグラフ高さに変換
  4. love.graphics.rectangle()で描画
  
  【操作】
  - Enter/Space/Esc: メニューに戻る
]]
function drawAutoplayResultsScreen()
  local w, h = BASE_W, BASE_H
  love.graphics.clear(0.06, 0.06, 0.12)

  -- タイトル
  love.graphics.setFont(titleFont)
  love.graphics.setColor(1, 0.85, 0.3)
  boldPrintf("オートプレイ結果", 0, 30, w, "center")

  love.graphics.setFont(tinyFont)
  love.graphics.setColor(0.6, 0.6, 0.7)
  boldPrintf(string.format("%d回実行", autoplayResults.totalRuns), 0, 65, w, "center")

  -- 生存率（大きく表示）
  love.graphics.setFont(menuFont)
  local survColor = autoplayResults.survivalRate >= 0.5 and {0.3, 1, 0.5} or
                    autoplayResults.survivalRate >= 0.3 and {1, 0.9, 0.3} or {1, 0.3, 0.3}
  love.graphics.setColor(survColor)
  boldPrintf(string.format("生存率: %.1f%%", autoplayResults.survivalRate * 100), 0, 95, w, "center")

  -- 統計情報
  love.graphics.setFont(smallFont)
  love.graphics.setColor(0.8, 0.8, 0.9)
  local infoY = 135
  boldPrintf(string.format("平均資金: %s", formatMoney(autoplayResults.avgMoney)), 0, infoY, w, "center")
  infoY = infoY + 20
  boldPrintf(string.format("最大資金: %s", formatMoney(autoplayResults.maxMoney)), 0, infoY, w, "center")
  infoY = infoY + 20
  boldPrintf(string.format("最小資金: %s", formatMoney(autoplayResults.minMoney)), 0, infoY, w, "center")

  -- 最終到達月分布グラフ
  love.graphics.setFont(tinyFont)
  love.graphics.setColor(1, 1, 1)
  boldPrint("【最終到達月の分布】", 50, 220)

  local graphX = 50
  local graphY = 245
  local graphWidth = 700
  local graphHeight = 100

  -- 最大値を求める
  local maxCount = 0
  for _, count in pairs(autoplayResults.monthDistribution) do
    maxCount = math.max(maxCount, count)
  end

  -- 棒グラフ描画
  if maxCount > 0 then
    local barWidth = graphWidth / WIN_MONTHS
    for month = 1, WIN_MONTHS do
      local count = autoplayResults.monthDistribution[month] or 0
      local barHeight = (count / maxCount) * graphHeight
      local x = graphX + (month - 1) * barWidth
      local y = graphY + graphHeight - barHeight

      -- 色は月数に応じて変化（早期＝赤、後期＝緑）
      local ratio = month / WIN_MONTHS
      love.graphics.setColor(1 - ratio * 0.7, ratio * 0.7 + 0.3, 0.4)
      love.graphics.rectangle("fill", x, y, barWidth - 1, barHeight)

      -- ラベル（6ヶ月ごと）
      if month % 6 == 0 then
        love.graphics.setColor(0.6, 0.6, 0.6)
        love.graphics.setFont(tinyFont)
        love.graphics.print(string.format("%d", month), x - 5, graphY + graphHeight + 5)
      end
    end
  end

  -- 最終資金分布グラフ
  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(tinyFont)
  boldPrint("【最終資金の分布】", 50, 370)

  local graph2Y = 395
  local graph2Height = 100

  -- 最大値を求める
  local maxMoneyCount = 0
  for _, count in pairs(autoplayResults.moneyDistribution) do
    maxMoneyCount = math.max(maxMoneyCount, count)
  end

  -- 棒グラフ描画
  if maxMoneyCount > 0 then
    local barWidth = graphWidth / 10
    for bucket = 1, 10 do
      local count = autoplayResults.moneyDistribution[bucket] or 0
      local barHeight = (count / maxMoneyCount) * graph2Height
      local x = graphX + (bucket - 1) * barWidth
      local y = graph2Y + graph2Height - barHeight

      love.graphics.setColor(0.3, 0.6, 1)
      love.graphics.rectangle("fill", x, y, barWidth - 2, barHeight)

      -- ラベル
      love.graphics.setColor(0.6, 0.6, 0.6)
      love.graphics.setFont(tinyFont)
      local label = string.format("%dM", (bucket - 1))
      love.graphics.print(label, x + 2, graph2Y + graph2Height + 5)
    end
  end

  love.graphics.setFont(tinyFont)
  love.graphics.setColor(0.4, 0.4, 0.4)
  boldPrintf("[Enter: 戻る]", 0, h - 30, w, "center")
end

-- ===== 描画: クリア =====
function drawClearScreen()
  local w, h = BASE_W, BASE_H
  love.graphics.clear(0.05, 0.08, 0.05)

  love.graphics.setFont(largeFont)
  love.graphics.setColor(1, 0.85, 0.2)
  boldPrintf("クリア！", 0, 80, w, "center")

  love.graphics.setFont(menuFont)
  love.graphics.setColor(0.9, 0.9, 0.8)
  boldPrintf("36ヶ月生存達成！", 0, 150, w, "center")

  love.graphics.setFont(smallFont)
  love.graphics.setColor(0.7, 0.7, 0.8)
  boldPrintf(string.format("最終資金: %s", formatMoney(state.money)), 0, 220, w, "center")
  boldPrintf(string.format("最終評価: %d", state.reputation), 0, 250, w, "center")

  love.graphics.setColor(0.4, 0.4, 0.4)
  boldPrintf("[Enterでタイトルに戻る]", 0, h - 40, w, "center")
end

