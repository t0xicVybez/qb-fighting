local QBCore = exports['qb-core']:GetCoreObject()

local businessStats = {}
local venueManagers = {}

-- Core business functions
local function InitializeBusinessStats()
    for venueId, _ in pairs(Config.Venues) do
        businessStats[venueId] = {
            totalRevenue = 0,
            totalFights = 0,
            totalBets = 0,
            commissionEarned = 0,
            lastFightTime = 0
        }
    end
end

local function UpdateBusinessStats(venueId, data)
    if not businessStats[venueId] then return false end
    
    for key, value in pairs(data) do
        if businessStats[venueId][key] ~= nil then
            businessStats[venueId][key] = businessStats[venueId][key] + value
        end
    end
    
    -- Update database
    MySQL.update.await([[
        UPDATE fighting_matches 
        SET total_revenue = ?, total_commission = ? 
        WHERE venue_id = ? 
        ORDER BY fight_date DESC 
        LIMIT 1
    ]], {
        businessStats[venueId].totalRevenue,
        businessStats[venueId].commissionEarned,
        venueId
    })
    
    return true
end

local function ProcessBusinessCommission(venueId, amount)
    if not businessStats[venueId] then return false end
    
    local commission = math.floor(amount * Config.BusinessSettings.BusinessCommission)
    businessStats[venueId].commissionEarned = businessStats[venueId].commissionEarned + commission
    
    -- Pay commission to online staff
    local onlineStaff = GetVenueStaff(venueId)
    if #onlineStaff > 0 then
        local sharePerPerson = math.floor(commission / #onlineStaff)
        for _, staffMember in ipairs(onlineStaff) do
            local Player = QBCore.Functions.GetPlayer(staffMember.source)
            if Player then
                Player.Functions.AddMoney('bank', sharePerPerson, "fight-commission")
                TriggerClientEvent('QBCore:Notify', staffMember.source, 
                    'You received $' .. sharePerPerson .. ' commission from the fight', 'success')
            end
        end
    end
    
    return true
end

local function GetVenueStaff(venueId)
    local staff = {}
    local players = QBCore.Functions.GetQBPlayers()
    
    for _, player in pairs(players) do
        if player.PlayerData.job.name == Config.BusinessSettings.RequiredJob then
            table.insert(staff, {
                source = player.PlayerData.source,
                name = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname,
                grade = player.PlayerData.job.grade.level
            })
        end
    end
    
    return staff
end

local function ValidateVenueAccess(source, venueId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    if Player.PlayerData.job.name ~= Config.BusinessSettings.RequiredJob then
        return false
    end
    
    if Player.PlayerData.job.grade.level < Config.BusinessSettings.RequiredJobGrade then
        return false
    end
    
    return true
end

local function GetBusinessStats(venueId)
    if not businessStats[venueId] then return nil end
    
    return {
        totalRevenue = businessStats[venueId].totalRevenue,
        totalFights = businessStats[venueId].totalFights,
        totalBets = businessStats[venueId].totalBets,
        commissionEarned = businessStats[venueId].commissionEarned,
        lastFightTime = businessStats[venueId].lastFightTime
    }
end

-- Initialize business stats on resource start
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    InitializeBusinessStats()
end)

-- Export functions
exports('UpdateBusinessStats', UpdateBusinessStats)
exports('ProcessBusinessCommission', ProcessBusinessCommission)
exports('GetVenueStaff', GetVenueStaff)
exports('ValidateVenueAccess', ValidateVenueAccess)
exports('GetBusinessStats', GetBusinessStats)

-- Return functions for use in other server files
return {
    UpdateBusinessStats = UpdateBusinessStats,
    ProcessBusinessCommission = ProcessBusinessCommission,
    GetVenueStaff = GetVenueStaff,
    ValidateVenueAccess = ValidateVenueAccess,
    GetBusinessStats = GetBusinessStats
}