-- ============================================================
-- ソシャゲ運営ローグライク — タスク管理システム
-- Phase 1: 基本実装
-- ============================================================

-- ===== 定数 =====
local FONT_PATH = "fonts/NotoSansJP-Regular.ttf"
local MAX_STAT = 100

-- 時間単位
local WEEKS_PER_MONTH = 4
local DEV_MONTHS = 24
local START_MONTH = 4  -- 4月スタート

-- 経済定数
local INITIAL_DEBT = 5000  -- 万円
local INTEREST_RATE = 0.03  -- 月次3%
local AUTO_REPAY_RATIO = 0.30

-- ===== グローバル変数 =====
local font
local smallFont
local state = nil  -- ゲーム状態

-- ===== ヘルパー関数 =====
local BOLD_OFFSET = 0.8

function boldPrint(text, x, y)
  love.graphics.print(text, x + BOLD_OFFSET, y)
  love.graphics.print(text, x, y)
end

function boldPrintf(text, x, y, limit, align)
  love.graphics.printf(text, x + BOLD_OFFSET, y, limit, align)
  love.graphics.printf(text, x, y, limit, align)
end

-- 年月変換
function monthToDate(month)
  local m = ((month - 1 + START_MONTH - 1) % 12) + 1
  local year = math.floor((month - 1 + START_MONTH - 1) / 12) + 1
  return year, m
end

function monthToDateStr(month)
  local y, m = monthToDate(month)
  return string.format("%d年目 %d月", y, m)
end

-- ===== タスクデータ定義 =====
local NEGATIVE_TASKS = {
  -- 技術トラブル
  {id="bug_report", name="バグ報告", category="tech", penalty_tech=-5, penalty_users=0, penalty_money=0, trigger_task="major_bug", trigger_prob=0.3},
  {id="major_bug", name="大規模バグ発生", category="tech", penalty_tech=-15, penalty_users=-500, penalty_money=0},
  {id="server_load", name="サーバー負荷増大", category="tech", penalty_tech=-10, penalty_users=-300, penalty_money=0, trigger_task="server_down", trigger_prob=0.3},
  {id="server_down", name="サーバーダウン", category="tech", penalty_tech=-20, penalty_users=-1000, penalty_money=0},
  -- コンテンツ枯渇
  {id="char_request", name="新キャラ要望", category="content", penalty_tech=0, penalty_users=0, penalty_money=0, penalty_content=-5},
  {id="event_drought", name="イベント枯渇", category="content", penalty_tech=0, penalty_users=-200, penalty_money=0, penalty_content=-10, trigger_task="user_complaint", trigger_prob=0.3},
  -- 炎上対応
  {id="user_complaint", name="ユーザークレーム", category="fame", penalty_tech=0, penalty_users=0, penalty_money=0, penalty_fame=-5, trigger_task="sns_flame", trigger_prob=0.3},
  {id="sns_flame", name="SNS炎上", category="fame", penalty_tech=0, penalty_users=-800, penalty_money=0, penalty_fame=-15, trigger_task="major_flame", trigger_prob=0.3},
  {id="major_flame", name="大炎上", category="fame", penalty_tech=0, penalty_users=-2000, penalty_money=-500, penalty_fame=-30},
}

local POSITIVE_TASKS = {
  -- 広報機会
  {id="cm_offer", name="CM出稿依頼", category="fame", reward_fame=10, reward_users=500},
  {id="collab_offer", name="コラボ打診", category="fame", reward_fame=20, reward_users=1000, reward_content=10},
  {id="influencer", name="インフルエンサー案件", category="fame", reward_fame=10, reward_users=500},
  -- 季節イベント
  {id="summer_event", name="水着イベント準備", category="content", reward_fame=10, reward_content=10, reward_money=200},
  {id="anniversary", name="周年記念準備", category="content", reward_fame=20, reward_content=20, reward_users=1000},
}

