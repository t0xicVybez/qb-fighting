local QBCore = exports['qb-core']:GetCoreObject()

-- Animation Management
local loadedAnimations = {}

local function LoadAnimationDict(dict)
    if not HasAnimDictLoaded(dict) then
        RequestAnimDict(dict)
        while not HasAnimDictLoaded(dict) do
            Wait(5)
        end
        loadedAnimations[dict] = true
    end
end

local function CleanupAnimations()
    for dict, _ in pairs(loadedAnimations) do
        RemoveAnimDict(dict)
    end
    loadedAnimations = {}
end

-- Player State Management
local function IsPlayerFighting()
    return inFight and not isKnockedOut
end

local function GetPlayerStamina()
    return GetPlayerStamina(PlayerId())
end

local function DrainPlayerStamina(amount)
    if Config.FightSettings.StaminaDrain then
        local currentStamina = GetPlayerStamina()
        local newStamina = math.max(0, currentStamina - amount)
        RestorePlayerStamina(PlayerId(), -amount)
    end
end

local function ResetPlayerState()
    local playerPed = PlayerPedId()
    ClearPedTasks(playerPed)
    SetPedInfiniteAmmoClip(playerPed, false)
    SetPedConfigFlag(playerPed, 146, false) -- Disable auto punch
    SetPedConfigFlag(playerPed, 26, false) -- Disable ragdoll
    SetPlayerInvincible(PlayerId(), false)
end

-- Combat Utilities
local function CanPlayerAttack()
    if not IsPlayerFighting() then return false end
    
    local currentStamina = GetPlayerStamina()
    return currentStamina >= Config.FightSettings.StaminaDrain.Punch and canAttack
end

local function CanPlayerBlock()
    if not IsPlayerFighting() then return false end
    
    local currentStamina = GetPlayerStamina()
    return currentStamina >= Config.FightSettings.StaminaDrain.Block
end

local function IsTargetInRange(targetPed)
    if not DoesEntityExist(targetPed) then return false end
    
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local targetCoords = GetEntityCoords(targetPed)
    local distance = #(playerCoords - targetCoords)
    
    return distance <= 2.0
end

local function GetNearestFighter()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local players = QBCore.Functions.GetPlayersFromCoords(playerCoords, 2.0)
    local nearestDistance = 2.0
    local nearestPlayer = nil
    
    for _, player in ipairs(players) do
        if player ~= PlayerId() then
            local targetPed = GetPlayerPed(player)
            if IsEntityFacingEntity(playerPed, targetPed, 90.0) then
                local distance = #(playerCoords - GetEntityCoords(targetPed))
                if distance < nearestDistance then
                    nearestDistance = distance
                    nearestPlayer = player
                end
            end
        end
    end
    
    return nearestPlayer
end

-- UI State Management
local function ShowFightHUD(show)
    SendNUIMessage({
        action = "toggleFightHUD",
        show = show,
        data = {
            stamina = GetPlayerStamina(),
            health = GetEntityHealth(PlayerPedId()),
            isBlocking = blocking
        }
    })
end

local function UpdateFightHUD()
    if not inFight then return end
    
    SendNUIMessage({
        action = "updateFightHUD",
        data = {
            stamina = GetPlayerStamina(),
            health = GetEntityHealth(PlayerPedId()),
            isBlocking = blocking,
            comboCount = comboCount
        }
    })
end

local function ShowMatchResults(results)
    SendNUIMessage({
        action = "showMatchResults",
        data = results
    })
end

-- Ring Management
local function TeleportToRingCenter(venueId)
    if not Config.Venues[venueId] then return false end
    
    local ringCenter = Config.Venues[venueId].ring.center
    SetEntityCoords(PlayerPedId(), 
        ringCenter.x, 
        ringCenter.y, 
        ringCenter.z, 
        false, false, false, false)
    return true
end

local function IsInRingSafeZone(venueId)
    if not Config.Venues[venueId] then return false end
    
    local playerCoords = GetEntityCoords(PlayerPedId())
    local ringCenter = Config.Venues[venueId].ring.center
    local safeRadius = Config.Venues[venueId].ring.radius * 1.5
    
    return #(playerCoords - ringCenter) <= safeRadius
end

-- Animation Sets
local function PlayPunchAnimation(comboLevel)
    local playerPed = PlayerPedId()
    local animDict = "melee@unarmed@streamed_core"
    local anim = "punch_" .. math.min(comboLevel, 3)
    
    LoadAnimationDict(animDict)
    TaskPlayAnim(playerPed, animDict, anim, 8.0, -8.0, -1, 0, 0, false, false, false)
end

local function PlayBlockAnimation()
    local playerPed = PlayerPedId()
    local animDict = "melee@unarmed@streamed_variations"
    local anim = "blockhigh"
    
    LoadAnimationDict(animDict)
    TaskPlayAnim(playerPed, animDict, anim, 8.0, -8.0, -1, 1, 0, false, false, false)
end

local function PlayVictoryAnimation()
    local playerPed = PlayerPedId()
    local dict = Config.Animations.Victory.dict
    local anim = Config.Animations.Victory.anim
    
    LoadAnimationDict(dict)
    TaskPlayAnim(playerPed, dict, anim, 8.0, -8.0, -1, 0, 0, false, false, false)
end

-- Effect Management
local function ApplyScreenEffect(effectName, duration)
    StartScreenEffect(effectName, 0, true)
    
    if duration then
        SetTimeout(duration, function()
            StopScreenEffect(effectName)
        end)
    end
end

local function RemoveAllScreenEffects()
    StopAllScreenEffects()
end

-- Export functions
exports('IsPlayerFighting', IsPlayerFighting)
exports('GetNearestFighter', GetNearestFighter)
exports('ShowFightHUD', ShowFightHUD)
exports('PlayPunchAnimation', PlayPunchAnimation)
exports('PlayBlockAnimation', PlayBlockAnimation)
exports('IsInRingSafeZone', IsInRingSafeZone)

-- Return function table for main client file
return {
    LoadAnimationDict = LoadAnimationDict,
    CleanupAnimations = CleanupAnimations,
    IsPlayerFighting = IsPlayerFighting,
    GetPlayerStamina = GetPlayerStamina,
    DrainPlayerStamina = DrainPlayerStamina,
    ResetPlayerState = ResetPlayerState,
    CanPlayerAttack = CanPlayerAttack,
    CanPlayerBlock = CanPlayerBlock,
    IsTargetInRange = IsTargetInRange,
    GetNearestFighter = GetNearestFighter,
    ShowFightHUD = ShowFightHUD,
    UpdateFightHUD = UpdateFightHUD,
    ShowMatchResults = ShowMatchResults,
    TeleportToRingCenter = TeleportToRingCenter,
    IsInRingSafeZone = IsInRingSafeZone,
    PlayPunchAnimation = PlayPunchAnimation,
    PlayBlockAnimation = PlayBlockAnimation,
    PlayVictoryAnimation = PlayVictoryAnimation,
    ApplyScreenEffect = ApplyScreenEffect,
    RemoveAllScreenEffects = RemoveAllScreenEffects
}