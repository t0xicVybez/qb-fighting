local QBCore = exports['qb-core']:GetCoreObject()

local activeBets = {}
local bettingPools = {}

-- Core betting functions
local function InitializeBettingPool(matchId)
    if bettingPools[matchId] then return false end
    
    bettingPools[matchId] = {
        totalPool = 0,
        fighter1Pool = 0,
        fighter2Pool = 0,
        bets = {},
        status = "open"
    }
    return true
end

local function ProcessBet(source, matchId, fighterLicense, amount)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false, "Player not found" end
    
    if not bettingPools[matchId] or bettingPools[matchId].status ~= "open" then
        return false, "Betting is not available for this match"
    end
    
    -- Validate bet amount
    if amount < Config.BettingSystem.MinBet then
        return false, "Minimum bet is $" .. Config.BettingSystem.MinBet
    end
    if amount > Config.BettingSystem.MaxBet then
        return false, "Maximum bet is $" .. Config.BettingSystem.MaxBet
    end
    
    -- Check if player has already bet
    if activeBets[source] and activeBets[source][matchId] then
        return false, "You have already placed a bet on this match"
    end
    
    -- Check if player has enough money
    if Player.PlayerData.money.cash < amount then
        return false, "Insufficient funds"
    end
    
    -- Record bet
    local betId = MySQL.insert.await('INSERT INTO fighting_bets (match_id, player_id, bet_amount, fighter_id) VALUES (?, ?, ?, ?)',
        {matchId, Player.PlayerData.license, amount, fighterLicense})
    
    if not betId then return false, "Failed to place bet" end
    
    -- Remove money from player
    Player.Functions.RemoveMoney('cash', amount, "fight-bet")
    
    -- Update betting pool
    bettingPools[matchId].totalPool = bettingPools[matchId].totalPool + amount
    if fighterLicense == exports['qb-fighting']:GetMatchState(matchId).fighter1 then
        bettingPools[matchId].fighter1Pool = bettingPools[matchId].fighter1Pool + amount
    else
        bettingPools[matchId].fighter2Pool = bettingPools[matchId].fighter2Pool + amount
    end
    
    -- Record bet in active bets
    if not activeBets[source] then activeBets[source] = {} end
    activeBets[source][matchId] = {
        betId = betId,
        amount = amount,
        fighter = fighterLicense
    }
    
    -- Update all clients with new pool totals
    TriggerClientEvent('qb-fighting:client:updateBettingPools', -1, matchId, {
        total = bettingPools[matchId].totalPool,
        fighter1 = bettingPools[matchId].fighter1Pool,
        fighter2 = bettingPools[matchId].fighter2Pool
    })
    
    return true, "Bet placed successfully"
end

local function CalculateOdds(matchId)
    if not bettingPools[matchId] then return 1.0, 1.0 end
    
    local total = bettingPools[matchId].totalPool
    if total == 0 then return 1.0, 1.0 end
    
    local fighter1Odds = (total / (bettingPools[matchId].fighter1Pool or 1)) * (1 - Config.BettingSystem.HouseCommission)
    local fighter2Odds = (total / (bettingPools[matchId].fighter2Pool or 1)) * (1 - Config.BettingSystem.HouseCommission)
    
    return math.min(fighter1Odds, Config.BettingSystem.PayoutMultiplier.Underdog),
           math.min(fighter2Odds, Config.BettingSystem.PayoutMultiplier.Underdog)
end

local function ProcessPayouts(matchId, winnerId)
    if not bettingPools[matchId] then return false end
    
    local pool = bettingPools[matchId]
    pool.status = "closed"
    
    -- Calculate house cut
    local houseCut = math.floor(pool.totalPool * Config.BettingSystem.HouseCommission)
    local winningPool = pool.totalPool - houseCut
    
    -- Get winning pool amount
    local winnerPool = (winnerId == exports['qb-fighting']:GetMatchState(matchId).fighter1) 
        and pool.fighter1Pool or pool.fighter2Pool
    
    -- Process each bet
    for source, bets in pairs(activeBets) do
        local bet = bets[matchId]
        if bet and bet.fighter == winnerId then
            local Player = QBCore.Functions.GetPlayer(source)
            if Player then
                local shareOfPool = bet.amount / winnerPool
                local winnings = math.floor(shareOfPool * winningPool)
                
                Player.Functions.AddMoney('cash', winnings, "fight-bet-win")
                TriggerClientEvent('QBCore:Notify', source, 'You won $' .. winnings .. ' from your bet!', 'success')
                
                -- Record payout in database
                MySQL.update('UPDATE fighting_bets SET won = 1, processed = 1, payout = ? WHERE id = ?',
                    {winnings, bet.betId})
            end
        else
            -- Record loss in database
            MySQL.update('UPDATE fighting_bets SET won = 0, processed = 1 WHERE id = ?', {bet.betId})
        end
    end
    
    -- Clear betting data
    activeBets[matchId] = nil
    bettingPools[matchId] = nil
    
    -- Update match record with betting totals
    MySQL.update('UPDATE fighting_matches SET total_bets = ?, house_cut = ? WHERE id = ?',
        {pool.totalPool, houseCut, matchId})
    
    return true
end

local function GetBettingStats(matchId)
    if not bettingPools[matchId] then return nil end
    
    local fighter1Odds, fighter2Odds = CalculateOdds(matchId)
    
    return {
        totalPool = bettingPools[matchId].totalPool,
        fighter1Pool = bettingPools[matchId].fighter1Pool,
        fighter2Pool = bettingPools[matchId].fighter2Pool,
        fighter1Odds = fighter1Odds,
        fighter2Odds = fighter2Odds,
        status = bettingPools[matchId].status
    }
end

-- Export functions
exports('InitializeBettingPool', InitializeBettingPool)
exports('ProcessBet', ProcessBet)
exports('CalculateOdds', CalculateOdds)
exports('ProcessPayouts', ProcessPayouts)
exports('GetBettingStats', GetBettingStats)

-- Return functions for use in other server files
return {
    InitializeBettingPool = InitializeBettingPool,
    ProcessBet = ProcessBet,
    CalculateOdds = CalculateOdds,
    ProcessPayouts = ProcessPayouts,
    GetBettingStats = GetBettingStats
}