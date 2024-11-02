local QBCore = exports['qb-core']:GetCoreObject()

-- Database Functions
local function GetPlayerFightStats(citizenId)
    local result = MySQL.query.await([[
        SELECT 
            COUNT(CASE WHEN winner_id = ? THEN 1 END) as wins,
            COUNT(*) as total_fights,
            SUM(CASE WHEN winner_id = ? THEN prize_pool ELSE 0 END) as total_earnings
        FROM fighting_matches 
        WHERE fighter1_id = ? OR fighter2_id = ?
    ]], {citizenId, citizenId, citizenId, citizenId})
    
    if result[1] then
        return {
            wins = result[1].wins,
            totalFights = result[1].total_fights,
            winRate = result[1].total_fights > 0 and (result[1].wins / result[1].total_fights * 100) or 0,
            earnings = result[1].total_earnings or 0
        }
    end
    return { wins = 0, totalFights = 0, winRate = 0, earnings = 0 }
end

local function GetVenueStats(venueId)
    local result = MySQL.query.await([[
        SELECT 
            COUNT(*) as total_fights,
            SUM(total_bets) as total_bets,
            SUM(prize_pool) as total_prize_pool
        FROM fighting_matches 
        WHERE venue_id = ?
    ]], {venueId})
    
    if result[1] then
        return {
            totalFights = result[1].total_fights,
            totalBets = result[1].total_bets or 0,
            totalPrizePool = result[1].total_prize_pool or 0
        }
    end
    return { totalFights = 0, totalBets = 0, totalPrizePool = 0 }
end

local function GetLeaderboard(category, limit)
    limit = limit or Config.LeaderboardSettings.DisplayLimit
    local query = ""
    
    if category == "most_wins" then
        query = [[
            SELECT 
                p.charinfo->>'$.firstname' as firstname,
                p.charinfo->>'$.lastname' as lastname,
                COUNT(CASE WHEN m.winner_id = p.citizenid THEN 1 END) as wins
            FROM players p
            LEFT JOIN fighting_matches m ON (m.fighter1_id = p.citizenid OR m.fighter2_id = p.citizenid)
            GROUP BY p.citizenid
            ORDER BY wins DESC
            LIMIT ?
        ]]
    elseif category == "highest_winrate" then
        query = [[
            SELECT 
                p.charinfo->>'$.firstname' as firstname,
                p.charinfo->>'$.lastname' as lastname,
                COUNT(CASE WHEN m.winner_id = p.citizenid THEN 1 END) * 100.0 / COUNT(*) as winrate
            FROM players p
            LEFT JOIN fighting_matches m ON (m.fighter1_id = p.citizenid OR m.fighter2_id = p.citizenid)
            GROUP BY p.citizenid
            HAVING COUNT(*) >= 5
            ORDER BY winrate DESC
            LIMIT ?
        ]]
    elseif category == "highest_earnings" then
        query = [[
            SELECT 
                p.charinfo->>'$.firstname' as firstname,
                p.charinfo->>'$.lastname' as lastname,
                SUM(CASE WHEN m.winner_id = p.citizenid THEN m.prize_pool ELSE 0 END) as earnings
            FROM players p
            LEFT JOIN fighting_matches m ON (m.fighter1_id = p.citizenid OR m.fighter2_id = p.citizenid)
            GROUP BY p.citizenid
            ORDER BY earnings DESC
            LIMIT ?
        ]]
    end
    
    return MySQL.query.await(query, {limit})
end

