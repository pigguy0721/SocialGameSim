-- ============================================================
-- ガチャ編成型 経営シミュレーション
-- ============================================================

-- ===== 定数 =====
local FONT_PATH = "fonts/NotoSansJP-Regular.ttf"
local WIN_MONTHS = 36
local INITIAL_MONEY = 3000000
local GACHA_COST = 100000
local TEAM_SIZE = 5
local CHAR_LIFETIME = 3

-- ===== デバッグモード =====
local DEBUG_MODE = false

-- ===== レアリティ確率テーブル =====
local gachaTable = {
  {rarity="N", prob=0.60},
  {rarity="R", prob=0.25},
  {rarity="SR", prob=0.10},
  {rarity="SSR", prob=0.05}
}

-- ===== 効果タイプ =====
local effectTypes = {"gacha_boost", "tech_up", "content_up", "buff"}
local effectTypeNames = {
  gacha_boost = "ガチャ強化",
  tech_up = "技術力UP",
  content_up = "コンテンツUP",
  buff = "バフ"
}

-- ===== レアリティ別効果量 =====
local rarityEffects = {
  N =   {gacha_boost=1.05, tech_up=5000,  content_up=1.05, buff=1.02},
  R =   {gacha_boost=1.10, tech_up=10000, content_up=1.10, buff=1.05},
  SR =  {gacha_boost=1.20, tech_up=20000, content_up=1.20, buff=1.10},
  SSR = {gacha_boost=1.50, tech_up=50000, content_up=1.50, buff=1.20}
}

-- ===== レアリティ色 =====
local rarityColors = {
  N =   {0.7, 0.7, 0.7},
  R =   {0.3, 0.7, 1.0},
  SR =  {0.9, 0.6, 1.0},
  SSR = {1.0, 0.85, 0.2}
}

-- ===== キャラクター名リスト =====
local charNames = {
  "アリス", "ベル", "クロエ", "ダイアナ", "エミリー",
  "フィオナ", "グレース", "ハンナ", "アイリス", "ジュリア",
  "カレン", "ルナ", "ミア", "ノエル", "オリビア",
  "ペトラ", "クイーン", "ローズ", "ソフィア", "ティア"
}

-- ===== ゲームバランスパラメータ =====
local BASE_REVENUE = 200000
local BASE_MAINTENANCE = 150000
local FIRE_PENALTY_MONEY = 0.40
local FIRE_PENALTY_REPUTATION = 2
local EMPTY_SLOT_PENALTY = 15

-- ===== シミュレーション設定 =====
local SIMULATION_RUNS = 100000  -- 通常シミュレーション回数
local BALANCE_TEST_RUNS = 100000  -- バランステスト用（高精度）

-- ===== 太字描画ヘルパー =====
local BOLD_OFFSET = 0.8

function boldPrint(text, x, y)
  love.graphics.print(text, x + BOLD_OFFSET, y)
  love.graphics.print(text, x, y)
end

function boldPrintf(text, x, y, limit, align)
  love.graphics.printf(text, x + BOLD_OFFSET, y, limit, align)
  love.graphics.printf(text, x, y, limit, align)
end

-- ===== フォーマット関数 =====
function formatMoney(num)
  if num >= 1000000 then
    return string.format("%.1fM円", num / 1000000)
  elseif num >= 1000 then
    return string.format("%dK円", math.floor(num / 1000))
  else
    return string.format("%d円", num)
  end
end

function formatNumber(num)
  if num >= 1000000 then
    return string.format("%.1fM", num / 1000000)
  elseif num >= 1000 then
    return string.format("%dK", math.floor(num / 1000))
  else
    return tostring(num)
  end
end

-- ===== ゲーム状態 =====
local gameState = "title"
local subState = "select"

local menu = { items = { "手動プレイ", "自動シミュレーション", "終了" }, selected = 1 }

local state = {}
local chars = {}
local team = {}
local selectedCharIndex = nil
local selectedSlotIndex = nil
local gachaResults = {}
local monthReport = {}

-- シミュレーション関連
local simMenu = { items = {"SAFE戦略", "NORMAL戦略", "GAMBLE戦略", "全戦略実行", "バランステスト(1000回)", "全自動バランス調整", "維持費のみ調整", "戻る"}, selected = 1 }
local simResults = nil
local simRunning = false
local simProgress = 0

-- ===== フォント =====
local largeFont, titleFont, menuFont, smallFont, tinyFont

-- ===== ガチャシステム =====
local nextCharId = 1