-- ===== スキルデータ定義 =====
local SKILLS = {
  -- 技術系スキル
  {id="bug_fix", name="バグ修正", category="tech", unlock_level=20, cost=50, effect_tech=10, solves={"bug_report"}},
  {id="server_upgrade", name="サーバー増強", category="tech", unlock_level=40, cost=100, effect_tech=20, solves={"server_load"}},
  {id="emergency_maint", name="緊急メンテナンス", category="tech", unlock_level=60, cost=200, effect_tech=30, solves={"major_bug", "server_down"}},
  {id="automation", name="自動化システム導入", category="tech", unlock_level=80, cost=400, effect_tech=40, solves={}},

  -- 知名度系スキル
  {id="sns_campaign", name="SNS広報キャンペーン", category="fame", unlock_level=20, cost=50, effect_fame=10, solves={"cm_offer"}},
  {id="influencer_deal", name="インフルエンサー案件", category="fame", unlock_level=40, cost=100, effect_fame=20, solves={"influencer"}},
  {id="tv_cm", name="テレビCM", category="fame", unlock_level=60, cost=200, effect_fame=30, solves={}},
  {id="collab_negotiate", name="大型コラボ交渉", category="fame", unlock_level=80, cost=400, effect_fame=40, solves={"collab_offer"}},

  -- コンテンツ系スキル
  {id="char_planning", name="キャラクター企画", category="content", unlock_level=20, cost=50, effect_content=10, solves={"char_request"}},
  {id="event_planning", name="イベント企画", category="content", unlock_level=40, cost=100, effect_content=20, solves={"event_drought", "summer_event"}},
  {id="major_event", name="大型イベント企画", category="content", unlock_level=60, cost=200, effect_content=30, solves={"anniversary"}},
  {id="new_system", name="新システム実装", category="content", unlock_level=80, cost=400, effect_content=40, solves={}},

  -- 対応スキル（炎上対応）
  {id="official_statement", name="公式声明発表", category="response", unlock_level=15, cost=50, effect_fame=5, solves={"user_complaint"}},
  {id="apology_gems", name="詫び石配布", category="response", unlock_level=30, cost=100, effect_fame=10, solves={"sns_flame"}},
  {id="refund", name="返金対応", category="response", unlock_level=50, cost=200, effect_fame=20, solves={"major_flame"}},
}

-- ===== ゲーム状態初期化 =====
function initState()
  return {
    phase = "dev",  -- dev or operation
    month = 1,
    week = 1,  -- 1-4

    -- 基本情報
    users = 0,
    money = INITIAL_DEBT,  -- 初期は借金額と同じ
    debt = INITIAL_DEBT,

    -- メインステータス (0-100)
    tech = 10,
    fame = 10,
    content = 10,

    -- 派生指標
    storeRating = 1,  -- 1-5 stars
    salesRank = 999,  -- 順位

    -- タスク管理
    tasks = {},  -- {task=taskDef, deterioration=0, type="negative/positive"}

    -- スキル管理
    unlockedSkills = {},  -- スキルIDのセット

    -- UI状態
    mode = "main",  -- main, skill_select, item_select
    selectedSkill = nil,
    selectedTask = nil,

    -- ゲームオーバー
    gameOver = false,
    gameOverReason = "",
    victory = false,

    -- ログ
    logs = {},
  }
end