-- Fight Management Functions
local function CalculateWinnings(matchId, winnerId)
    local result = MySQL.query.await([[
        SELECT 
            b.bet_amount,
            b.fighter_id,
            m.total_bets
        FROM fighting_bets b
        JOIN fighting_matches m ON m.id = b.match_id
        WHERE b.match_id = ? AND b.processed = 0
    ]], {matchId})
    
    if not result then return 0, 0 end
    
    local totalBets = 0
    local winningBets = 0
    local payouts = {}
    
    -- Calculate totals
    for _, bet in ipairs(result) do
        totalBets = totalBets + bet.bet_amount
        if bet.fighter_id == winnerId then
            winningBets = winningBets + bet.bet_amount
        end
    end
    
    -- Calculate house cut
    local houseCut = math.floor(totalBets * Config.BettingSystem.HouseCommission)
    local winningPool = totalBets - houseCut
    
    -- Calculate individual payouts
    if winningBets > 0 then
        for _, bet in ipairs(result) do
            if bet.fighter_id == winnerId then
                local share = bet.bet_amount / winningBets
                payouts[bet.fighter_id] = math.floor(share * winningPool)
            end
        end
    end
    
    return payouts, houseCut
end

local function ProcessMatchEnd(matchId, winnerId)
    local payouts, houseCut = CalculateWinnings(matchId, winnerId)
    
    -- Process payouts
    for playerId, amount in pairs(payouts) do
        local Player = QBCore.Functions.GetPlayerByCitizenId(playerId)
        if Player then
            Player.Functions.AddMoney('cash', amount, 'fight-winnings')
            TriggerClientEvent('QBCore:Notify', Player.PlayerData.source, 
                'You won $' .. amount .. ' from your bet!', 'success')
        end
    end
    
    -- Update match record
    MySQL.update('UPDATE fighting_matches SET winner_id = ?, processed = 1 WHERE id = ?',
        {winnerId, matchId})
    
    -- Mark bets as processed
    MySQL.update('UPDATE fighting_bets SET processed = 1 WHERE match_id = ?', {matchId})
    
    return true
end

-- Business Functions
local function IsVenueAvailable(venueId)
    if not Config.Venues[venueId] then return false end
    if activeMatches[venueId] then return false end
    if cooldowns[venueId] and cooldowns[venueId] > os.time() then return false end
    return true
end

local function GetVenueEmployees(venueId)
    local result = {}
    local qbPlayers = QBCore.Functions.GetQBPlayers()
    
    for _, player in pairs(qbPlayers) do
        if player.PlayerData.job.name == Config.BusinessSettings.RequiredJob then
            table.insert(result, {
                source = player.PlayerData.source,
                citizenid = player.PlayerData.citizenid,
                name = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname,
                grade = player.PlayerData.job.grade
            })
        end
    end
    
    return result
end

local function ValidateFightSetup(venueId, fighter1Id, fighter2Id)
    -- Check venue availability
    if not IsVenueAvailable(venueId) then
        return false, "Venue is not available"
    end
    
    -- Validate fighters
    local fighter1 = QBCore.Functions.GetPlayerByCitizenId(fighter1Id)
    local fighter2 = QBCore.Functions.GetPlayerByCitizenId(fighter2Id)
    
    if not fighter1 or not fighter2 then
        return false, "One or both fighters not found"
    end
    
    if fighter1Id == fighter2Id then
        return false, "Fighters must be different players"
    end
    
    -- Check fighter states
    local f1Coords = GetEntityCoords(GetPlayerPed(fighter1.PlayerData.source))
    local f2Coords = GetEntityCoords(GetPlayerPed(fighter2.PlayerData.source))
    local venueCoords = vector3(Config.Venues[venueId].coords.x, Config.Venues[venueId].coords.y, Config.Venues[venueId].coords.z)
    
    if #(f1Coords - venueCoords) > 20.0 or #(f2Coords - venueCoords) > 20.0 then
        return false, "Both fighters must be at the venue"
    end
    
    return true, ""
end

-- Exports
return {
    Database = {
        GetPlayerFightStats = GetPlayerFightStats,
        GetVenueStats = GetVenueStats,
        GetLeaderboard = GetLeaderboard
    },
    Fight = {
        CalculateWinnings = CalculateWinnings,
        ProcessMatchEnd = ProcessMatchEnd
    },
    Business = {
        IsVenueAvailable = IsVenueAvailable,
        GetVenueEmployees = GetVenueEmployees,
        ValidateFightSetup = ValidateFightSetup
    }
}