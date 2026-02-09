-- ソシャゲ運営シミュ（シンプル版）
-- 仕様: E:\work\helloworld\docs\simple_gacha_sim_spec.md

-- ========================================
-- 定数
-- ========================================
local WINDOW_WIDTH = 800
local WINDOW_HEIGHT = 600

-- ========================================
-- 設定システム
-- ========================================
local config = {
    maxMonths = 36,
    initialMoney = 2000,        -- 万円
    baseActionCost = 100,       -- 万円
    actionCostMultiplier = 1.4,

    -- 炎上システム
    fireBaseRate = 5,           -- 基礎炎上率(%)
    fireRatePerAction = 4,      -- 行動ごとの増加率(%)
    fireMoneyLoss = 0.3,        -- 資金減少率
    fireUserLoss = 0.15,        -- ユーザ減少率

    -- アイテム効果
    gachaItemRevenue = 0.10,    -- 収益+10%
    contentItemRevenue = 0.05,  -- 収益+5%
    adItemUsers = 0.10,         -- ユーザ+10%

    -- ユーザ変動
    newUserPerFame = 100,       -- 知名度あたりの新規ユーザ
    leaveRateBase = 6,          -- 離脱率計算の基礎値
    leaveRateMultiplier = 0.03, -- 離脱率の倍率

    -- 評価補正
    ratingMultipliers = {0.5, 0.8, 1.0, 1.3, 1.6},

    -- 初期値
    initialRating = 3,
    initialUsers = 1000,
}

-- デフォルト設定を保存
local defaultConfig = {}
for k, v in pairs(config) do
    if type(v) == "table" then
        defaultConfig[k] = {}
        for i, val in ipairs(v) do
            defaultConfig[k][i] = val
        end
    else
        defaultConfig[k] = v
    end
end

-- 設定を保存
function saveConfig()
    local content = "-- Game Config\nreturn {\n"
    for k, v in pairs(config) do
        if type(v) == "table" then
            content = content .. "    " .. k .. " = {"
            for i, val in ipairs(v) do
                content = content .. val
                if i < #v then content = content .. ", " end
            end
            content = content .. "},\n"
        else
            content = content .. "    " .. k .. " = " .. v .. ",\n"
        end
    end
    content = content .. "}\n"

    love.filesystem.write("config.lua", content)
end

-- 設定を読み込み
function loadConfig()
    if love.filesystem.getInfo("config.lua") then
        local chunk = love.filesystem.load("config.lua")
        if chunk then
            local loaded = chunk()
            for k, v in pairs(loaded) do
                config[k] = v
            end
        end
    end
end

-- デフォルト設定に戻す
function resetConfig()
    for k, v in pairs(defaultConfig) do
        if type(v) == "table" then
            config[k] = {}
            for i, val in ipairs(v) do
                config[k][i] = val
            end
        else
            config[k] = v
        end
    end
end

-- ========================================
-- グローバル変数
-- ========================================
local gameState = "title"  -- "title", "settings", "autoplay", "autoplay_result", "game", "gameover", "clear"
local subState = "month_start"
local font
local largeFont
local smallFont
local selectedIndex = 1
local messageTimer = 0
local currentMessage = ""

-- 設定画面用
local settingsCategories = {
    "基本設定",
    "炎上システム",
    "アイテム効果",
    "ユーザ変動",
    "評価補正"
}
local settingsSelectedCategory = 1
local settingsSelectedItem = 1
local settingsItems = {}

-- オートプレイ用
local autoplayState = {
    running = false,
    totalRuns = 0,
    currentRun = 0,
    results = {},  -- 小規模実行時のみ使用
    mode = 1,  -- 1=10回, 2=10000回, 3=100万回

    -- リアルタイム統計集計
    statsAccum = {
        survived = 0,
        totalMonths = 0,
        totalMoney = 0,
        totalUsers = 0,
        totalFires = 0,
        totalRanking = 0,
        maxMonths = 0,
        minMonths = 999,
        maxMoney = -999999,
        minMoney = 999999,
        maxUsers = 0,
        minUsers = 999999,
        maxRanking = 999,
        minRanking = 1,

        -- 分布データ（ヒストグラム）
        monthsDist = {},     -- 月数分布
        moneyDist = {},      -- 資金分布
        usersDist = {},      -- ユーザ数分布
    },

    -- 最終結果統計
    stats = {
        survived = 0,
        survivalRate = 0,
        avgMonths = 0,
        avgMoney = 0,
        avgUsers = 0,
        avgRanking = 0,
        avgFires = 0,
        maxMonths = 0,
        minMonths = 999,
        maxMoney = 0,
        minMoney = 0,
        maxUsers = 0,
        minUsers = 0,
        maxRanking = 999,
        minRanking = 1,
        csvFilename = "",
        statsFilename = "",

        -- 分布データ
        monthsDist = {},
        moneyDist = {},
        usersDist = {},
    }
}

-- ========================================
-- ゲーム状態
-- ========================================
local state = {}

function initState()
    state = {
        month = 1,
        money = config.initialMoney,

        -- 成長パラメータ
        character = 0,
        tech = 0,
        fame = 0,

        -- 状態パラメータ
        rating = config.initialRating,
        users = config.initialUsers,
        ranking = 100,

        -- 月内状態
        actionsThisMonth = 0,

        -- アイテム（1ヶ月寿命）
        gachaItems = 0,
        contentItems = 0,
        adItems = 0,

        -- 行動結果（表示用）
        lastActionResult = {},
        fireResult = nil,
        monthEndResult = {},
    }
end

-- ========================================
-- ヘルパー関数
-- ========================================
function boldPrint(text, x, y)
    love.graphics.print(text, x, y)
    love.graphics.print(text, x + 0.8, y)
end

function boldPrintf(text, x, y, limit, align)
    love.graphics.printf(text, x, y, limit, align)
    love.graphics.printf(text, x + 0.8, y, limit, align)
end

function formatMoney(amount)
    return string.format("%d万円", math.floor(amount))
end

function formatNumber(num)
    return string.format("%d", math.floor(num))
end

function getRatingStars(rating)
    return string.rep("★", rating) .. string.rep("☆", 5 - rating)
end

-- ========================================
-- 行動コスト計算
-- ========================================
function getActionCost(actionCount)
    return math.floor(config.baseActionCost * math.pow(config.actionCostMultiplier, actionCount))
end