-- ===== タスク管理関数 =====
function generateTasks(s)
  -- 月初に6件程度のタスクを生成（ポジティブ/ネガティブ混在）
  local numNegative = math.random(3, 4)
  local numPositive = math.random(2, 3)

  -- ネガティブタスク生成
  for i = 1, numNegative do
    local taskDef = NEGATIVE_TASKS[math.random(#NEGATIVE_TASKS)]
    table.insert(s.tasks, {task=taskDef, deterioration=0, type="negative"})
  end

  -- ポジティブタスク生成
  for i = 1, numPositive do
    local taskDef = POSITIVE_TASKS[math.random(#POSITIVE_TASKS)]
    table.insert(s.tasks, {task=taskDef, deterioration=0, type="positive"})
  end

  table.insert(s.logs, string.format("新規タスク発生: %d件", numNegative + numPositive))
end

function deteriorateTasks(s)
  -- 月末にネガティブタスクを悪化させる
  local newTasks = {}

  for i = #s.tasks, 1, -1 do
    local taskEntry = s.tasks[i]

    if taskEntry.type == "negative" then
      -- 悪化度を増加
      taskEntry.deterioration = taskEntry.deterioration + 1

      -- 悪化倍率（上限4倍）
      local multiplier = math.min(taskEntry.deterioration, 4)

      -- ペナルティ適用
      local task = taskEntry.task
      if task.penalty_tech then
        local penalty = task.penalty_tech * multiplier
        s.tech = math.max(0, s.tech + penalty)
        if penalty < 0 then
          table.insert(s.logs, string.format("%s悪化: 技術力%d", task.name, penalty))
        end
      end
      if task.penalty_fame then
        local penalty = task.penalty_fame * multiplier
        s.fame = math.max(0, s.fame + penalty)
        if penalty < 0 then
          table.insert(s.logs, string.format("%s悪化: 知名度%d", task.name, penalty))
        end
      end
      if task.penalty_content then
        local penalty = task.penalty_content * multiplier
        s.content = math.max(0, s.content + penalty)
        if penalty < 0 then
          table.insert(s.logs, string.format("%s悪化: コンテンツ力%d", task.name, penalty))
        end
      end
      if task.penalty_users then
        local penalty = task.penalty_users * multiplier
        s.users = math.max(0, s.users + penalty)
        if penalty < 0 then
          table.insert(s.logs, string.format("%s悪化: ユーザー%d人", task.name, penalty))
        end
      end
      if task.penalty_money then
        local penalty = task.penalty_money * multiplier
        s.money = s.money + penalty
        if penalty < 0 then
          table.insert(s.logs, string.format("%s悪化: 資金%d万", task.name, penalty))
        end
      end

      -- 確率的に新規タスク誘発
      if task.trigger_task and task.trigger_prob and taskEntry.deterioration >= 1 then
        if math.random() < task.trigger_prob then
          -- 誘発タスクを探す
          for _, negTask in ipairs(NEGATIVE_TASKS) do
            if negTask.id == task.trigger_task then
              table.insert(newTasks, {task=negTask, deterioration=0, type="negative"})
              table.insert(s.logs, string.format("誘発: %s → %s", task.name, negTask.name))
              break
            end
          end
        end
      end

      -- タスク継続
      -- (s.tasksにそのまま残る)
    elseif taskEntry.type == "positive" then
      -- ポジティブタスクは月末に消滅
      table.remove(s.tasks, i)
      table.insert(s.logs, string.format("機会損失: %s", taskEntry.task.name))
    end
  end

  -- 誘発されたタスクを追加
  for _, newTask in ipairs(newTasks) do
    table.insert(s.tasks, newTask)
  end
end

-- ===== スキル管理関数 =====
function checkSkillUnlocks(s)
  -- ステータスに応じてスキルを自動習得
  for _, skill in ipairs(SKILLS) do
    if not s.unlockedSkills[skill.id] then
      local unlocked = false

      if skill.category == "tech" and s.tech >= skill.unlock_level then
        unlocked = true
      elseif skill.category == "fame" and s.fame >= skill.unlock_level then
        unlocked = true
      elseif skill.category == "content" and s.content >= skill.unlock_level then
        unlocked = true
      elseif skill.category == "response" and s.fame >= skill.unlock_level then
        unlocked = true
      end

      if unlocked then
        s.unlockedSkills[skill.id] = true
        table.insert(s.logs, string.format("スキル習得: %s", skill.name))
      end
    end
  end
end

function findSkill(skillId)
  for _, skill in ipairs(SKILLS) do
    if skill.id == skillId then
      return skill
    end
  end
  return nil
end

function canSolveTask(skill, taskEntry)
  -- スキルがタスクを解決できるか判定
  for _, solvableTaskId in ipairs(skill.solves) do
    if taskEntry.task.id == solvableTaskId then
      return true
    end
  end
  return false
end

function useSkill(s, skillId, targetTaskIndex)
  local skill = findSkill(skillId)
  if not skill then return false end

  -- コストチェック
  if s.money < skill.cost then
    table.insert(s.logs, string.format("%s: 資金不足", skill.name))
    return false
  end

  -- コスト支払い
  s.money = s.money - skill.cost

  -- スキル効果適用
  if skill.effect_tech then
    s.tech = math.min(MAX_STAT, s.tech + skill.effect_tech)
  end
  if skill.effect_fame then
    s.fame = math.min(MAX_STAT, s.fame + skill.effect_fame)
  end
  if skill.effect_content then
    s.content = math.min(MAX_STAT, s.content + skill.effect_content)
  end

  table.insert(s.logs, string.format("%s 使用（コスト: %d万）", skill.name, skill.cost))

  -- タスク解決
  if targetTaskIndex and s.tasks[targetTaskIndex] then
    local taskEntry = s.tasks[targetTaskIndex]

    if canSolveTask(skill, taskEntry) then
      -- ポジティブタスクの場合は報酬を追加
      if taskEntry.type == "positive" then
        local task = taskEntry.task
        if task.reward_tech then
          s.tech = math.min(MAX_STAT, s.tech + task.reward_tech)
        end
        if task.reward_fame then
          s.fame = math.min(MAX_STAT, s.fame + task.reward_fame)
        end
        if task.reward_content then
          s.content = math.min(MAX_STAT, s.content + task.reward_content)
        end
        if task.reward_users then
          s.users = s.users + task.reward_users
        end
        if task.reward_money then
          s.money = s.money + task.reward_money
        end
        table.insert(s.logs, string.format("タスク完了: %s（報酬獲得）", taskEntry.task.name))
      else
        table.insert(s.logs, string.format("タスク解決: %s", taskEntry.task.name))
      end

      -- タスク削除
      table.remove(s.tasks, targetTaskIndex)
      return true
    else
      table.insert(s.logs, "このスキルはこのタスクを解決できません")
      return false
    end
  end

  return true
end

-- ===== 週進行 =====
function advanceWeek(s)
  s.week = s.week + 1

  if s.week > WEEKS_PER_MONTH then
    -- 月末処理
    table.insert(s.logs, "=== 月末処理 ===")

    -- タスク悪化処理
    deteriorateTasks(s)

    -- 月を進める
    s.month = s.month + 1
    s.week = 1

    -- フェーズ切り替え
    if s.phase == "dev" and s.month > DEV_MONTHS then
      s.phase = "operation"
      table.insert(s.logs, "=== 運営期開始 ===")

      -- リリース時のユーザー獲得
      local initialUsers = math.floor(s.fame * 100)
      s.users = initialUsers
      table.insert(s.logs, string.format("初期ユーザー: %d人", initialUsers))
    end

    -- 月初処理
    table.insert(s.logs, "=== 月初処理 ===")

    -- タスク生成
    generateTasks(s)

    -- 運営期のみ
    if s.phase == "operation" then
      -- 収支計算
      local chargeRate = s.content / 100 * 0.05  -- コンテンツ力に応じた課金率
      local revenue = math.floor(s.users * chargeRate * 10)

      local maint = math.floor(50 * (1 + s.month * 0.05))
      local interest = math.floor(s.debt * INTEREST_RATE)

      local profit = revenue - maint - interest
      s.money = s.money + profit

      -- 自動返済
      if profit > 0 then
        local repay = math.floor(profit * AUTO_REPAY_RATIO)
        repay = math.min(repay, s.debt)
        s.debt = s.debt - repay
        table.insert(s.logs, string.format("自動返済: %d万", repay))
      end

      table.insert(s.logs, string.format("売上: %d万", revenue))
      table.insert(s.logs, string.format("維持費: %d万", maint))
      table.insert(s.logs, string.format("利子: %d万", interest))
      table.insert(s.logs, string.format("純利益: %d万", profit))

      -- ユーザー変動
      local inflowRate = s.fame / 100 * 0.2
      local inflow = math.floor(inflowRate * 1000)

      local churnRate = 0.1 - (s.content / 100 * 0.05) - (s.tech / 100 * 0.05)
      churnRate = math.max(0.01, churnRate)
      local churn = math.floor(s.users * churnRate)

      s.users = s.users + inflow - churn
      s.users = math.max(0, s.users)

      table.insert(s.logs, string.format("新規: %d人", inflow))
      table.insert(s.logs, string.format("離脱: %d人", churn))

      -- 知名度減衰
      local decay = math.floor(s.fame * 0.15)
      s.fame = math.max(0, s.fame - decay)
      table.insert(s.logs, string.format("知名度減衰: -%d", decay))

      -- アプリストア評価更新
      s.storeRating = math.floor((s.tech + s.content) / 2 / 20) + 1
      s.storeRating = math.min(5, s.storeRating)
    end
  end
end

-- ===== ゲームオーバー判定 =====
function checkGameOver(s)
  if s.users <= 0 and s.phase == "operation" then
    s.gameOver = true
    s.gameOverReason = "ユーザー数ゼロでサービス終了"
    return true
  end
  if s.money <= 0 then
    s.gameOver = true
    s.gameOverReason = "資金ゼロで破産"
    return true
  end
  if s.debt <= 0 then
    s.gameOver = true
    s.gameOverReason = "借金完済！おめでとうございます！"
    s.victory = true
    return true
  end
  return false
end

-- ===== LÖVE callbacks =====
function love.load()
  love.window.setTitle("ソシャゲ運営ローグライク")
  love.window.setMode(1200, 800)

  font = love.graphics.newFont(FONT_PATH, 20)
  smallFont = love.graphics.newFont(FONT_PATH, 16)
  love.graphics.setFont(font)

  state = initState()

  -- 初月のタスク生成
  generateTasks(state)
  table.insert(state.logs, "ゲーム開始")
end

function love.update(dt)
end

function love.draw()
  -- ゲームオーバー画面
  if state.gameOver then
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(font)

    if state.victory then
      love.graphics.setColor(1, 1, 0)
      boldPrintf("VICTORY!", 300, 300, 600, "center")
    else
      love.graphics.setColor(1, 0, 0)
      boldPrintf("GAME OVER", 300, 300, 600, "center")
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(state.gameOverReason, 300, 360, 600, "center")
    love.graphics.printf(string.format("生存期間: %d ヶ月", state.month), 300, 400, 600, "center")

    love.graphics.setFont(smallFont)
    love.graphics.printf("[R] リスタート", 300, 500, 600, "center")

    return
  end

  love.graphics.setColor(1, 1, 1)

  -- 日付表示
  local dateStr = monthToDateStr(state.month)
  local weekStr = string.format("第%d週/全%d週", state.week, WEEKS_PER_MONTH)
  boldPrint(dateStr .. " " .. weekStr, 20, 20)

  -- フェーズ表示
  local phaseStr = state.phase == "dev" and "開発期" or "運営期"
  love.graphics.print("【" .. phaseStr .. "】", 300, 20)

  -- 基本情報（左側）
  local y = 60
  love.graphics.print(string.format("ユーザー: %d人", state.users), 20, y)
  y = y + 30
  love.graphics.print(string.format("資金: %d万", state.money), 20, y)
  y = y + 30
  love.graphics.print(string.format("借金: %d万", state.debt), 20, y)
  y = y + 40

  -- メインステータス
  love.graphics.print(string.format("技術力: %d", state.tech), 20, y)
  y = y + 30
  love.graphics.print(string.format("知名度: %d", state.fame), 20, y)
  y = y + 30
  love.graphics.print(string.format("コンテンツ力: %d", state.content), 20, y)
  y = y + 40

  -- 派生指標
  local stars = string.rep("★", state.storeRating) .. string.rep("☆", 5 - state.storeRating)
  love.graphics.print(string.format("ストア: %s", stars), 20, y)
  y = y + 30
  if state.phase == "operation" then
    love.graphics.print(string.format("セルラン: %d位", state.salesRank), 20, y)
  end

  -- タスク一覧表示（右側）
  love.graphics.setFont(smallFont)
  local taskX = 650
  local taskY = 60
  love.graphics.setColor(1, 1, 1)
  love.graphics.print(string.format("【発生中タスク】 (%d件)", #state.tasks), taskX, 20)

  for i, taskEntry in ipairs(state.tasks) do
    if taskY > 550 then break end  -- 画面外は表示しない

    local task = taskEntry.task
    local deterioration = taskEntry.deterioration
    local taskType = taskEntry.type

    -- タスク種別で色分け
    if taskType == "negative" then
      if deterioration >= 3 then
        love.graphics.setColor(1, 0, 0)  -- 赤（緊急）
      elseif deterioration >= 1 then
        love.graphics.setColor(1, 1, 0)  -- 黄（重要）
      else
        love.graphics.setColor(1, 0.7, 0)  -- オレンジ
      end
    else
      love.graphics.setColor(0, 1, 0)  -- 緑（ポジティブ）
    end

    -- タスク名と悪化度表示
    local prefix = ""
    if state.mode == "task_select" then
      prefix = string.format("%d. ", i)
    else
      prefix = "・"
    end

    if taskType == "negative" then
      love.graphics.print(string.format("%s%s [悪化%d]", prefix, task.name, deterioration), taskX, taskY)
    else
      love.graphics.print(string.format("%s%s [今月のみ]", prefix, task.name), taskX, taskY)
    end

    taskY = taskY + 22
  end

  -- 習得スキル表示
  love.graphics.setFont(smallFont)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("【習得スキル】", 20, 550)

  local skillY = 575
  local skillIndex = 0
  for skillId, _ in pairs(state.unlockedSkills) do
    local skill = findSkill(skillId)
    if skill then
      skillIndex = skillIndex + 1
      local categoryMark = ""
      if skill.category == "tech" then
        categoryMark = "[技]"
      elseif skill.category == "fame" then
        categoryMark = "[知]"
      elseif skill.category == "content" then
        categoryMark = "[コ]"
      elseif skill.category == "response" then
        categoryMark = "[対]"
      end
      love.graphics.print(string.format("%d. %s %s (%d万)", skillIndex, categoryMark, skill.name, skill.cost), 30, skillY)
      skillY = skillY + 20
      if skillY > 620 then break end  -- 最大3行
    end
  end

  -- 操作説明
  love.graphics.setFont(font)
  love.graphics.setColor(1, 1, 1)
  if state.mode == "main" then
    love.graphics.print("[Space] 休養  [S] スキル使用", 20, 630)
  elseif state.mode == "skill_select" then
    love.graphics.print("[1-9] スキル選択  [ESC] キャンセル", 20, 630)
  elseif state.mode == "task_select" then
    local skill = findSkill(state.selectedSkill)
    if skill then
      love.graphics.print(string.format("スキル: %s", skill.name), 20, 630)
      love.graphics.print("[1-9] 対応タスク選択  [0] 対応せず使用  [ESC] キャンセル", 20, 655)
    end
  end

  -- ログ表示（下部）
  love.graphics.setFont(smallFont)
  love.graphics.setColor(0.7, 0.7, 0.7)
  local logY = 700
  local logStart = math.max(1, #state.logs - 5)
  for i = logStart, #state.logs do
    love.graphics.print(state.logs[i], 20, logY)
    logY = logY + 18
  end
end

function love.keypressed(key)
  -- ゲームオーバー時は入力を受け付けない
  if state.gameOver then
    if key == "r" then
      -- リスタート
      state = initState()
      generateTasks(state)
      table.insert(state.logs, "ゲーム開始")
    end
    return
  end

  if state.mode == "main" then
    if key == "space" then
      -- 休養
      state.tech = math.min(MAX_STAT, state.tech + 5)
      state.fame = math.min(MAX_STAT, state.fame + 5)
      state.content = math.min(MAX_STAT, state.content + 5)

      table.insert(state.logs, "休養: 全ステータス+5")

      -- スキル習得チェック
      checkSkillUnlocks(state)

      advanceWeek(state)
      checkGameOver(state)
    elseif key == "s" then
      -- スキル選択モードへ
      state.mode = "skill_select"
    end
  elseif state.mode == "skill_select" then
    if key == "escape" then
      -- メインモードに戻る
      state.mode = "main"
      state.selectedSkill = nil
    else
      -- 数字キーでスキル選択
      local num = tonumber(key)
      if num then
        local skillIndex = 0
        for skillId, _ in pairs(state.unlockedSkills) do
          skillIndex = skillIndex + 1
          if skillIndex == num then
            state.selectedSkill = skillId
            state.mode = "task_select"
            return
          end
        end
      end
    end
  elseif state.mode == "task_select" then
    if key == "escape" then
      -- スキル選択モードに戻る
      state.mode = "skill_select"
      state.selectedSkill = nil
    elseif key == "0" then
      -- タスクに使用せず、ステータス上昇のみ
      useSkill(state, state.selectedSkill, nil)
      checkSkillUnlocks(state)
      advanceWeek(state)
      checkGameOver(state)
      state.mode = "main"
      state.selectedSkill = nil
    else
      -- 数字キーでタスク選択
      local num = tonumber(key)
      if num and num >= 1 and num <= #state.tasks then
        useSkill(state, state.selectedSkill, num)
        checkSkillUnlocks(state)
        advanceWeek(state)
        checkGameOver(state)
        state.mode = "main"
        state.selectedSkill = nil
      end
    end
  end
end
