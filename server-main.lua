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

-- Core fight management functions
local function InitiateFight(venueId, fighter1Id, fighter2Id)
    if activeMatches[venueId] then return false, "A fight is already in progress at this venue" end
    if cooldowns[venueId] and cooldowns[venueId] > os.time() then
        return false, "Venue is on cooldown"
    end

    local matchId = MySQL.insert.await('INSERT INTO fighting_matches (venue_id, fighter1_id, fighter2_id, rounds) VALUES (?, ?, ?, ?)',
        {venueId, fighter1Id, fighter2Id, Config.FightSettings.MaxRounds})
    
    if not matchId then return false, "Failed to create match record" end

    activeMatches[venueId] = {
        matchId = matchId,
        fighter1 = fighter1Id,
        fighter2 = fighter2Id,
        currentRound = 0,
        status = "preparing",
        scores = { [fighter1Id] = 0, [fighter2Id] = 0 },
        knockoutCount = { [fighter1Id] = 0, [fighter2Id] = 0 },
        timeRemaining = Config.BettingSystem.BettingTime,
        roundStartTime = 0
    }

    activeBets[matchId] = { totalPool = 0, bets = {} }
    
    return true, matchId
end

local function StartNextRound(venueId)
    local match = activeMatches[venueId]
    if not match then return false end

    match.currentRound = match.currentRound + 1
    match.status = "fighting"
    match.timeRemaining = Config.FightSettings.RoundTime
    match.roundStartTime = os.time()
    
    return true
end

local function ProcessHit(venueId, attackerId, defenderId, wasBlocked)
    local match = activeMatches[venueId]
    if not match or match.status ~= "fighting" then return false end

    if wasBlocked then
        match.scores[defenderId] = match.scores[defenderId] + Config.ScoringSystem.PointsPerBlock
    else
        match.scores[attackerId] = match.scores[attackerId] + Config.ScoringSystem.PointsPerHit
        match.knockoutCount[defenderId] = match.knockoutCount[defenderId] + 1

        if match.knockoutCount[defenderId] >= Config.FightSettings.KnockoutHits then
            return true, "knockout"
        end
    end

    return true, "hit"
end

local function ConcludeFight(venueId, reason)
    local match = activeMatches[venueId]
    if not match then return false end

    local winner = nil
    if reason == "knockout" then
        winner = match.fighter1
    else
        winner = match.scores[match.fighter1] > match.scores[match.fighter2] and match.fighter1 or match.fighter2
    end

    MySQL.update('UPDATE fighting_matches SET winner_id = ? WHERE id = ?', {winner, match.matchId})
    
    -- Process betting payouts
    local Functions = require('server/functions.lua')
    Functions.Fight.ProcessMatchEnd(match.matchId, winner)

    -- Set cooldown
    cooldowns[venueId] = os.time() + Config.BusinessSettings.SetupCooldown

    local results = {
        winner = winner,
        scores = match.scores,
        matchId = match.matchId,
        reason = reason
    }

    activeMatches[venueId] = nil
    return true, results
end

-- Initialize database when resource starts
AddEventHandler('onResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    InitializeDatabase()
end)

-- Exports for use in other server files
exports('GetMatchState', GetMatchState)
exports('HasRequiredJob', HasRequiredJob)
exports('InitiateFight', InitiateFight)
exports('StartNextRound', StartNextRound)
exports('ProcessHit', ProcessHit)
exports('ConcludeFight', ConcludeFight)