local QBCore = exports['qb-core']:GetCoreObject()
local activeMatches = {}
local activeBets = {}
local cooldowns = {}

-- Initialize database tables when resource starts
local function InitializeDatabase()
    for _, query in pairs(Config.DatabaseTables) do
        MySQL.query(query)
    end
end

-- Get current match state for a venue
local function GetMatchState(venueId)
    if not activeMatches[venueId] then return false end
    return {
        matchId = activeMatches[venueId].matchId,
        fighter1 = activeMatches[venueId].fighter1,
        fighter2 = activeMatches[venueId].fighter2,
        round = activeMatches[venueId].currentRound,
        status = activeMatches[venueId].status,
        scores = activeMatches[venueId].scores,
        timeRemaining = activeMatches[venueId].timeRemaining
    }
end

-- Check if player has required job
local function HasRequiredJob(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local job = Player.PlayerData.job
    return job.name == Config.BusinessSettings.RequiredJob and 
           job.grade.level >= Config.BusinessSettings.RequiredJobGrade
end

-- Start a new fight
local function StartFight(venueId, fighter1Id, fighter2Id)
    if activeMatches[venueId] then return false, "A fight is already in progress at this venue" end
    if cooldowns[venueId] and cooldowns[venueId] > os.time() then
        return false, "Venue is on cooldown"
    end

    -- Create match in database
    local result = MySQL.insert.await('INSERT INTO fighting_matches (venue_id, fighter1_id, fighter2_id, rounds) VALUES (?, ?, ?, ?)',
        {venueId, fighter1Id, fighter2Id, Config.FightSettings.MaxRounds})
    
    if not result then return false, "Failed to create match record" end

    -- Initialize match state
    activeMatches[venueId] = {
        matchId = result,
        fighter1 = fighter1Id,
        fighter2 = fighter2Id,
        currentRound = 0,
        status = "preparing", -- preparing, betting, fighting, break, finished
        scores = {
            [fighter1Id] = 0,
            [fighter2Id] = 0
        },
        knockoutCount = {
            [fighter1Id] = 0,
            [fighter2Id] = 0
        },
        timeRemaining = Config.BettingSystem.BettingTime,
        roundStartTime = 0
    }

    -- Initialize betting pool
    activeBets[result] = {
        totalPool = 0,
        bets = {}
    }

    -- Trigger match preparation
    TriggerClientEvent('qb-fighting:client:prepareFight', -1, venueId, activeMatches[venueId])
    SetTimeout(Config.BettingSystem.BettingTime * 1000, function()
        StartRound(venueId)
    end)

    return true, result
end

-- Start a new round
local function StartRound(venueId)
    local match = activeMatches[venueId]
    if not match then return false end

    match.currentRound = match.currentRound + 1
    match.status = "fighting"
    match.timeRemaining = Config.FightSettings.RoundTime
    match.roundStartTime = os.time()

    TriggerClientEvent('qb-fighting:client:startRound', -1, venueId, match.currentRound)
    
    -- Set round timer
    SetTimeout(Config.FightSettings.RoundTime * 1000, function()
        EndRound(venueId)
    end)
end

-- End current round
local function EndRound(venueId)
    local match = activeMatches[venueId]
    if not match then return false end

    if match.currentRound >= Config.FightSettings.MaxRounds then
        EndFight(venueId)
    else
        match.status = "break"
        match.timeRemaining = Config.FightSettings.BreakTime

        TriggerClientEvent('qb-fighting:client:roundBreak', -1, venueId)
        
        SetTimeout(Config.FightSettings.BreakTime * 1000, function()
            StartRound(venueId)
        end)
    end
end

-- Process win conditions and end fight
local function EndFight(venueId)
    local match = activeMatches[venueId]
    if not match then return false end

    -- Determine winner
    local winner = nil
    if match.scores[match.fighter1] > match.scores[match.fighter2] then
        winner = match.fighter1
    elseif match.scores[match.fighter2] > match.scores[match.fighter1] then
        winner = match.fighter2
    end

    -- Update match record
    MySQL.update('UPDATE fighting_matches SET winner_id = ? WHERE id = ?',
        {winner, match.matchId})

    -- Process bets
    ProcessBets(match.matchId, winner)

    -- Set venue cooldown
    cooldowns[venueId] = os.time() + Config.BusinessSettings.SetupCooldown

    -- Clean up match state
    TriggerClientEvent('qb-fighting:client:endFight', -1, venueId, {
        winner = winner,
        scores = match.scores,
        matchId = match.matchId
    })

    activeMatches[venueId] = nil
end

-- Register hit and check for knockout
local function RegisterHit(venueId, attackerId, defenderId, wasBlocked)
    local match = activeMatches[venueId]
    if not match or match.status ~= "fighting" then return false end

    if wasBlocked then
        match.scores[defenderId] = match.scores[defenderId] + Config.ScoringSystem.PointsPerBlock
    else
        match.scores[attackerId] = match.scores[attackerId] + Config.ScoringSystem.PointsPerHit
        match.knockoutCount[defenderId] = match.knockoutCount[defenderId] + 1

        -- Check for knockout
        if match.knockoutCount[defenderId] >= Config.FightSettings.KnockoutHits then
            TriggerClientEvent('qb-fighting:client:knockout', -1, venueId, defenderId)
            EndFight(venueId)
            return true
        end
    end

    TriggerClientEvent('qb-fighting:client:updateScores', -1, venueId, match.scores)
    return true
end

-- Process a new bet
local function PlaceBet(source, matchId, fighterLicense, amount)
    if not Config.BettingSystem.Enabled then return false, "Betting is disabled" end
    
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false, "Player not found" end
    
    if amount < Config.BettingSystem.MinBet or amount > Config.BettingSystem.MaxBet then
        return false, "Invalid bet amount"
    end

    -- Check if player has enough money
    if Player.PlayerData.money.cash < amount then
        return false, "Insufficient funds"
    end

    -- Record bet
    local success = MySQL.insert.await('INSERT INTO fighting_bets (match_id, player_id, bet_amount, fighter_id) VALUES (?, ?, ?, ?)',
        {matchId, Player.PlayerData.license, amount, fighterLicense})
    
    if not success then return false, "Failed to place bet" end

    -- Remove money from player
    Player.Functions.RemoveMoney('cash', amount, "fight-bet")

    -- Update betting pool
    if not activeBets[matchId] then
        activeBets[matchId] = {totalPool = 0, bets = {}}
    end
    activeBets[matchId].totalPool = activeBets[matchId].totalPool + amount
    table.insert(activeBets[matchId].bets, {
        playerId = Player.PlayerData.license,
        amount = amount,
        fighter = fighterLicense
    })

    TriggerClientEvent('qb-fighting:client:updateBettingPool', -1, matchId, activeBets[matchId].totalPool)
    return true, "Bet placed successfully"
end

-- Process bets after fight ends
local function ProcessBets(matchId, winnerId)
    if not activeBets[matchId] then return end

    local bets = activeBets[matchId].bets
    local totalPool = activeBets[matchId].totalPool
    local houseCommission = math.floor(totalPool * Config.BettingSystem.HouseCommission)
    local winningPool = totalPool - houseCommission

    -- Calculate total winning bets
    local winningBetsTotal = 0
    for _, bet in ipairs(bets) do
        if bet.fighter == winnerId then
            winningBetsTotal = winningBetsTotal + bet.amount
        end
    end

    -- Process each bet
    for _, bet in ipairs(bets) do
        local Player = QBCore.Functions.GetPlayerByLicense(bet.playerId)
        if Player then
            if bet.fighter == winnerId then
                local winShare = (bet.amount / winningBetsTotal) * winningPool
                Player.Functions.AddMoney('cash', math.floor(winShare), "fight-bet-win")
            end
        end
    end

    -- Clear betting pool
    activeBets[matchId] = nil

    -- Update match record
    MySQL.update('UPDATE fighting_matches SET total_bets = ?, prize_pool = ? WHERE id = ?',
        {totalPool, winningPool, matchId})
end

-- Event handlers
RegisterNetEvent('qb-fighting:server:startFight', function(venueId, fighter1Id, fighter2Id)
    local source = source
    if not HasRequiredJob(source) then
        TriggerClientEvent('QBCore:Notify', source, 'You do not have permission to start fights', 'error')
        return
    end
    
    local success, result = StartFight(venueId, fighter1Id, fighter2Id)
    TriggerClientEvent('QBCore:Notify', source, success and 'Fight started successfully' or result, success and 'success' or 'error')
end)

RegisterNetEvent('qb-fighting:server:registerHit', function(venueId, defenderId, wasBlocked)
    local source = source
    local match = activeMatches[venueId]
    if not match then return end
    
    if match.fighter1 == source or match.fighter2 == source then
        RegisterHit(venueId, source, defenderId, wasBlocked)
    end
end)

RegisterNetEvent('qb-fighting:server:placeBet', function(matchId, fighterLicense, amount)
    local source = source
    local success, message = PlaceBet(source, matchId, fighterLicense, amount)
    TriggerClientEvent('QBCore:Notify', source, message, success and 'success' or 'error')
end)

-- Initialize database when resource starts
AddEventHandler('onResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    InitializeDatabase()
end)

-- Exports
exports('GetMatchState', GetMatchState)
exports('HasRequiredJob', HasRequiredJob)