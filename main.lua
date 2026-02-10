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
local WIN_MONTHS = 36           -- クリア条件：36ヶ月生存
local INITIAL_MONEY = 3000000   -- 初期資金：300万円
local GACHA_COST = 100000       -- ガチャ1回のコスト：10万円
local TEAM_SIZE = 5             -- 編成枠数：5枠
local CHAR_LIFETIME = 3         -- キャラクターの寿命：3ヶ月

-- ===== デバッグモード =====
local DEBUG_MODE = false  -- true にすると追加情報を表示

-- ===== レアリティ確率テーブル =====
--[[
  ガチャで排出されるキャラクターのレアリティと確率
  合計確率 = 100%

  N（ノーマル）: 60% - 最も出やすいが効果は低い
  R（レア）: 25% - そこそこのレア度
  SR（スーパーレア）: 10% - かなりレア
  SSR（スーパースーパーレア）: 5% - 最高レア、最も強力
]]
local gachaTable = {
  {rarity="N", prob=0.60},    -- 60%の確率
  {rarity="R", prob=0.25},    -- 25%の確率
  {rarity="SR", prob=0.10},   -- 10%の確率
  {rarity="SSR", prob=0.05}   -- 5%の確率
}

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
local BASE_REVENUE = 200000           -- 基礎収益：20万円/月
local BASE_MAINTENANCE = 150000       -- 維持費：15万円/月（自動調整される）
local FIRE_PENALTY_MONEY = 0.40       -- 炎上時の資金減少率：40%
local FIRE_PENALTY_REPUTATION = 2     -- 炎上時の評価減少：-2
local EMPTY_SLOT_PENALTY = 15         -- 空枠1つあたりのバランススコアペナルティ：+15

-- ===== シミュレーション設定 =====
--[[
  自動シミュレーションの実行回数設定

  【パフォーマンス目安】
  - 100回: ~1秒
  - 1,000回: ~10秒
  - 100,000回: ~15-20分（高精度）

  SIMULATION_RUNS: 通常のシミュレーション実行回数
  BALANCE_TEST_RUNS: バランステスト用の実行回数（精度重視）
]]
local SIMULATION_RUNS = 100000        -- 通常シミュレーション回数
local BALANCE_TEST_RUNS = 100000      -- バランステスト用（高精度）

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

-- ===== ゲーム状態変数 =====
--[[
  【画面遷移の仕組み】
  gameState: メイン画面の状態
    - "title": タイトル画面
    - "game": ゲームプレイ中
    - "gameover": ゲームオーバー
    - "clear": クリア画面
    - "simulation": 自動シミュレーション

  subState: サブ画面の状態（gameState内の詳細状態）
    - "gacha": ガチャ画面
    - "formation": 編成画面
    - "month_report": 月末レポート
    - "menu": シミュレーションメニュー
    - "results": シミュレーション結果
    など
]]
local gameState = "title"    -- 現在のメイン画面状態
local subState = "select"    -- 現在のサブ画面状態

-- タイトルメニュー
local menu = {
  items = { "手動プレイ", "自動シミュレーション", "終了" },
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

-- シミュレーション関連
local simMenu = {
  items = {
    "SAFE戦略",
    "NORMAL戦略",
    "GAMBLE戦略",
    "全戦略実行",
    "バランステスト(1000回)",
    "全自動バランス調整",
    "維持費のみ調整",
    "戻る"
  },
  selected = 1
}
local simResults = nil      -- シミュレーション結果データ
local simRunning = false    -- シミュレーション実行中フラグ
local simProgress = 0       -- シミュレーション進捗（0-100）

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

  -- バランススコアを計算（標準偏差を30倍して拡大）
  local balanceScore = math.min(100, stdDev * 30)

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

  【ランダムブレの役割】
  - SAFE戦略: ±10%（安定）
  - NORMAL戦略: ±20%（中程度）
  - GAMBLE戦略: ±50%（ハイリスク・ハイリターン）

  @param currentTeam 編成テーブル（5枠の配列）
  @param varianceAmount 収益ブレの幅（0.20 = ±20%）
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

  【具体例】
  - バランススコア50、評価5の場合:
    炎上確率 = 50 × 0.005 + (10 - 5) × 0.02 = 0.25 + 0.10 = 35%

  - バランススコア20、評価8の場合:
    炎上確率 = 20 × 0.005 + (10 - 8) × 0.02 = 0.10 + 0.04 = 14%

  - バランススコア80、評価2の場合:
    炎上確率 = 80 × 0.005 + (10 - 2) × 0.02 = 0.40 + 0.16 = 56%

  【炎上確率の上限】
  最大80%（どれだけ悪くても必ず炎上するわけではない）

  【ゲームバランスへの影響】
  - 偏った編成 → バランススコア高 → 炎上リスク増
  - 炎上すると資金減少 → 次のガチャが引けなくなる
  - 評価が下がるとさらに炎上しやすくなる（悪循環）

  @param balanceScore バランススコア（0-100）
  @param reputation 現在の評価（0-10）
  @return 炎上したかどうか（boolean）, 炎上確率（0.0-1.0）
]]
function checkFire(balanceScore, reputation)
  -- バランススコアによる基本炎上確率（0-50%）
  local baseProb = balanceScore * 0.005  -- スコア100で50%

  -- 評価による修正（評価が低いほど炎上しやすい）
  local reputationMod = (10 - reputation) * 0.02  -- 評価0で+20%、評価10で0%

  -- 合計確率
  local totalProb = baseProb + reputationMod

  -- 確率を0-80%の範囲に収める（必ず炎上する状況は作らない）
  totalProb = math.max(0, math.min(0.80, totalProb))

  -- 炎上判定（ランダム抽選）と確率を返す
  return math.random() < totalProb, totalProb