-- ========================================
-- 行動定義
-- ========================================
local actions = {
    {
        name = "ガチャ実装",
        desc = "キャラ↑ 収益アイテム獲得 炎上率:大",
        execute = function()
            state.character = state.character + 1
            state.gachaItems = state.gachaItems + 1
            return {
                "キャラ +1",
                "収益アイテム(ガチャ) を獲得",
            }
        end
    },
    {
        name = "コンテンツ実装",
        desc = "技術力↑ 収益バフアイテム獲得 炎上率:中",
        execute = function()
            state.tech = state.tech + 1
            state.contentItems = state.contentItems + 1
            return {
                "技術力 +1",
                "収益バフアイテム(コンテンツ) を獲得",
            }
        end
    },
    {
        name = "広告",
        desc = "知名度↑ ユーザ増加バフ獲得 炎上率:小",
        execute = function()
            state.fame = state.fame + 1
            state.adItems = state.adItems + 1
            return {
                "知名度 +1",
                "ユーザ増加バフ(広告) を獲得",
            }
        end
    },
}

-- ========================================
-- 行動実行
-- ========================================
function executeAction(actionIndex)
    local action = actions[actionIndex]
    local cost = getActionCost(state.actionsThisMonth)

    if state.money < cost then
        return false, "資金不足"
    end

    state.money = state.money - cost
    state.actionsThisMonth = state.actionsThisMonth + 1

    local results = action.execute()

    state.lastActionResult = {
        name = action.name,
        cost = cost,
        results = results,
        newMoney = state.money,
    }

    return true, nil
end

-- ========================================
-- 炎上判定
-- ========================================
function checkFire()
    local fireRate = config.fireBaseRate + (state.actionsThisMonth * config.fireRatePerAction)
    local roll = math.random(100)

    if roll <= fireRate then
        local moneyLoss = math.floor(state.money * config.fireMoneyLoss)
        local userLoss = math.floor(state.users * config.fireUserLoss)

        state.money = state.money - moneyLoss
        state.rating = math.max(1, state.rating - 1)
        state.users = math.max(0, state.users - userLoss)

        state.fireResult = {
            happened = true,
            rate = fireRate,
            moneyLoss = moneyLoss,
            ratingLoss = 1,
            userLoss = userLoss,
        }

        return true
    else
        state.fireResult = {
            happened = false,
            rate = fireRate,
        }
        return false
    end
end

-- ========================================
-- 月末処理
-- ========================================
function processMonthEnd()
    local result = {
        items = {
            gacha = state.gachaItems,
            content = state.contentItems,
            ad = state.adItems,
        }
    }

    -- 新規ユーザ
    local newUsers = state.fame * config.newUserPerFame

    -- 広告バフ適用
    if state.adItems > 0 then
        newUsers = math.floor(newUsers * (1 + state.adItems * config.adItemUsers))
    end

    state.users = state.users + newUsers
    result.newUsers = newUsers

    -- 離脱ユーザ
    local leaveRate = (config.leaveRateBase - state.rating) * config.leaveRateMultiplier
    local leaveUsers = math.floor(state.users * leaveRate)
    state.users = math.max(0, state.users - leaveUsers)
    result.leaveUsers = leaveUsers
    result.leaveRate = leaveRate * 100

    -- 収益計算
    local ratingMultiplier = config.ratingMultipliers[state.rating] or 1.0

    local revenue = state.users * ratingMultiplier

    -- ガチャアイテムバフ
    if state.gachaItems > 0 then
        revenue = revenue * (1 + state.gachaItems * config.gachaItemRevenue)
    end

    -- コンテンツアイテムバフ
    if state.contentItems > 0 then
        revenue = revenue * (1 + state.contentItems * config.contentItemRevenue)
    end

    revenue = math.floor(revenue / 10000)
    state.money = state.money + revenue
    result.revenue = revenue
    result.ratingMultiplier = ratingMultiplier

    -- セルラン更新
    if state.users > 100000 then
        state.ranking = math.random(1, 10)
    elseif state.users > 50000 then
        state.ranking = math.random(10, 30)
    elseif state.users > 10000 then
        state.ranking = math.random(30, 80)
    else
        state.ranking = math.random(80, 150)
    end

    -- アイテム消滅
    state.gachaItems = 0
    state.contentItems = 0
    state.adItems = 0

    -- 行動カウントリセット
    state.actionsThisMonth = 0

    state.monthEndResult = result
end

-- ========================================
-- 次月へ
-- ========================================
function advanceMonth()
    state.month = state.month + 1

    if state.month > config.maxMonths then
        gameState = "clear"
        return
    end

    if state.money <= 0 then
        gameState = "gameover"
        return
    end

    subState = "month_start"
    selectedIndex = 1
end

-- ========================================
-- オートプレイ
-- ========================================
function startAutoplay(mode)
    autoplayState.mode = mode
    if mode == 1 then
        autoplayState.totalRuns = 10
    elseif mode == 2 then
        autoplayState.totalRuns = 10000
    else
        autoplayState.totalRuns = 1000000
    end
    autoplayState.currentRun = 0
    autoplayState.results = {}
    autoplayState.running = true

    -- 統計アキュムレータを初期化
    autoplayState.statsAccum = {
        survived = 0,
        totalMonths = 0,
        totalMoney = 0,
        totalUsers = 0,
        totalFires = 0,
        totalRanking = 0,
        maxMonths = 0,
        minMonths = 999,
        maxMoney = -999999,
        minMoney = 999999,
        maxUsers = 0,
        minUsers = 999999,
        maxRanking = 999,
        minRanking = 1,

        -- 分布データ初期化
        monthsDist = {},
        moneyDist = {},
        usersDist = {},
    }

    -- 月数分布（0-36ヶ月）
    for i = 0, config.maxMonths do
        autoplayState.statsAccum.monthsDist[i] = 0
    end

    -- 資金分布（10区間）
    for i = 1, 10 do
        autoplayState.statsAccum.moneyDist[i] = 0
    end

    -- ユーザ数分布（10区間）
    for i = 1, 10 do
        autoplayState.statsAccum.usersDist[i] = 0
    end
end

function runOneAutoplayGame()
    initState()

    local log = {
        survived = false,
        months = 0,
        finalMoney = 0,
        finalUsers = 0,
        finalRating = 0,
        finalRanking = 100,
        totalActions = 0,
        fireCount = 0,
    }

    while state.month <= config.maxMonths and state.money > 0 do
        -- 簡単なAI戦略：資金がある限り、ランダムに1-3回行動
        local actionCount = math.random(1, 3)

        for i = 1, actionCount do
            local cost = getActionCost(state.actionsThisMonth)
            if state.money >= cost then
                local actionIndex = math.random(1, 3)
                executeAction(actionIndex)
                log.totalActions = log.totalActions + 1
            else
                break
            end
        end

        -- 炎上判定
        if checkFire() then
            if state.fireResult.happened then
                log.fireCount = log.fireCount + 1
            end
        end

        -- 月末処理
        processMonthEnd()

        log.months = state.month

        -- 次月へ
        state.month = state.month + 1

        if state.month > config.maxMonths then
            log.survived = true
            break
        end

        if state.money <= 0 then
            break
        end

        -- 次月の準備
        state.actionsThisMonth = 0
    end

    log.finalMoney = state.money
    log.finalUsers = state.users
    log.finalRating = state.rating
    log.finalRanking = state.ranking

    return log