function rollGacha()
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

  local effectType = effectTypes[math.random(#effectTypes)]

  return createCharacter(selectedRarity, effectType)
end

function createCharacter(rarity, effectType)
  local char = {
    id = nextCharId,
    rarity = rarity,
    effectType = effectType,
    effectValue = rarityEffects[rarity][effectType],
    lifetime = CHAR_LIFETIME,
    acquiredMonth = state.month,
    name = charNames[math.random(#charNames)] .. " #" .. nextCharId
  }
  nextCharId = nextCharId + 1
  return char
end

-- ===== 編成システム =====
function calculateTeamBalance(currentTeam)
  local typeCounts = {gacha_boost=0, tech_up=0, content_up=0, buff=0}
  local emptySlots = 0

  for i = 1, TEAM_SIZE do
    if currentTeam[i] then
      typeCounts[currentTeam[i].effectType] = typeCounts[currentTeam[i].effectType] + 1
    else
      emptySlots = emptySlots + 1
    end
  end

  -- 標準偏差計算
  local mean = TEAM_SIZE / 4
  local variance = 0
  for _, count in pairs(typeCounts) do
    variance = variance + (count - mean) ^ 2
  end
  variance = variance / 4
  local stdDev = math.sqrt(variance)

  -- バランススコア（0-100）
  local balanceScore = math.min(100, stdDev * 30)

  -- 空枠ペナルティ
  balanceScore = balanceScore + (emptySlots * EMPTY_SLOT_PENALTY)

  return math.min(100, balanceScore)
end

-- ===== 収益計算 =====
function calculateRevenue(currentTeam, varianceAmount)
  varianceAmount = varianceAmount or 0.20  -- デフォルト±20%
  local baseRevenue = BASE_REVENUE

  -- キャラ補正
  local gachaBoost = 1.0
  local techBonus = 0
  local contentBoost = 1.0
  local buffMultiplier = 1.0

  for i = 1, TEAM_SIZE do
    if currentTeam[i] then
      local char = currentTeam[i]
      if char.effectType == "gacha_boost" then
        gachaBoost = gachaBoost * char.effectValue
      elseif char.effectType == "tech_up" then
        techBonus = techBonus + char.effectValue
      elseif char.effectType == "content_up" then
        contentBoost = contentBoost * char.effectValue
      elseif char.effectType == "buff" then
        buffMultiplier = buffMultiplier * char.effectValue
      end
    end
  end

  local totalRevenue = (baseRevenue + techBonus) * gachaBoost * contentBoost * buffMultiplier

  -- ランダムブレ（戦略ごとに変動）
  local minVariance = 1.0 - varianceAmount
  local maxVariance = 1.0 + varianceAmount
  local variance = minVariance + math.random() * (maxVariance - minVariance)
  totalRevenue = totalRevenue * variance

  return math.floor(totalRevenue)
end

-- ===== 炎上システム =====
function checkFire(balanceScore, reputation)
  local baseProb = balanceScore * 0.005  -- 0-50%
  local reputationMod = (10 - reputation) * 0.02  -- 0-20%
  local totalProb = baseProb + reputationMod

  totalProb = math.max(0, math.min(0.80, totalProb))

  return math.random() < totalProb, totalProb
end

-- ===== 戦略AI =====
local strategies = {
  SAFE = {
    name = "SAFE戦略",
    description = "安定重視：ガチャ最小限、バランス編成",
    targetSurvivalRate = 0.45,  -- 40-50%
    revenueVariance = 0.10,  -- ±10% (収益ブレ最小)

    -- ガチャ回数決定
    gachaCount = function(month, money, charsCount)
      -- 資金に余裕があり、キャラが少ない場合のみ1回
      if money > 1000000 and charsCount < 3 then
        return 1
      end
      return 0
    end,

    -- 編成選択
    selectFormation = function(availableChars, month)
      -- 最もバランスの取れた編成を選択
      local bestTeam = {}
      local bestScore = 999

      -- 全キャラから5体選ぶ組み合わせを評価（簡易版：上位5体）
      local sortedChars = {}
      for _, char in ipairs(availableChars) do
        table.insert(sortedChars, char)
      end

      -- レアリティ順にソート（バランス重視）
      table.sort(sortedChars, function(a, b)
        local rarityOrder = {N=1, R=2, SR=3, SSR=4}
        return rarityOrder[a.rarity] > rarityOrder[b.rarity]
      end)

      -- バランスを考慮して選択
      local typeCounts = {gacha_boost=0, tech_up=0, content_up=0, buff=0}
      for i = 1, math.min(TEAM_SIZE, #sortedChars) do
        local char = sortedChars[i]
        -- 同タイプが2個以上ある場合はスキップ
        if typeCounts[char.effectType] < 2 then
          table.insert(bestTeam, char)
          typeCounts[char.effectType] = typeCounts[char.effectType] + 1
        end
      end

      return bestTeam
    end
  },

  NORMAL = {
    name = "NORMAL戦略",
    description = "バランス型：中程度のガチャ、レアリティ優先",
    targetSurvivalRate = 0.35,  -- 30-40%
    revenueVariance = 0.20,  -- ±20% (収益ブレ中)

    gachaCount = function(month, money, charsCount)
      if month <= 6 then
        return money >= 200000 and 2 or 1
      elseif month <= 18 then
        return money >= 500000 and 1 or 0
      else
        return money >= 800000 and 1 or 0
      end
    end,

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

      -- 同タイプ3枚まで制限
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