end

-- ============================================================
-- 戦略AI定義
-- ============================================================

--[[
  【戦略AIとは】
  自動シミュレーションで使用される3つの異なるプレイスタイル。
  それぞれ異なるリスク/リターンのバランスを持つ。

  【3つの戦略】
  1. SAFE戦略: 安定プレイ、生存率重視（目標45%）
  2. NORMAL戦略: バランス型、基準となる戦略（目標35%）
  3. GAMBLE戦略: ハイリスク・ハイリターン（目標25%）

  【戦略AIの構成要素】
  - name: 表示名
  - description: 説明文
  - targetSurvivalRate: 目標生存率（バランス調整の基準）
  - revenueVariance: 収益ブレの幅（戦略の個性を決定）
  - gachaCount(month, money, charsCount): ガチャ回数決定関数
  - selectFormation(availableChars, month): 編成選択関数

  【収益ブレの重要性】
  同じ編成でも収益が変動することで、戦略の個性が生まれる：
  - SAFE: ±10% → 安定した収益、破産リスク低
  - NORMAL: ±20% → 中程度の変動、バランス型
  - GAMBLE: ±50% → 大きな変動、爆益or破産
]]
local strategies = {
  -- ===== SAFE戦略 =====
  --[[
    【SAFE戦略の特徴】
    - ガチャを最小限に抑えて資金を温存
    - バランスの取れた編成を優先（炎上リスク最小化）
    - 収益ブレ±10%で安定した収益
    - 目標生存率：40-50%

    【プレイ方針】
    - ガチャは資金100万以上＆キャラ3体未満の時のみ1回
    - 同タイプは2枚まで制限（バランス重視）
    - レアリティは考慮するが、バランスを最優先
  ]]
  SAFE = {
    name = "SAFE戦略",
    description = "安定重視：ガチャ最小限、バランス編成",
    targetSurvivalRate = 0.45,  -- 目標生存率：40-50%
    revenueVariance = 0.10,     -- 収益ブレ：±10%（最小）

    --[[
      ガチャ回数決定関数（SAFE戦略）

      【判断基準】
      資金が100万円以上 かつ キャラが3体未満の場合のみ1回引く
      それ以外は0回（ガチャを引かない）

      【設計思想】
      - 資金を温存することを最優先
      - キャラが極端に少ない時だけ補充
      - 月が進んでも方針は変わらない（一貫性）

      @param month 現在の月（1-36）
      @param money 現在の資金
      @param charsCount 現在の所持キャラ数
      @return ガチャを引く回数
    ]]
    gachaCount = function(month, money, charsCount)
      -- 資金に余裕があり、キャラが少ない場合のみ1回
      if money > 1000000 and charsCount < 3 then
        return 1
      end
      return 0
    end,

    --[[
      編成選択関数（SAFE戦略）

      【編成方針】
      1. レアリティの高いキャラを優先
      2. 同じ効果タイプは2枚まで制限（バランス重視）
      3. バランススコアを最小化することで炎上リスクを下げる

      【アルゴリズム】
      1. 所持キャラをレアリティ順にソート
      2. 上位から順に選択
      3. 同タイプが2枚になったらそのタイプはスキップ
      4. 5枠埋まるまで繰り返す

      @param availableChars 所持している全キャラのリスト
      @param month 現在の月（未使用だが統一のため引数に含む）
      @return 選択された編成（最大5体のテーブル）
    ]]
    selectFormation = function(availableChars, month)
      local bestTeam = {}

      -- 所持キャラをコピー（元のリストを変更しないため）
      local sortedChars = {}
      for _, char in ipairs(availableChars) do
        table.insert(sortedChars, char)
      end

      -- レアリティの高い順にソート
      -- rarityOrder: N=1, R=2, SR=3, SSR=4（数値が大きいほど優先）
      table.sort(sortedChars, function(a, b)
        local rarityOrder = {N=1, R=2, SR=3, SSR=4}
        return rarityOrder[a.rarity] > rarityOrder[b.rarity]
      end)

      -- バランスを考慮して選択
      local typeCounts = {gacha_boost=0, tech_up=0, content_up=0, buff=0}
      for i = 1, math.min(TEAM_SIZE, #sortedChars) do
        local char = sortedChars[i]
        -- 同タイプが2枚未満なら編成に追加
        if typeCounts[char.effectType] < 2 then
          table.insert(bestTeam, char)
          typeCounts[char.effectType] = typeCounts[char.effectType] + 1
        end
        -- 2枚以上の場合はスキップして次のキャラへ
      end

      return bestTeam
    end
  },

  -- ===== NORMAL戦略 =====
  --[[
    【NORMAL戦略の特徴】
    - バランスの取れた中間的なプレイスタイル
    - ガチャは序盤多め、後半控えめ
    - 同タイプ3枚まで許容（ある程度の偏りを許す）
    - 収益ブレ±20%で中程度の変動
    - 目標生存率：30-40%（バランス調整の基準戦略）

    【プレイ方針】
    - 序盤（1-6月）：ガチャ1-2回（キャラを集める）
    - 中盤（7-18月）：ガチャ0-1回（資金次第）
    - 後半（19-36月）：ガチャ0-1回（慎重に）
    - 編成：レアリティ優先、同タイプ3枚まで
  ]]
  NORMAL = {
    name = "NORMAL戦略",
    description = "バランス型：中程度のガチャ、レアリティ優先",
    targetSurvivalRate = 0.35,  -- 目標生存率：30-40%
    revenueVariance = 0.20,     -- 収益ブレ：±20%（中）

    --[[
      ガチャ回数決定関数（NORMAL戦略）

      【月ごとの戦略】
      序盤（1-6月）：
        - 資金20万以上なら2回
        - それ以外は1回
      中盤（7-18月）：
        - 資金50万以上なら1回
        - それ以外は0回
      後半（19-36月）：
        - 資金80万以上なら1回
        - それ以外は0回

      @param month 現在の月
      @param money 現在の資金
      @param charsCount 現在の所持キャラ数（未使用）
      @return ガチャを引く回数
    ]]
    gachaCount = function(month, money, charsCount)
      if month <= 6 then
        -- 序盤：キャラを集める
        return money >= 200000 and 2 or 1
      elseif month <= 18 then
        -- 中盤：慎重に
        return money >= 500000 and 1 or 0
      else
        -- 後半：さらに慎重に
        return money >= 800000 and 1 or 0
      end
    end,

    --[[
      編成選択関数（NORMAL戦略）

      【編成方針】
      1. レアリティの高いキャラを優先
      2. 同じ効果タイプは3枚まで許容
      3. SAFEよりは攻めるが、GAMBLEほど無茶はしない

      @param availableChars 所持している全キャラのリスト
      @param month 現在の月
      @return 選択された編成
    ]]
    selectFormation = function(availableChars, month)
      local team = {}
      local sortedChars = {}
      for _, char in ipairs(availableChars) do
        table.insert(sortedChars, char)
      end

      -- レアリティ優先でソート
      table.sort(sortedChars, function(a, b)
        local rarityOrder = {N=1, R=2, SR=3, SSR=4}
        return rarityOrder[a.rarity] > rarityOrder[b.rarity]
      end)

      -- 同タイプ3枚まで制限（SAFEの2枚より緩い）
      local typeCounts = {gacha_boost=0, tech_up=0, content_up=0, buff=0}
      for _, char in ipairs(sortedChars) do
        if #team < TEAM_SIZE then
          if typeCounts[char.effectType] < 3 then
            table.insert(team, char)
            typeCounts[char.effectType] = typeCounts[char.effectType] + 1
          end
        end
      end

      return team
    end
  },

  GAMBLE = {
    name = "GAMBLE戦略",
    description = "ギャンブル型：ガチャ多め、レアリティ最優先",
    targetSurvivalRate = 0.25,  -- 20-30%
    revenueVariance = 0.50,  -- ±50% (収益ブレ最大)

    gachaCount = function(month, money, charsCount)
      if month <= 6 then
        return money >= 400000 and 4 or money >= 300000 and 3 or money >= 200000 and 2 or 1
      elseif month <= 18 then
        return money >= 500000 and 3 or money >= 300000 and 2 or 1
      else
        return money >= 600000 and 2 or money >= 400000 and 1 or 0
      end
    end,

    selectFormation = function(availableChars, month)
      local team = {}
      local sortedChars = {}
      for _, char in ipairs(availableChars) do
        table.insert(sortedChars, char)
      end

      -- レアリティ最優先（バランス無視）
      table.sort(sortedChars, function(a, b)
        local rarityOrder = {N=1, R=2, SR=3, SSR=4}
        return rarityOrder[a.rarity] > rarityOrder[b.rarity]
      end)

      for i = 1, math.min(TEAM_SIZE, #sortedChars) do
        table.insert(team, sortedChars[i])
      end

      return team
    end
  }
}

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

-- ===== シミュレーション実行 =====
function runSimulation(strategy, simCount, maintenance)
  local results = {}
  local moneyHistory = {}
  local survivalMonths = {}

  -- 維持費を設定
  local originalMaintenance = BASE_MAINTENANCE
  if maintenance then
    BASE_MAINTENANCE = maintenance
  end

  for run = 1, simCount do
    -- 状態初期化
    local simState = {
      month = 1,
      money = INITIAL_MONEY,
      reputation = 5
    }
    local simChars = {}
    local simTeam = {}
    local simNextCharId = 1

    -- 36ヶ月シミュレーション
    for month = 1, WIN_MONTHS do
      -- ガチャ回数決定
      local gachaCount = strategy.gachaCount(month, simState.money, #simChars)

      -- ガチャ実行
      for i = 1, gachaCount do
        if simState.money >= GACHA_COST then
          -- レアリティ抽選
          local roll = math.random()
          local cumProb = 0
          local selectedRarity = "N"
          for _, entry in ipairs(gachaTable) do
            cumProb = cumProb + entry.prob
            if roll <= cumProb then
              selectedRarity = entry.rarity
              break
            end
          end

          -- 効果タイプ抽選
          local effectType = effectTypes[math.random(#effectTypes)]

          -- キャラ生成
          local char = {
            id = simNextCharId,
            rarity = selectedRarity,
            effectType = effectType,
            effectValue = rarityEffects[selectedRarity][effectType],
            lifetime = CHAR_LIFETIME,
            acquiredMonth = month
          }
          simNextCharId = simNextCharId + 1

          table.insert(simChars, char)
          simState.money = simState.money - GACHA_COST
        end
      end

      -- キャラ寿命更新
      for i = #simChars, 1, -1 do
        simChars[i].lifetime = simChars[i].lifetime - 1
        if simChars[i].lifetime <= 0 then
          table.remove(simChars, i)
        end
      end

      -- 編成決定
      simTeam = strategy.selectFormation(simChars, month)

      -- 編成を配列に変換
      local teamArray = {}
      for i = 1, TEAM_SIZE do
        teamArray[i] = simTeam[i] or nil
      end

      -- 収益計算（戦略の収益ブレを適用）
      local revenue = calculateRevenue(teamArray, strategy.revenueVariance)
      simState.money = simState.money + revenue

      -- 炎上判定
      local balanceScore = calculateTeamBalance(teamArray)
      local fired = math.random() < (balanceScore * 0.005 + (10 - simState.reputation) * 0.02)
      if fired then
        local moneyLoss = math.floor(simState.money * FIRE_PENALTY_MONEY)
        simState.money = simState.money - moneyLoss
        simState.reputation = math.max(0, simState.reputation - FIRE_PENALTY_REPUTATION)
      end

      -- 維持費
      simState.money = simState.money - BASE_MAINTENANCE

      -- 破産チェック
      if simState.money <= 0 then
        table.insert(survivalMonths, month)
        table.insert(moneyHistory, 0)
        break
      end

      -- 36ヶ月生存
      if month == WIN_MONTHS then
        table.insert(survivalMonths, WIN_MONTHS)
        table.insert(moneyHistory, simState.money)
      end
    end
  end

  -- 統計計算
  local survivedCount = 0
  for _, months in ipairs(survivalMonths) do
    if months >= WIN_MONTHS then
      survivedCount = survivedCount + 1
    end
  end

  local survivalRate = survivedCount / simCount

  -- 最終資金の統計
  table.sort(moneyHistory)
  local median = 0
  if #moneyHistory > 0 then
    local mid = math.floor(#moneyHistory / 2)
    if #moneyHistory % 2 == 0 then
      median = (moneyHistory[mid] + moneyHistory[mid + 1]) / 2
    else
      median = moneyHistory[mid + 1]
    end
  end

  local total = 0
  local maxMoney = 0
  for _, money in ipairs(moneyHistory) do
    total = total + money
    maxMoney = math.max(maxMoney, money)
  end
  local avgMoney = #moneyHistory > 0 and (total / #moneyHistory) or 0

  -- 生存期間分布
  local distribution = {
    ["1-12月"] = 0,
    ["13-24月"] = 0,
    ["25-35月"] = 0,
    ["36月(クリア)"] = 0
  }
  for _, months in ipairs(survivalMonths) do
    if months <= 12 then
      distribution["1-12月"] = distribution["1-12月"] + 1
    elseif months <= 24 then
      distribution["13-24月"] = distribution["13-24月"] + 1
    elseif months < 36 then
      distribution["25-35月"] = distribution["25-35月"] + 1
    else
      distribution["36月(クリア)"] = distribution["36月(クリア)"] + 1
    end
  end

  -- 維持費を元に戻す
  BASE_MAINTENANCE = originalMaintenance

  return {
    survivalRate = survivalRate,
    medianMoney = median,
    avgMoney = avgMoney,
    maxMoney = maxMoney,
    distribution = distribution,
    totalRuns = simCount
  }
end

-- ===== 維持費自動調整 =====
function autoAdjustMaintenance(targetRate, tolerance, maxIterations)
  local minMaint = 10000
  local maxMaint = 300000
  local currentMaint = BASE_MAINTENANCE
  local iteration = 0

  tolerance = tolerance or 0.05
  maxIterations = maxIterations or 15

  while iteration < maxIterations do
    iteration = iteration + 1

    -- NORMAL戦略で100回シミュレーション
    local results = runSimulation(strategies.NORMAL, 100, currentMaint)
    local survivalRate = results.survivalRate

    -- 目標達成チェック
    if math.abs(survivalRate - targetRate) < tolerance then
      BASE_MAINTENANCE = currentMaint
      return currentMaint, survivalRate, iteration
    end

    -- バイナリサーチ
    if survivalRate > targetRate then
      -- 維持費を上げる
      minMaint = currentMaint
      currentMaint = math.floor((currentMaint + maxMaint) / 2)
    else
      -- 維持費を下げる
      maxMaint = currentMaint
      currentMaint = math.floor((minMaint + currentMaint) / 2)
    end

    -- 範囲が狭くなりすぎた場合は終了
    if maxMaint - minMaint < 1000 then
      break
    end
  end

  BASE_MAINTENANCE = currentMaint
  return currentMaint, runSimulation(strategies.NORMAL, 100, currentMaint).survivalRate, iteration
end

-- ===== ファイル出力ヘルパー =====
function saveResultsToFile(filename, content)
  local success, err = love.filesystem.write(filename, content)
  if success then
    local savePath = love.filesystem.getSaveDirectory()
    return true, savePath .. "/" .. filename
  else
    return false, err
  end
end

-- ===== 全体バランス自動調整 =====
function autoBalanceAll()
  local log = {}

  table.insert(log, "=== 自動バランス調整開始 ===")
  table.insert(log, string.format("初期維持費: %s", formatMoney(BASE_MAINTENANCE)))
  table.insert(log, "目標:")
  table.insert(log, "  SAFE: 40-50% (収益ブレ±10%)")
  table.insert(log, "  NORMAL: 30-40% (収益ブレ±20%)")
  table.insert(log, "  GAMBLE: 20-30% (収益ブレ±50%)")

  -- ステップ1: NORMAL戦略を35%に調整
  table.insert(log, "\n【ステップ1】NORMAL戦略を生存率35%に調整中...")
  local newMaint, normalRate, iterations = autoAdjustMaintenance(0.35, 0.03, 15)
  table.insert(log, string.format("完了: 維持費=%s, 生存率=%.1f%%, 反復=%d回",
    formatMoney(newMaint), normalRate * 100, iterations))

  -- ステップ2: 全戦略でバランステスト（300回）
  table.insert(log, "\n【ステップ2】全戦略でバランス検証中（300回）...")
  local safeResult = runSimulation(strategies.SAFE, 300)
  local normalResult = runSimulation(strategies.NORMAL, 300)
  local gambleResult = runSimulation(strategies.GAMBLE, 300)

  table.insert(log, string.format("SAFE: %.1f%% (目標: 40-50%%)", safeResult.survivalRate * 100))
  table.insert(log, string.format("NORMAL: %.1f%% (目標: 30-40%%)", normalResult.survivalRate * 100))
  table.insert(log, string.format("GAMBLE: %.1f%% (目標: 20-30%%)", gambleResult.survivalRate * 100))

  -- ステップ3: 段階的な微調整
  local maxAdjustments = 5
  local adjustmentCount = 0

  while adjustmentCount < maxAdjustments do
    local needsAdjustment = false
    local adjustmentReason = ""

    -- SAFEの調整判定
    if safeResult.survivalRate < 0.38 then
      needsAdjustment = true
      adjustmentReason = "SAFE生存率が低すぎる"
      BASE_MAINTENANCE = math.floor(BASE_MAINTENANCE * 0.95)
    elseif safeResult.survivalRate > 0.52 then
      needsAdjustment = true
      adjustmentReason = "SAFE生存率が高すぎる"
      BASE_MAINTENANCE = math.floor(BASE_MAINTENANCE * 1.03)
    -- NORMALの調整判定
    elseif normalResult.survivalRate < 0.28 then
      needsAdjustment = true
      adjustmentReason = "NORMAL生存率が低すぎる"
      BASE_MAINTENANCE = math.floor(BASE_MAINTENANCE * 0.95)
    elseif normalResult.survivalRate > 0.42 then
      needsAdjustment = true
      adjustmentReason = "NORMAL生存率が高すぎる"
      BASE_MAINTENANCE = math.floor(BASE_MAINTENANCE * 1.03)
    -- GAMBLEの調整判定
    elseif gambleResult.survivalRate < 0.18 then
      needsAdjustment = true
      adjustmentReason = "GAMBLE生存率が低すぎる"
      BASE_MAINTENANCE = math.floor(BASE_MAINTENANCE * 0.97)
    elseif gambleResult.survivalRate > 0.32 then
      needsAdjustment = true
      adjustmentReason = "GAMBLE生存率が高すぎる"
      BASE_MAINTENANCE = math.floor(BASE_MAINTENANCE * 1.02)
    end

    if not needsAdjustment then
      table.insert(log, "\n全戦略が目標範囲内に収まりました")
      break
    end

    adjustmentCount = adjustmentCount + 1
    table.insert(log, string.format("\n【微調整%d】%s", adjustmentCount, adjustmentReason))
    table.insert(log, string.format("維持費: %s", formatMoney(BASE_MAINTENANCE)))

    -- 再検証
    safeResult = runSimulation(strategies.SAFE, 300)
    normalResult = runSimulation(strategies.NORMAL, 300)
    gambleResult = runSimulation(strategies.GAMBLE, 300)

    table.insert(log, string.format("SAFE: %.1f%%", safeResult.survivalRate * 100))
    table.insert(log, string.format("NORMAL: %.1f%%", normalResult.survivalRate * 100))
    table.insert(log, string.format("GAMBLE: %.1f%%", gambleResult.survivalRate * 100))
  end

  -- 最終検証（1000回）
  table.insert(log, "\n【最終検証】1000回シミュレーション実行中...")
  safeResult = runSimulation(strategies.SAFE, 1000)
  normalResult = runSimulation(strategies.NORMAL, 1000)
  gambleResult = runSimulation(strategies.GAMBLE, 1000)

  table.insert(log, string.format("SAFE: %.2f%% (目標: 40-50%%)", safeResult.survivalRate * 100))
  table.insert(log, string.format("NORMAL: %.2f%% (目標: 30-40%%)", normalResult.survivalRate * 100))
  table.insert(log, string.format("GAMBLE: %.2f%% (目標: 20-30%%)", gambleResult.survivalRate * 100))

  table.insert(log, "\n=== 調整完了 ===")
  table.insert(log, string.format("最終維持費: %s", formatMoney(BASE_MAINTENANCE)))

  -- 結果をファイルに保存
  local fileContent = table.concat(log, "\n")
  fileContent = fileContent .. "\n\n【最終パラメータ】\n"
  fileContent = fileContent .. string.format("BASE_MAINTENANCE = %d\n", BASE_MAINTENANCE)
  fileContent = fileContent .. string.format("BASE_REVENUE = %d\n", BASE_REVENUE)
  fileContent = fileContent .. string.format("GACHA_COST = %d\n", GACHA_COST)
  fileContent = fileContent .. string.format("INITIAL_MONEY = %d\n", INITIAL_MONEY)

  local success, path = saveResultsToFile("balance_result.txt", fileContent)

  return {
    maintenance = BASE_MAINTENANCE,
    safeRate = safeResult.survivalRate,
    normalRate = normalResult.survivalRate,
    gambleRate = gambleResult.survivalRate,
    log = log,
    savedPath = success and path or nil
  }
end

-- ===== 初期化 =====
function initState()
  state = {
    month = 1,
    money = INITIAL_MONEY,
    reputation = 5,
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

-- ===== Love2D コールバック =====
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
        -- 自動シミュレーション
        gameState = "simulation"
        subState = "menu"
        simResults = nil
      elseif menu.selected == 3 then
        love.event.quit()
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

  elseif gameState == "simulation" then
    if subState == "menu" then
      if key == "up" then
        simMenu.selected = simMenu.selected - 1
        if simMenu.selected < 1 then simMenu.selected = #simMenu.items end
      elseif key == "down" then
        simMenu.selected = simMenu.selected + 1
        if simMenu.selected > #simMenu.items then simMenu.selected = 1 end
      elseif key == "return" or key == "space" then
        if simMenu.selected == 1 then
          -- SAFE戦略
          simResults = {SAFE = runSimulation(strategies.SAFE, SIMULATION_RUNS)}
          subState = "results"
        elseif simMenu.selected == 2 then
          -- NORMAL戦略
          simResults = {NORMAL = runSimulation(strategies.NORMAL, SIMULATION_RUNS)}
          subState = "results"
        elseif simMenu.selected == 3 then
          -- GAMBLE戦略
          simResults = {GAMBLE = runSimulation(strategies.GAMBLE, SIMULATION_RUNS)}
          subState = "results"
        elseif simMenu.selected == 4 then
          -- 全戦略実行
          simResults = {
            SAFE = runSimulation(strategies.SAFE, SIMULATION_RUNS),
            NORMAL = runSimulation(strategies.NORMAL, SIMULATION_RUNS),
            GAMBLE = runSimulation(strategies.GAMBLE, SIMULATION_RUNS)
          }
          subState = "results"
        elseif simMenu.selected == 5 then
          -- バランステスト（1000回）
          local safeRes = runSimulation(strategies.SAFE, BALANCE_TEST_RUNS)
          local normalRes = runSimulation(strategies.NORMAL, BALANCE_TEST_RUNS)
          local gambleRes = runSimulation(strategies.GAMBLE, BALANCE_TEST_RUNS)

          simResults = {
            SAFE = safeRes,
            NORMAL = normalRes,
            GAMBLE = gambleRes
          }

          -- 結果をファイルに保存
          local fileContent = string.format("=== バランステスト結果 (%d回実行) ===\n\n", BALANCE_TEST_RUNS)
          fileContent = fileContent .. string.format("維持費: %s\n\n", formatMoney(BASE_MAINTENANCE))

          for _, stratName in ipairs({"SAFE", "NORMAL", "GAMBLE"}) do
            local res = simResults[stratName]
            local strategy = strategies[stratName]
            fileContent = fileContent .. string.format("【%s】\n", strategy.name)
            fileContent = fileContent .. string.format("生存率: %.2f%%\n", res.survivalRate * 100)
            fileContent = fileContent .. string.format("中央値: %s\n", formatMoney(res.medianMoney))
            fileContent = fileContent .. string.format("平均値: %s\n", formatMoney(res.avgMoney))
            fileContent = fileContent .. string.format("最大値: %s\n\n", formatMoney(res.maxMoney))
          end

          saveResultsToFile("balance_test.txt", fileContent)

          subState = "balance_test_results"
        elseif simMenu.selected == 6 then
          -- 全自動バランス調整
          simResults = autoBalanceAll()
          subState = "auto_balance_results"
        elseif simMenu.selected == 7 then
          -- 維持費のみ調整
          local newMaint, survRate, iterations = autoAdjustMaintenance(0.30, 0.05, 15)
          simResults = {
            adjustedMaintenance = newMaint,
            survivalRate = survRate,
            iterations = iterations
          }
          subState = "adjust_results"
        elseif simMenu.selected == 8 then
          -- 戻る
          gameState = "title"
          menu.selected = 1
        end
      elseif key == "escape" then
        gameState = "title"
        menu.selected = 1
      end

    elseif subState == "results" or subState == "adjust_results" or subState == "balance_test_results" or subState == "auto_balance_results" then
      if key == "return" or key == "space" or key == "escape" then
        subState = "menu"
        simResults = nil
      end
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
  elseif gameState == "simulation" then
    drawSimulationScreen()
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
    for i = math.max(1, #gachaResults - 10), #gachaResults do
      local char = gachaResults[i]
      love.graphics.setColor(rarityColors[char.rarity])
      boldPrint(string.format("[%s] %s - %s", char.rarity, char.name, effectTypeNames[char.effectType]), 300, ry)
      ry = ry + 18
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

  -- 所持キャラ一覧
  love.graphics.setFont(menuFont)
  love.graphics.setColor(1, 1, 1)
  boldPrint("【所持キャラ】", 20, 220)

  love.graphics.setFont(tinyFont)
  local cy = 250
  for i, char in ipairs(chars) do
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

-- ===== 描画: シミュレーション =====
function drawSimulationScreen()
  local w, h = BASE_W, BASE_H
  love.graphics.clear(0.06, 0.06, 0.12)

  if subState == "menu" then
    -- メニュー画面
    love.graphics.setFont(titleFont)
    love.graphics.setColor(1, 0.6, 0.3)
    boldPrintf("自動シミュレーション", 0, 50, w, "center")

    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.6, 0.6, 0.7)
    boldPrintf(string.format("実行回数: %d回  維持費: %s", SIMULATION_RUNS, formatMoney(BASE_MAINTENANCE)), 0, 100, w, "center")

    -- 戦略説明
    love.graphics.setFont(tinyFont)
    love.graphics.setColor(0.5, 0.5, 0.6)
    local strategyInfo = {
      "SAFE: 安定重視、ガチャ最小限、生存率45%目標、収益ブレ±10%",
      "NORMAL: バランス型、中程度のガチャ、生存率35%目標、収益ブレ±20%",
      "GAMBLE: ギャンブル型、ガチャ多め、生存率25%目標、収益ブレ±50%"
    }
    local infoY = 140
    for _, info in ipairs(strategyInfo) do
      boldPrintf(info, 0, infoY, w, "center")
      infoY = infoY + 18
    end

    -- メニュー項目
    love.graphics.setFont(menuFont)
    for i, item in ipairs(simMenu.items) do
      local y = 240 + (i - 1) * 40
      if i == simMenu.selected then
        love.graphics.setColor(1, 1, 0)
        boldPrintf("> " .. item .. " <", 0, y, w, "center")
      else
        love.graphics.setColor(0.7, 0.7, 0.7)
        boldPrintf(item, 0, y, w, "center")
      end
    end

    love.graphics.setFont(tinyFont)
    love.graphics.setColor(0.4, 0.4, 0.4)
    boldPrintf("↑↓: 選択  Enter: 実行  Esc: タイトル", 0, h - 30, w, "center")

  elseif subState == "results" then
    -- 結果画面
    love.graphics.setFont(titleFont)
    love.graphics.setColor(1, 0.85, 0.3)
    boldPrintf("シミュレーション結果", 0, 30, w, "center")

    love.graphics.setFont(tinyFont)
    love.graphics.setColor(0.6, 0.6, 0.7)
    boldPrintf(string.format("%d回実行  維持費: %s", SIMULATION_RUNS, formatMoney(BASE_MAINTENANCE)), 0, 65, w, "center")

    local startY = 100
    local lineHeight = 140

    for strategyName, results in pairs(simResults) do
      local strategy = strategies[strategyName]
      local sy = startY

      -- 戦略名
      love.graphics.setFont(menuFont)
      love.graphics.setColor(1, 1, 1)
      boldPrint(strategy.name, 50, sy)
      sy = sy + 30

      -- 生存率
      love.graphics.setFont(smallFont)
      local survColor = results.survivalRate >= 0.6 and {0.3, 1, 0.5} or
                        results.survivalRate >= 0.3 and {1, 0.9, 0.3} or {1, 0.3, 0.3}
      love.graphics.setColor(survColor)
      boldPrint(string.format("生存率: %.1f%%", results.survivalRate * 100), 70, sy)
      sy = sy + 25

      -- 統計
      love.graphics.setFont(tinyFont)
      love.graphics.setColor(0.8, 0.8, 0.9)
      boldPrint(string.format("中央値: %s", formatMoney(results.medianMoney)), 70, sy)
      sy = sy + 18
      boldPrint(string.format("平均値: %s", formatMoney(results.avgMoney)), 70, sy)
      sy = sy + 18
      boldPrint(string.format("最大値: %s", formatMoney(results.maxMoney)), 70, sy)
      sy = sy + 20

      -- 分布
      love.graphics.setColor(0.7, 0.7, 0.8)
      boldPrint("【生存期間分布】", 70, sy)
      sy = sy + 16
      for period, count in pairs(results.distribution) do
        local pct = (count / results.totalRuns) * 100
        boldPrint(string.format("%s: %d回 (%.1f%%)", period, count, pct), 90, sy)
        sy = sy + 15
      end

      startY = startY + lineHeight
    end

    love.graphics.setFont(tinyFont)
    love.graphics.setColor(0.4, 0.4, 0.4)
    boldPrintf("[Enter: 戻る]", 0, h - 30, w, "center")

  elseif subState == "adjust_results" then
    -- 維持費調整結果画面
    love.graphics.setFont(titleFont)
    love.graphics.setColor(1, 0.85, 0.3)
    boldPrintf("維持費自動調整 完了", 0, 100, w, "center")

    love.graphics.setFont(menuFont)
    love.graphics.setColor(0.3, 1, 0.5)
    boldPrintf(string.format("調整後維持費: %s", formatMoney(simResults.adjustedMaintenance)), 0, 180, w, "center")

    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.8, 0.8, 0.9)
    boldPrintf(string.format("NORMAL戦略 生存率: %.1f%%", simResults.survivalRate * 100), 0, 230, w, "center")
    boldPrintf(string.format("調整回数: %d回", simResults.iterations), 0, 260, w, "center")

    love.graphics.setFont(tinyFont)
    love.graphics.setColor(0.6, 0.6, 0.7)
    boldPrintf("目標: 生存率30% (±5%)", 0, 310, w, "center")

    love.graphics.setFont(tinyFont)
    love.graphics.setColor(0.4, 0.4, 0.4)
    boldPrintf("[Enter: 戻る]", 0, h - 30, w, "center")

  elseif subState == "balance_test_results" then
    -- バランステスト結果画面（詳細版）
    love.graphics.setFont(titleFont)
    love.graphics.setColor(1, 0.85, 0.3)
    boldPrintf("バランステスト結果", 0, 15, w, "center")

    love.graphics.setFont(tinyFont)
    love.graphics.setColor(0.6, 0.6, 0.7)
    boldPrintf(string.format("%d回実行  維持費: %s", BALANCE_TEST_RUNS, formatMoney(BASE_MAINTENANCE)), 0, 45, w, "center")
    boldPrintf("結果はbalance_test.txtに保存されました", 0, 60, w, "center")

    -- 生存率比較
    love.graphics.setFont(smallFont)
    love.graphics.setColor(1, 1, 1)
    boldPrint("【生存率】", 50, 85)

    love.graphics.setFont(tinyFont)
    local sy = 110
    for _, strategyName in ipairs({"SAFE", "NORMAL", "GAMBLE"}) do
      local results = simResults[strategyName]
      local strategy = strategies[strategyName]
      local survRate = results.survivalRate * 100

      -- 目標範囲チェック
      local targetRanges = {SAFE = {40, 50}, NORMAL = {30, 40}, GAMBLE = {20, 30}}
      local range = targetRanges[strategyName]
      local inRange = survRate >= range[1] and survRate <= range[2]
      local color = inRange and {0.3, 1, 0.5} or {1, 0.3, 0.3}

      love.graphics.setColor(color)
      local status = inRange and "✓" or "✗"
      boldPrint(string.format("%s %s: %.1f%% (目標: %d-%d%%)",
        status, strategy.name, survRate, range[1], range[2]), 60, sy)
      sy = sy + 22
    end

    -- 中央値比較
    sy = sy + 15
    love.graphics.setFont(smallFont)
    love.graphics.setColor(1, 1, 1)
    boldPrint("【最終資金中央値】", 50, sy)
    sy = sy + 25

    love.graphics.setFont(tinyFont)
    for _, strategyName in ipairs({"SAFE", "NORMAL", "GAMBLE"}) do
      local results = simResults[strategyName]
      local strategy = strategies[strategyName]
      love.graphics.setColor(0.8, 0.8, 0.9)
      boldPrint(string.format("%s: %s", strategy.name, formatMoney(results.medianMoney)), 60, sy)
      sy = sy + 20
    end

    -- 詳細統計（NORMAL）
    sy = sy + 15
    love.graphics.setFont(smallFont)
    love.graphics.setColor(1, 1, 1)
    boldPrint("【NORMAL戦略 詳細】", 50, sy)
    sy = sy + 25

    local normalResults = simResults.NORMAL
    love.graphics.setFont(tinyFont)
    love.graphics.setColor(0.8, 0.8, 0.9)
    boldPrint(string.format("平均値: %s", formatMoney(normalResults.avgMoney)), 60, sy)
    sy = sy + 18
    boldPrint(string.format("最大値: %s", formatMoney(normalResults.maxMoney)), 60, sy)
    sy = sy + 22

    -- 分布
    love.graphics.setColor(0.7, 0.7, 0.8)
    boldPrint("生存期間分布:", 60, sy)
    sy = sy + 18
    for _, period in ipairs({"1-12月", "13-24月", "25-35月", "36月(クリア)"}) do
      local count = normalResults.distribution[period]
      local pct = (count / normalResults.totalRuns) * 100
      boldPrint(string.format("  %s: %.1f%%", period, pct), 70, sy)
      sy = sy + 17
    end

    love.graphics.setFont(tinyFont)
    love.graphics.setColor(0.4, 0.4, 0.4)
    boldPrintf("[Enter: 戻る]", 0, h - 30, w, "center")

  elseif subState == "auto_balance_results" then
    -- 全自動バランス調整結果画面
    love.graphics.setFont(titleFont)
    love.graphics.setColor(1, 0.85, 0.3)
    boldPrintf("全自動バランス調整 完了", 0, 15, w, "center")

    -- 保存パス表示
    if simResults.savedPath then
      love.graphics.setFont(tinyFont)
      love.graphics.setColor(0.6, 0.6, 0.7)
      boldPrintf("結果はbalance_result.txtに保存されました", 0, 45, w, "center")
    end

    -- 最終結果
    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.3, 1, 0.5)
    boldPrintf(string.format("最終維持費: %s", formatMoney(simResults.maintenance)), 0, 70, w, "center")

    -- 生存率
    love.graphics.setFont(tinyFont)
    local sy = 105
    love.graphics.setColor(1, 1, 1)
    boldPrint("【最終生存率】", 50, sy)
    sy = sy + 22

    local rates = {
      {name = "SAFE", rate = simResults.safeRate, target = "40-50%"},
      {name = "NORMAL", rate = simResults.normalRate, target = "30-40%"},
      {name = "GAMBLE", rate = simResults.gambleRate, target = "20-30%"}
    }

    for _, r in ipairs(rates) do
      local color = {0.8, 0.8, 0.9}
      love.graphics.setColor(color)
      boldPrint(string.format("%s: %.1f%% (目標: %s)", r.name, r.rate * 100, r.target), 60, sy)
      sy = sy + 20
    end

    -- ログ表示
    sy = sy + 18
    love.graphics.setFont(tinyFont)
    love.graphics.setColor(0.7, 0.7, 0.8)
    boldPrint("【調整ログ】", 50, sy)
    sy = sy + 18

    love.graphics.setColor(0.6, 0.6, 0.7)
    for i = 1, math.min(12, #simResults.log) do
      local line = simResults.log[i]
      if line:len() > 70 then
        line = line:sub(1, 67) .. "..."
      end
      boldPrint(line, 55, sy)
      sy = sy + 15
    end

    love.graphics.setFont(tinyFont)
    love.graphics.setColor(0.4, 0.4, 0.4)
    boldPrintf("[Enter: 戻る]", 0, h - 30, w, "center")
  end
end