end

function updateAutoplay()
    if not autoplayState.running then return end

    -- 1フレームで複数回実行（高速化）
    local runsPerFrame = autoplayState.totalRuns > 1000 and 1000 or 10

    for i = 1, runsPerFrame do
        if autoplayState.currentRun >= autoplayState.totalRuns then
            autoplayState.running = false
            saveAutoplayResults()
            break
        end

        autoplayState.currentRun = autoplayState.currentRun + 1
        local result = runOneAutoplayGame()

        -- リアルタイム統計集計
        local accum = autoplayState.statsAccum
        if result.survived then accum.survived = accum.survived + 1 end
        accum.totalMonths = accum.totalMonths + result.months
        accum.totalMoney = accum.totalMoney + result.finalMoney
        accum.totalUsers = accum.totalUsers + result.finalUsers
        accum.totalRanking = accum.totalRanking + result.finalRanking
        accum.totalFires = accum.totalFires + result.fireCount

        -- 最大/最小
        accum.maxMonths = math.max(accum.maxMonths, result.months)
        accum.minMonths = math.min(accum.minMonths, result.months)
        accum.maxMoney = math.max(accum.maxMoney, result.finalMoney)
        accum.minMoney = math.min(accum.minMoney, result.finalMoney)
        accum.maxUsers = math.max(accum.maxUsers, result.finalUsers)
        accum.minUsers = math.min(accum.minUsers, result.finalUsers)
        accum.maxRanking = math.max(accum.maxRanking, result.finalRanking)
        accum.minRanking = math.min(accum.minRanking, result.finalRanking)

        -- 月数分布
        if accum.monthsDist[result.months] then
            accum.monthsDist[result.months] = accum.monthsDist[result.months] + 1
        end

        -- 資金分布（10区間: <0, 0-500, 500-1000, 1000-2000, 2000-3000, 3000-5000, 5000-10000, 10000-20000, 20000-50000, 50000+）
        local moneyBucket = 1
        if result.finalMoney < 0 then moneyBucket = 1
        elseif result.finalMoney < 500 then moneyBucket = 2
        elseif result.finalMoney < 1000 then moneyBucket = 3
        elseif result.finalMoney < 2000 then moneyBucket = 4
        elseif result.finalMoney < 3000 then moneyBucket = 5
        elseif result.finalMoney < 5000 then moneyBucket = 6
        elseif result.finalMoney < 10000 then moneyBucket = 7
        elseif result.finalMoney < 20000 then moneyBucket = 8
        elseif result.finalMoney < 50000 then moneyBucket = 9
        else moneyBucket = 10 end
        accum.moneyDist[moneyBucket] = accum.moneyDist[moneyBucket] + 1

        -- ユーザ数分布（10区間: 0-1k, 1k-5k, 5k-10k, 10k-20k, 20k-50k, 50k-100k, 100k-200k, 200k-500k, 500k-1M, 1M+）
        local usersBucket = 1
        if result.finalUsers < 1000 then usersBucket = 1
        elseif result.finalUsers < 5000 then usersBucket = 2
        elseif result.finalUsers < 10000 then usersBucket = 3
        elseif result.finalUsers < 20000 then usersBucket = 4
        elseif result.finalUsers < 50000 then usersBucket = 5
        elseif result.finalUsers < 100000 then usersBucket = 6
        elseif result.finalUsers < 200000 then usersBucket = 7
        elseif result.finalUsers < 500000 then usersBucket = 8
        elseif result.finalUsers < 1000000 then usersBucket = 9
        else usersBucket = 10 end
        accum.usersDist[usersBucket] = accum.usersDist[usersBucket] + 1

        -- 大規模実行時はサンプリング（最初の1000件のみ保存）
        if autoplayState.totalRuns <= 10000 or #autoplayState.results < 1000 then
            table.insert(autoplayState.results, result)
        end
    end
end

