local QBCore = exports['qb-core']:GetCoreObject()
local ServerFunctions = require('server/functions.lua')

-- Fight Management Events
RegisterNetEvent('qb-fighting:server:requestFight', function(data)
    local source = source
    if not exports['qb-fighting']:HasRequiredJob(source) then
        TriggerClientEvent('QBCore:Notify', source, 'You do not have permission to start fights', 'error')
        return
    end
    
    -- Validate fight setup
    local isValid, message = ServerFunctions.Business.ValidateFightSetup(data.venueId, data.fighter1Id, data.fighter2Id)
    if not isValid then
        TriggerClientEvent('QBCore:Notify', source, message, 'error')
        return
    end
    
    -- Initialize the fight
    local success, result = exports['qb-fighting']:InitiateFight(data.venueId, data.fighter1Id, data.fighter2Id)
    if not success then
        TriggerClientEvent('QBCore:Notify', source, result, 'error')
        return
    end
    
    -- Notify all players and start fight sequence
    TriggerClientEvent('qb-fighting:client:prepareFight', -1, data.venueId, {
        matchId = result,
        fighter1 = data.fighter1Id,
        fighter2 = data.fighter2Id,
        startTime = os.time() + 10 -- 10 second preparation time
    })
    
    -- Start betting period
    SetTimeout(1000, function()
        TriggerClientEvent('qb-fighting:client:startBetting', -1, result, Config.BettingSystem.BettingTime)
    end)
    
    -- Schedule fight start
    SetTimeout(Config.BettingSystem.BettingTime * 1000, function()
        TriggerEvent('qb-fighting:server:startFight', data.venueId)
    end)
end)

RegisterNetEvent('qb-fighting:server:startFight', function(venueId)
    local success = exports['qb-fighting']:StartNextRound(venueId)
    if success then
        local matchState = exports['qb-fighting']:GetMatchState(venueId)
        TriggerClientEvent('qb-fighting:client:startRound', -1, venueId, matchState.round)
        
        -- Set round timer
        SetTimeout(Config.FightSettings.RoundTime * 1000, function()
            TriggerEvent('qb-fighting:server:roundEnd', venueId)
        end)
    end
end)

RegisterNetEvent('qb-fighting:server:registerHit', function(data)
    local source = source
    local matchState = exports['qb-fighting']:GetMatchState(data.venueId)
    if not matchState then return end
    
    -- Validate hit
    if matchState.fighter1 ~= source and matchState.fighter2 ~= source then return end
    
    local success, result = exports['qb-fighting']:ProcessHit(data.venueId, source, data.defenderId, data.wasBlocked)
    if not success then return end
    
    -- Broadcast hit registration
    TriggerClientEvent('qb-fighting:client:registerHit', -1, {
        venueId = data.venueId,
        attackerId = source,
        defenderId = data.defenderId,
        wasBlocked = data.wasBlocked
    })
    
    -- Check for knockout
    if result == "knockout" then
        TriggerEvent('qb-fighting:server:endFight', data.venueId, "knockout")
    end
end)

RegisterNetEvent('qb-fighting:server:roundEnd', function(venueId)
    local matchState = exports['qb-fighting']:GetMatchState(venueId)
    if not matchState then return end
    
    if matchState.round >= Config.FightSettings.MaxRounds then
        TriggerEvent('qb-fighting:server:endFight', venueId, "decision")
    else
        TriggerClientEvent('qb-fighting:client:roundBreak', -1, venueId)
        
        -- Schedule next round
        SetTimeout(Config.FightSettings.BreakTime * 1000, function()
            TriggerEvent('qb-fighting:server:startFight', venueId)
        end)
    end
end)

RegisterNetEvent('qb-fighting:server:endFight', function(venueId, reason)
    local success, results = exports['qb-fighting']:ConcludeFight(venueId, reason)
    if success then
        TriggerClientEvent('qb-fighting:client:endFight', -1, venueId, results)
    end
end)

-- Betting System Events
RegisterNetEvent('qb-fighting:server:placeBet', function(data)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    
    local success, message = ServerFunctions.Fight.ProcessBet(source, data.matchId, data.fighterLicense, data.amount)
    TriggerClientEvent('QBCore:Notify', source, message, success and 'success' or 'error')
end)

-- Business Management Events
RegisterNetEvent('qb-fighting:server:requestVenueStats', function(venueId)
    local source = source
    if not exports['qb-fighting']:HasRequiredJob(source) then return end
    
    local stats = ServerFunctions.Database.GetVenueStats(venueId)
    TriggerClientEvent('qb-fighting:client:receiveVenueStats', source, stats)
end)

-- Leaderboard Events
RegisterNetEvent('qb-fighting:server:requestLeaderboard', function(category)
    local source = source
    local leaderboard = ServerFunctions.Database.GetLeaderboard(category)
    TriggerClientEvent('qb-fighting:client:receiveLeaderboard', source, category, leaderboard)
end)

-- State Synchronization
RegisterNetEvent('qb-fighting:server:syncFightState', function()
    local source = source
    for venueId, matchState in pairs(exports['qb-fighting']:GetAllMatchStates()) do
        TriggerClientEvent('qb-fighting:client:syncMatchState', source, venueId, matchState)
    end
end)