function saveAutoplayResults()
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local filename = string.format("autoplay_%s.csv", timestamp)

    -- CSV保存（大規模実行時はサンプルのみ）
    if #autoplayState.results > 0 then
        local csv = "run,survived,months,finalMoney,finalUsers,finalRating,totalActions,fireCount\n"

        if autoplayState.totalRuns > 10000 then
            csv = csv .. string.format("# サンプルデータ（最初の%d件）\n", #autoplayState.results)
        end

        for i, result in ipairs(autoplayState.results) do
            csv = csv .. string.format("%d,%s,%d,%d,%d,%d,%d,%d\n",
                i,
                result.survived and "TRUE" or "FALSE",
                result.months,
                result.finalMoney,
                result.finalUsers,
                result.finalRating,
                result.totalActions,
                result.fireCount
            )
        end

        love.filesystem.write(filename, csv)
    end

    -- 統計情報を計算（リアルタイム集計から）
    calculateAutoplayStats()

    -- 統計情報をテキストファイルにも保存
    local statsFilename = string.format("autoplay_stats_%s.txt", timestamp)
    local statsText = formatAutoplayStatsText()
    love.filesystem.write(statsFilename, statsText)

    -- ファイル名を保存
    autoplayState.stats.csvFilename = filename
    autoplayState.stats.statsFilename = statsFilename

    -- 結果画面に遷移
    gameState = "autoplay_result"
    selectedIndex = 1
end

function calculateAutoplayStats()
    -- リアルタイム集計された統計を使用
    local accum = autoplayState.statsAccum
    local count = autoplayState.totalRuns

    if count == 0 then return end

    autoplayState.stats.survived = accum.survived
    autoplayState.stats.survivalRate = (accum.survived / count) * 100
    autoplayState.stats.avgMonths = accum.totalMonths / count
    autoplayState.stats.avgMoney = accum.totalMoney / count
    autoplayState.stats.avgUsers = accum.totalUsers / count
    autoplayState.stats.avgRanking = accum.totalRanking / count
    autoplayState.stats.avgFires = accum.totalFires / count
    autoplayState.stats.maxMonths = accum.maxMonths
    autoplayState.stats.minMonths = accum.minMonths
    autoplayState.stats.maxMoney = accum.maxMoney
    autoplayState.stats.minMoney = accum.minMoney
    autoplayState.stats.maxUsers = accum.maxUsers
    autoplayState.stats.minUsers = accum.minUsers
    autoplayState.stats.maxRanking = accum.maxRanking
    autoplayState.stats.minRanking = accum.minRanking
    autoplayState.stats.totalRuns = count

    -- 分布データをコピー
    autoplayState.stats.monthsDist = accum.monthsDist
    autoplayState.stats.moneyDist = accum.moneyDist
    autoplayState.stats.usersDist = accum.usersDist
end

function formatAutoplayStatsText()
    local s = autoplayState.stats
    return string.format([[オートプレイ統計結果

実行回数: %d
生存率: %.2f%% (%d / %d)

生存月数:
- 平均: %.2f ヶ月
- 最長: %d ヶ月
- 最短: %d ヶ月

最終資金:
- 平均: %.0f 万円
- 最大: %.0f 万円
- 最小: %.0f 万円

最終ユーザ数:
- 平均: %.0f
- 最大: %.0f
- 最小: %.0f

最終セルラン:
- 平均: %.1f 位
- 最高: %d 位
- 最低: %d 位

平均炎上回数: %.2f 回

設定:
- 初期資金: %d万円
- 基本コスト: %d万円
- コスト倍率: %.2f
- 炎上基礎率: %d%%
- 炎上増加率: %d%%/行動
]],
        s.totalRuns,
        s.survivalRate, s.survived, s.totalRuns,
        s.avgMonths,
        s.maxMonths,
        s.minMonths,
        s.avgMoney,
        s.maxMoney,
        s.minMoney,
        s.avgUsers,
        s.maxUsers,
        s.minUsers,
        s.avgRanking,
        s.minRanking,
        s.maxRanking,
        s.avgFires,
        config.initialMoney,
        config.baseActionCost,
        config.actionCostMultiplier,
        config.fireBaseRate,
        config.fireRatePerAction
    )
end

-- ========================================
-- 設定画面
-- ========================================
function buildSettingsItems()
    settingsItems = {
        ["基本設定"] = {
            {name = "最大月数", key = "maxMonths", min = 12, max = 120, step = 6},
            {name = "初期資金(万円)", key = "initialMoney", min = 500, max = 5000, step = 100},
            {name = "基本行動コスト", key = "baseActionCost", min = 50, max = 500, step = 10},
            {name = "コスト倍率", key = "actionCostMultiplier", min = 1.1, max = 2.0, step = 0.1, decimal = true},
        },
        ["炎上システム"] = {
            {name = "基礎炎上率(%)", key = "fireBaseRate", min = 0, max = 20, step = 1},
            {name = "行動毎増加率(%)", key = "fireRatePerAction", min = 1, max = 10, step = 1},
            {name = "資金減少率", key = "fireMoneyLoss", min = 0.1, max = 0.5, step = 0.05, decimal = true},
            {name = "ユーザ減少率", key = "fireUserLoss", min = 0.05, max = 0.3, step = 0.05, decimal = true},
        },
        ["アイテム効果"] = {
            {name = "ガチャ収益率", key = "gachaItemRevenue", min = 0.05, max = 0.30, step = 0.05, decimal = true},
            {name = "コンテンツ収益率", key = "contentItemRevenue", min = 0.02, max = 0.15, step = 0.01, decimal = true},
            {name = "広告ユーザ率", key = "adItemUsers", min = 0.05, max = 0.30, step = 0.05, decimal = true},
        },
        ["ユーザ変動"] = {
            {name = "知名度あたり新規", key = "newUserPerFame", min = 50, max = 500, step = 50},
            {name = "初期ユーザ数", key = "initialUsers", min = 500, max = 5000, step = 500},
            {name = "離脱率基礎値", key = "leaveRateBase", min = 4, max = 10, step = 1},
            {name = "離脱率倍率", key = "leaveRateMultiplier", min = 0.01, max = 0.10, step = 0.01, decimal = true},
        },
        ["評価補正"] = {
            {name = "★1倍率", key = "ratingMultipliers", index = 1, min = 0.3, max = 1.0, step = 0.1, decimal = true},
            {name = "★2倍率", key = "ratingMultipliers", index = 2, min = 0.5, max = 1.2, step = 0.1, decimal = true},
            {name = "★3倍率", key = "ratingMultipliers", index = 3, min = 0.8, max = 1.5, step = 0.1, decimal = true},
            {name = "★4倍率", key = "ratingMultipliers", index = 4, min = 1.0, max = 2.0, step = 0.1, decimal = true},
            {name = "★5倍率", key = "ratingMultipliers", index = 5, min = 1.3, max = 2.5, step = 0.1, decimal = true},
        },
    }
end

function adjustSetting(item, direction)
    local value
    if item.index then
        value = config[item.key][item.index]
    else
        value = config[item.key]
    end

    value = value + (item.step * direction)
    value = math.max(item.min, math.min(item.max, value))

    if item.decimal then
        value = math.floor(value * 100 + 0.5) / 100
    else
        value = math.floor(value + 0.5)
    end

    if item.index then
        config[item.key][item.index] = value
    else
        config[item.key] = value
    end
end

-- ========================================
-- Love2D コールバック
-- ========================================
function love.load()
    love.window.setTitle("ソシャゲ運営シミュ")
    love.window.setMode(WINDOW_WIDTH, WINDOW_HEIGHT, {
        resizable = false,
        minwidth = WINDOW_WIDTH,
        minheight = WINDOW_HEIGHT,
    })

    font = love.graphics.newFont("fonts/NotoSansJP-Regular.ttf", 18)
    largeFont = love.graphics.newFont("fonts/NotoSansJP-Regular.ttf", 32)
    smallFont = love.graphics.newFont("fonts/NotoSansJP-Regular.ttf", 14)
    love.graphics.setFont(font)

    math.randomseed(os.time())

    loadConfig()
    buildSettingsItems()
    initState()
end

function love.keypressed(key)
    if key == "escape" then
        if gameState == "title" then
            love.event.quit()
        elseif gameState == "settings" or gameState == "autoplay" or gameState == "autoplay_result" then
            gameState = "title"
            selectedIndex = 1
        else
            gameState = "title"
            initState()
        end
        return
    end

    if gameState == "title" then
        if key == "up" then
            selectedIndex = math.max(1, selectedIndex - 1)
        elseif key == "down" then
            selectedIndex = math.min(4, selectedIndex + 1)
        elseif key == "space" or key == "return" then
            if selectedIndex == 1 then
                gameState = "game"
                subState = "month_start"
                initState()
                selectedIndex = 1
            elseif selectedIndex == 2 then
                gameState = "settings"
                settingsSelectedCategory = 1
                settingsSelectedItem = 1
            elseif selectedIndex == 3 then
                gameState = "autoplay"
                selectedIndex = 1
            elseif selectedIndex == 4 then
                love.event.quit()
            end
        end

    elseif gameState == "settings" then
        local category = settingsCategories[settingsSelectedCategory]
        local items = settingsItems[category]

        if key == "up" then
            settingsSelectedItem = math.max(1, settingsSelectedItem - 1)
        elseif key == "down" then
            settingsSelectedItem = math.min(#items + 2, settingsSelectedItem + 1)
        elseif key == "left" then
            if settingsSelectedItem <= #items then
                adjustSetting(items[settingsSelectedItem], -1)
            elseif settingsSelectedItem == #items + 1 then
                settingsSelectedCategory = math.max(1, settingsSelectedCategory - 1)
                settingsSelectedItem = 1
            end
        elseif key == "right" then
            if settingsSelectedItem <= #items then
                adjustSetting(items[settingsSelectedItem], 1)
            elseif settingsSelectedItem == #items + 1 then
                settingsSelectedCategory = math.min(#settingsCategories, settingsSelectedCategory + 1)
                settingsSelectedItem = 1
            end
        elseif key == "space" or key == "return" then
            if settingsSelectedItem == #items + 1 then
                -- カテゴリ切替
            elseif settingsSelectedItem == #items + 2 then
                -- 保存して戻る
                saveConfig()
                gameState = "title"
                selectedIndex = 1
            end
        elseif key == "r" then
            resetConfig()
        end

    elseif gameState == "autoplay" then
        if not autoplayState.running then
            if key == "up" then
                selectedIndex = math.max(1, selectedIndex - 1)
            elseif key == "down" then
                selectedIndex = math.min(4, selectedIndex + 1)
            elseif key == "space" or key == "return" then
                if selectedIndex <= 3 then
                    startAutoplay(selectedIndex)
                else
                    gameState = "title"
                    selectedIndex = 1
                end
            end
        end

    elseif gameState == "autoplay_result" then
        if key == "space" or key == "return" then
            gameState = "title"
            selectedIndex = 1
        elseif key == "s" then
            -- 統計情報を再表示（コンソールまたはメッセージ）
            currentMessage = "統計: " .. autoplayState.stats.csvFilename
            messageTimer = 5
        end

    elseif gameState == "game" then
        if subState == "month_start" then
            if key == "space" or key == "return" then
                subState = "action_select"
                selectedIndex = 1
            end

        elseif subState == "action_select" then
            if key == "up" then
                selectedIndex = math.max(1, selectedIndex - 1)
            elseif key == "down" then
                selectedIndex = math.min(4, selectedIndex + 1)
            elseif key == "space" or key == "return" then
                if selectedIndex == 4 then
                    subState = "fire_check"
                    checkFire()
                else
                    local success, error = executeAction(selectedIndex)
                    if success then
                        subState = "action_result"
                    else
                        currentMessage = error or "実行失敗"
                        messageTimer = 2
                    end
                end
            end

        elseif subState == "action_result" then
            if key == "space" or key == "return" then
                subState = "action_select"
                selectedIndex = 1
            end

        elseif subState == "fire_check" then
            if key == "space" or key == "return" then
                processMonthEnd()
                subState = "month_end"
            end

        elseif subState == "month_end" then
            if key == "space" or key == "return" then
                advanceMonth()
            end
        end

    elseif gameState == "gameover" or gameState == "clear" then
        if key == "space" or key == "return" then
            gameState = "title"
            initState()
        end
    end
end

function love.update(dt)
    if messageTimer > 0 then
        messageTimer = messageTimer - dt
        if messageTimer < 0 then
            messageTimer = 0
            currentMessage = ""
        end
    end

    if gameState == "autoplay" then
        updateAutoplay()
    end
end

function love.draw()
    love.graphics.clear(0.1, 0.1, 0.15)

    if gameState == "title" then
        drawTitleScreen()
    elseif gameState == "settings" then
        drawSettingsScreen()
    elseif gameState == "autoplay" then
        drawAutoplayScreen()
    elseif gameState == "autoplay_result" then
        drawAutoplayResultScreen()
    elseif gameState == "game" then
        drawGameScreen()
    elseif gameState == "gameover" then
        drawGameOverScreen()
    elseif gameState == "clear" then
        drawClearScreen()
    end

    -- メッセージ表示
    if messageTimer > 0 then
        love.graphics.setColor(1, 1, 0.3)
        boldPrintf(currentMessage, 0, WINDOW_HEIGHT - 40, WINDOW_WIDTH, "center")
        love.graphics.setColor(1, 1, 1)
    end
end

-- ========================================
-- 描画関数
-- ========================================
function drawTitleScreen()
    love.graphics.setFont(largeFont)
    love.graphics.setColor(1, 1, 0.5)
    boldPrintf("ソシャゲ運営シミュ", 0, 120, WINDOW_WIDTH, "center")

    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1)
    boldPrintf("シンプル版", 0, 180, WINDOW_WIDTH, "center")

    local y = 260
    local menuItems = {"ゲーム開始", "ゲーム設定", "オートプレイ", "終了"}

    for i, item in ipairs(menuItems) do
        if selectedIndex == i then
            love.graphics.setColor(1, 1, 0)
            boldPrint("→ " .. item, 320, y)
        else
            love.graphics.setColor(1, 1, 1)
            boldPrint("  " .. item, 320, y)
        end
        y = y + 40
    end

    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.7, 0.7, 0.7)
    boldPrintf("↑↓: 選択 / SPACE: 決定 / ESC: 終了", 0, 520, WINDOW_WIDTH, "center")
end

function drawSettingsScreen()
    love.graphics.setFont(largeFont)
    love.graphics.setColor(1, 1, 0.5)
    boldPrint("ゲーム設定", 50, 20)

    love.graphics.setFont(font)

    -- カテゴリ表示
    local x = 50
    local y = 80
    for i, category in ipairs(settingsCategories) do
        if i == settingsSelectedCategory then
            love.graphics.setColor(1, 1, 0)
            boldPrint("【" .. category .. "】", x, y)
        else
            love.graphics.setColor(0.5, 0.5, 0.5)
            boldPrint(category, x, y)
        end
        x = x + 140
    end

    -- 設定項目表示
    y = 130
    local category = settingsCategories[settingsSelectedCategory]
    local items = settingsItems[category]

    for i, item in ipairs(items) do
        local value
        if item.index then
            value = config[item.key][item.index]
        else
            value = config[item.key]
        end

        if settingsSelectedItem == i then
            love.graphics.setColor(1, 1, 0)
            boldPrint("→", 50, y)
        end

        love.graphics.setColor(1, 1, 1)
        boldPrint(item.name .. ":", 80, y)

        love.graphics.setColor(0.5, 1, 0.5)
        if item.decimal then
            boldPrint(string.format("%.2f", value), 400, y)
        else
            boldPrint(string.format("%d", value), 400, y)
        end

        love.graphics.setColor(0.5, 0.5, 0.5)
        love.graphics.setFont(smallFont)
        boldPrint(string.format("[%s - %s]",
            item.decimal and string.format("%.2f", item.min) or tostring(item.min),
            item.decimal and string.format("%.2f", item.max) or tostring(item.max)
        ), 500, y + 2)
        love.graphics.setFont(font)

        y = y + 30
    end

    y = y + 20

    -- カテゴリ切替
    if settingsSelectedItem == #items + 1 then
        love.graphics.setColor(1, 1, 0)
        boldPrint("→", 50, y)
    end
    love.graphics.setColor(0.7, 0.7, 1)
    boldPrint("← カテゴリ切替 →", 80, y)
    y = y + 35

    -- 保存して戻る
    if settingsSelectedItem == #items + 2 then
        love.graphics.setColor(1, 1, 0)
        boldPrint("→", 50, y)
    end
    love.graphics.setColor(0.5, 1, 0.5)
    boldPrint("保存して戻る", 80, y)

    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.7, 0.7, 0.7)
    boldPrintf("↑↓: 選択 / ←→: 調整/カテゴリ切替 / R: デフォルトに戻す / ESC: 戻る", 0, 550, WINDOW_WIDTH, "center")
end

function drawAutoplayScreen()
    love.graphics.setFont(largeFont)
    love.graphics.setColor(1, 1, 0.5)
    boldPrint("オートプレイ", 50, 30)

    love.graphics.setFont(font)

    if autoplayState.running then
        -- 実行中
        local y = 150
        love.graphics.setColor(1, 1, 1)
        boldPrint("実行中...", 300, y)
        y = y + 60

        love.graphics.setColor(0.5, 1, 0.5)
        boldPrint(string.format("進行: %d / %d (%.1f%%)",
            autoplayState.currentRun,
            autoplayState.totalRuns,
            (autoplayState.currentRun / autoplayState.totalRuns) * 100
        ), 200, y)

        -- プログレスバー
        y = y + 50
        local barWidth = 400
        local barHeight = 30
        local barX = (WINDOW_WIDTH - barWidth) / 2
        love.graphics.setColor(0.3, 0.3, 0.3)
        love.graphics.rectangle("fill", barX, y, barWidth, barHeight)
        love.graphics.setColor(0.5, 1, 0.5)
        local progress = (autoplayState.currentRun / autoplayState.totalRuns) * barWidth
        love.graphics.rectangle("fill", barX, y, progress, barHeight)

    else
        -- メニュー
        local y = 120
        love.graphics.setColor(1, 1, 1)
        boldPrint("実行回数を選択:", 250, y)
        y = y + 60

        local modes = {
            "10回（テスト用）",
            "10,000回（バランス確認）",
            "1,000,000回（詳細分析）",
            "戻る"
        }

        for i, mode in ipairs(modes) do
            if selectedIndex == i then
                love.graphics.setColor(1, 1, 0)
                boldPrint("→ " .. mode, 200, y)
            else
                love.graphics.setColor(1, 1, 1)
                boldPrint("  " .. mode, 200, y)
            end
            y = y + 40
        end

        y = y + 40
        love.graphics.setColor(0.7, 0.7, 0.7)
        love.graphics.setFont(smallFont)
        boldPrint("※結果はCSVファイルとして保存されます", 200, y)
        boldPrint(string.format("  保存先: %s", love.filesystem.getSaveDirectory()), 200, y + 20)
    end

    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.7, 0.7, 0.7)
    if not autoplayState.running then
        boldPrintf("↑↓: 選択 / SPACE: 決定 / ESC: 戻る", 0, 550, WINDOW_WIDTH, "center")
    else
        boldPrintf("実行中... しばらくお待ちください", 0, 550, WINDOW_WIDTH, "center")
    end
end

function drawAutoplayResultScreen()
    love.graphics.setFont(largeFont)
    love.graphics.setColor(1, 1, 0.5)
    boldPrint("オートプレイ結果", 50, 15)

    local s = autoplayState.stats
    love.graphics.setFont(smallFont)

    -- 左側: 統計情報
    local leftX = 20
    local y = 60

    -- 実行回数と生存率
    love.graphics.setColor(1, 1, 1)
    boldPrint(string.format("実行: %d回", s.totalRuns or autoplayState.totalRuns), leftX, y)
    y = y + 18
    local survivalColor = s.survivalRate >= 50 and {0.5, 1, 0.5} or s.survivalRate >= 30 and {1, 1, 0.5} or {1, 0.5, 0.5}
    love.graphics.setColor(survivalColor)
    boldPrint(string.format("生存率: %.1f%% (%d/%d)", s.survivalRate, s.survived, s.totalRuns or autoplayState.totalRuns), leftX, y)
    y = y + 22

    -- 生存月数
    love.graphics.setColor(0.7, 1, 1)
    boldPrint(string.format("月数 平均:%.1f 最長:%d 最短:%d", s.avgMonths, s.maxMonths, s.minMonths), leftX, y)
    y = y + 20

    -- 最終資金
    love.graphics.setColor(1, 1, 0.5)
    boldPrint(string.format("資金 平均:%s", formatMoney(s.avgMoney)), leftX, y)
    y = y + 16
    boldPrint(string.format("    最大:%s 最小:%s", formatMoney(s.maxMoney), formatMoney(s.minMoney)), leftX, y)
    y = y + 20

    -- 最終ユーザ数
    love.graphics.setColor(0.7, 1, 0.7)
    boldPrint(string.format("ユーザ 平均:%s", formatNumber(s.avgUsers)), leftX, y)
    y = y + 16
    boldPrint(string.format("      最大:%s 最小:%s", formatNumber(s.maxUsers), formatNumber(s.minUsers)), leftX, y)
    y = y + 20

    -- 最終セルラン
    love.graphics.setColor(1, 0.7, 1)
    boldPrint(string.format("セルラン 平均:%.0f位", s.avgRanking), leftX, y)
    y = y + 16
    boldPrint(string.format("        最高:%d位 最低:%d位", s.minRanking, s.maxRanking), leftX, y)
    y = y + 20

    -- 炎上
    love.graphics.setColor(1, 0.7, 0.7)
    boldPrint(string.format("平均炎上: %.2f回", s.avgFires), leftX, y)
    y = y + 25

    -- 保存ファイル
    love.graphics.setColor(0.5, 1, 0.5)
    boldPrint("保存:", leftX, y)
    y = y + 16
    love.graphics.setColor(0.6, 0.6, 0.6)
    boldPrint((s.csvFilename or ""):sub(1, 25), leftX, y)
    y = y + 14
    boldPrint((s.statsFilename or ""):sub(1, 25), leftX, y)

    -- 右側: グラフ
    local graphX = 410
    local graphWidth = 370
    local graphHeight = 140

    -- グラフ1: 終了月数分布
    drawHistogram(graphX, 60, graphWidth, graphHeight, "終了月数分布", s.monthsDist, config.maxMonths)

    -- グラフ2: 最終資金分布
    drawHistogram(graphX, 220, graphWidth, graphHeight, "最終資金分布", s.moneyDist, 10,
        {"<0", "0-500", "500-1k", "1k-2k", "2k-3k", "3k-5k", "5k-10k", "10k-20k", "20k-50k", "50k+"})

    -- グラフ3: 最終ユーザ数分布
    drawHistogram(graphX, 380, graphWidth, graphHeight, "最終ユーザ数分布", s.usersDist, 10,
        {"<1k", "1k-5k", "5k-10k", "10k-20k", "20k-50k", "50k-100k", "100k-200k", "200k-500k", "500k-1M", "1M+"})

    -- 操作説明
    love.graphics.setColor(0.7, 0.7, 0.7)
    boldPrintf("SPACE: タイトルへ / ESC: 戻る", 0, 570, WINDOW_WIDTH, "center")
end

-- ヒストグラム描画
function drawHistogram(x, y, width, height, title, data, maxBuckets, labels)
    love.graphics.setFont(smallFont)

    -- タイトル
    love.graphics.setColor(1, 1, 0.5)
    boldPrint(title, x, y)

    -- グラフエリア
    local graphY = y + 20
    local graphH = height - 25
    local barWidth = width / maxBuckets

    -- 最大値を見つける
    local maxValue = 0
    for i = 1, maxBuckets do
        local value = data[i] or data[i-1] or 0
        maxValue = math.max(maxValue, value)
    end

    if maxValue == 0 then
        love.graphics.setColor(0.5, 0.5, 0.5)
        boldPrint("データなし", x + width/2 - 40, graphY + graphH/2)
        return
    end

    -- 棒グラフ描画
    for i = 1, maxBuckets do
        local value = data[i] or data[i-1] or 0
        local barHeight = (value / maxValue) * graphH
        local barX = x + (i - 1) * barWidth

        -- 棒
        love.graphics.setColor(0.3, 0.7, 1)
        love.graphics.rectangle("fill", barX + 1, graphY + graphH - barHeight, barWidth - 2, barHeight)

        -- 枠
        love.graphics.setColor(0.2, 0.2, 0.3)
        love.graphics.rectangle("line", barX + 1, graphY, barWidth - 2, graphH)

        -- ラベル（一部のみ表示）
        if labels and i % math.ceil(maxBuckets / 5) == 1 then
            love.graphics.setColor(0.7, 0.7, 0.7)
            love.graphics.printf(labels[i] or "", barX, graphY + graphH + 2, barWidth, "center")
        elseif not labels and maxBuckets <= 40 and i % math.ceil(maxBuckets / 8) == 0 then
            love.graphics.setColor(0.7, 0.7, 0.7)
            love.graphics.printf(tostring(i-1), barX, graphY + graphH + 2, barWidth, "center")
        end
    end
end

function drawGameScreen()
    if subState == "month_start" then
        drawMonthStartScreen()
    elseif subState == "action_select" then
        drawActionSelectScreen()
    elseif subState == "action_result" then
        drawActionResultScreen()
    elseif subState == "fire_check" then
        drawFireCheckScreen()
    elseif subState == "month_end" then
        drawMonthEndScreen()
    end
end

function drawMonthStartScreen()
    drawHeader()

    love.graphics.setFont(largeFont)
    love.graphics.setColor(1, 1, 0.5)
    boldPrintf(string.format("%d ヶ月目", state.month), 0, 200, WINDOW_WIDTH, "center")

    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1)
    boldPrintf("今月も頑張りましょう", 0, 280, WINDOW_WIDTH, "center")

    love.graphics.setColor(0.7, 0.7, 0.7)
    boldPrintf("SPACE: 続ける", 0, 500, WINDOW_WIDTH, "center")
end

function drawActionSelectScreen()
    drawHeader()

    local x = 50
    local y = 120

    love.graphics.setColor(1, 1, 0.5)
    boldPrint("▼ 行動を選択", x, y)
    y = y + 40

    for i, action in ipairs(actions) do
        local cost = getActionCost(state.actionsThisMonth)
        local canAfford = state.money >= cost

        if selectedIndex == i then
            love.graphics.setColor(1, 1, 0)
            boldPrint("→", x, y)
        end

        if canAfford then
            love.graphics.setColor(1, 1, 1)
        else
            love.graphics.setColor(0.5, 0.5, 0.5)
        end

        boldPrint(string.format("%s (コスト: %s)", action.name, formatMoney(cost)), x + 30, y)
        love.graphics.setColor(0.7, 0.7, 0.7)
        boldPrint(action.desc, x + 50, y + 22)

        y = y + 60
    end

    if selectedIndex == 4 then
        love.graphics.setColor(1, 1, 0)
        boldPrint("→", x, y)
    end
    love.graphics.setColor(0.5, 1, 0.5)
    boldPrint("月末へ進む", x + 30, y)

    y = y + 60
    love.graphics.setColor(1, 0.7, 0.7)
    local fireRate = config.fireBaseRate + (state.actionsThisMonth * config.fireRatePerAction)
    boldPrint(string.format("今月の行動数: %d回 / 炎上率: %d%%", state.actionsThisMonth, fireRate), x, y)

    love.graphics.setColor(0.7, 0.7, 0.7)
    boldPrintf("↑↓: 選択 / SPACE: 決定", 0, 550, WINDOW_WIDTH, "center")
end

function drawActionResultScreen()
    drawHeader()

    local x = 100
    local y = 150

    love.graphics.setColor(1, 1, 0.5)
    boldPrint("▼ " .. state.lastActionResult.name, x, y)
    y = y + 40

    love.graphics.setColor(1, 0.5, 0.5)
    boldPrint("コスト: " .. formatMoney(state.lastActionResult.cost), x, y)
    y = y + 30

    love.graphics.setColor(0.5, 1, 0.5)
    for _, result in ipairs(state.lastActionResult.results) do
        boldPrint("・" .. result, x, y)
        y = y + 25
    end

    y = y + 20
    love.graphics.setColor(1, 1, 1)
    boldPrint("残り資金: " .. formatMoney(state.lastActionResult.newMoney), x, y)

    love.graphics.setColor(0.7, 0.7, 0.7)
    boldPrintf("SPACE: 続ける", 0, 500, WINDOW_WIDTH, "center")
end

function drawFireCheckScreen()
    drawHeader()

    local x = 100
    local y = 150

    love.graphics.setColor(1, 1, 0.5)
    boldPrint("▼ 炎上判定", x, y)
    y = y + 40

    love.graphics.setColor(1, 1, 1)
    boldPrint(string.format("炎上率: %d%%", state.fireResult.rate), x, y)
    y = y + 40

    if state.fireResult.happened then
        love.graphics.setColor(1, 0.3, 0.3)
        boldPrint("炎上発生！！", x, y)
        y = y + 40

        love.graphics.setColor(1, 0.5, 0.5)
        boldPrint("資金 -" .. formatMoney(state.fireResult.moneyLoss), x, y)
        y = y + 25
        boldPrint("評価 -" .. state.fireResult.ratingLoss, x, y)
        y = y + 25
        boldPrint("ユーザ -" .. formatNumber(state.fireResult.userLoss), x, y)
    else
        love.graphics.setColor(0.5, 1, 0.5)
        boldPrint("炎上回避", x, y)
    end

    love.graphics.setColor(0.7, 0.7, 0.7)
    boldPrintf("SPACE: 月末処理へ", 0, 500, WINDOW_WIDTH, "center")
end

function drawMonthEndScreen()
    drawHeader()

    local x = 80
    local y = 120

    love.graphics.setColor(1, 1, 0.5)
    boldPrint("▼ 月末処理", x, y)
    y = y + 40

    local result = state.monthEndResult

    if result.items.gacha > 0 or result.items.content > 0 or result.items.ad > 0 then
        love.graphics.setColor(0.7, 0.7, 1)
        boldPrint("アイテム効果（今月で消滅）:", x, y)
        y = y + 25
        if result.items.gacha > 0 then
            boldPrint(string.format("  ガチャ×%d (収益+%d%%)", result.items.gacha, math.floor(result.items.gacha * config.gachaItemRevenue * 100)), x, y)
            y = y + 22
        end
        if result.items.content > 0 then
            boldPrint(string.format("  コンテンツ×%d (収益+%d%%)", result.items.content, math.floor(result.items.content * config.contentItemRevenue * 100)), x, y)
            y = y + 22
        end
        if result.items.ad > 0 then
            boldPrint(string.format("  広告×%d (ユーザ+%d%%)", result.items.ad, math.floor(result.items.ad * config.adItemUsers * 100)), x, y)
            y = y + 22
        end
        y = y + 10
    end

    love.graphics.setColor(0.5, 1, 0.5)
    boldPrint("新規ユーザ: +" .. formatNumber(result.newUsers), x, y)
    y = y + 25

    love.graphics.setColor(1, 0.5, 0.5)
    boldPrint(string.format("離脱ユーザ: -%s (離脱率%.1f%%)", formatNumber(result.leaveUsers), result.leaveRate), x, y)
    y = y + 35

    love.graphics.setColor(1, 1, 0.5)
    boldPrint(string.format("収益: +%s (評価補正×%.1f)", formatMoney(result.revenue), result.ratingMultiplier), x, y)
    y = y + 25

    love.graphics.setColor(1, 1, 1)
    boldPrint("最終資金: " .. formatMoney(state.money), x, y)

    love.graphics.setColor(0.7, 0.7, 0.7)
    boldPrintf("SPACE: 次月へ", 0, 550, WINDOW_WIDTH, "center")
end

function drawGameOverScreen()
    love.graphics.setFont(largeFont)
    love.graphics.setColor(1, 0.3, 0.3)
    boldPrintf("GAME OVER", 0, 150, WINDOW_WIDTH, "center")

    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1)
    boldPrintf(string.format("生存期間: %d ヶ月", state.month - 1), 0, 250, WINDOW_WIDTH, "center")
    boldPrintf("資金が尽きました", 0, 280, WINDOW_WIDTH, "center")

    love.graphics.setColor(0.7, 0.7, 0.7)
    boldPrintf("SPACE: タイトルへ", 0, 450, WINDOW_WIDTH, "center")
end

function drawClearScreen()
    love.graphics.setFont(largeFont)
    love.graphics.setColor(1, 1, 0)
    boldPrintf("CLEAR!", 0, 150, WINDOW_WIDTH, "center")

    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1)
    boldPrintf(string.format("%dヶ月生存達成！", config.maxMonths), 0, 250, WINDOW_WIDTH, "center")
    boldPrintf(string.format("最終資金: %s", formatMoney(state.money)), 0, 280, WINDOW_WIDTH, "center")
    boldPrintf(string.format("最終ユーザ数: %s", formatNumber(state.users)), 0, 310, WINDOW_WIDTH, "center")
    boldPrintf(string.format("最終評価: %s", getRatingStars(state.rating)), 0, 340, WINDOW_WIDTH, "center")

    love.graphics.setColor(0.7, 0.7, 0.7)
    boldPrintf("SPACE: タイトルへ", 0, 450, WINDOW_WIDTH, "center")
end

function drawHeader()
    local y = 10
    love.graphics.setColor(1, 1, 1)

    boldPrint(string.format("%d ヶ月目 / %d", state.month, config.maxMonths), 20, y)

    local moneyColor = state.money > 1000 and {0.5, 1, 0.5} or state.money > 500 and {1, 1, 1} or {1, 0.5, 0.5}
    love.graphics.setColor(moneyColor)
    boldPrint("資金: " .. formatMoney(state.money), 20, y + 25)

    local rightX = WINDOW_WIDTH - 250
    love.graphics.setColor(1, 1, 1)
    boldPrint("評価: " .. getRatingStars(state.rating), rightX, y)
    boldPrint("ユーザ: " .. formatNumber(state.users), rightX, y + 25)
    boldPrint("セルラン: " .. state.ranking .. "位", rightX, y + 50)

    y = y + 80
    love.graphics.setColor(0.8, 0.8, 1)
    boldPrint(string.format("キャラ:%d / 技術:%d / 知名度:%d", state.character, state.tech, state.fame), 20, y)

    love.graphics.setColor(0.3, 0.3, 0.3)
    love.graphics.rectangle("fill", 0, y + 25, WINDOW_WIDTH, 2)
end
