local QBCore = exports['qb-core']:GetCoreObject()
local Functions = require('client/functions.lua')

-- Fight State Events
RegisterNetEvent('qb-fighting:client:initializeFight', function(venueId, matchData)
    if currentFightData then return end -- Prevent multiple fight initializations
    
    -- Setup match data
    currentFightData = matchData
    activeVenue = venueId
    
    -- Reset player state
    Functions.ResetPlayerState()
    
    -- Notify players
    if GetPlayerServerId(PlayerId()) == matchData.fighter1 or 
       GetPlayerServerId(PlayerId()) == matchData.fighter2 then
        
        QBCore.Functions.Notify('Fight starting in 10 seconds...', 'primary', 5000)
        Functions.ShowFightHUD(true)
        
        -- Initial positioning
        local spawnPoint = matchData.fighter1 == GetPlayerServerId(PlayerId()) and 
            Config.Venues[venueId].spawnPoints.fighter1 or
            Config.Venues[venueId].spawnPoints.fighter2
            
        SetEntityCoords(PlayerPedId(), 
            spawnPoint.x, 
            spawnPoint.y, 
            spawnPoint.z, 
            false, false, false, false)
        SetEntityHeading(PlayerPedId(), spawnPoint.w)
        
        -- Play ready animation
        local dict = Config.Animations.Ready.dict
        local anim = Config.Animations.Ready.anim
        Functions.LoadAnimationDict(dict)
        TaskPlayAnim(PlayerPedId(), dict, anim, 8.0, -8.0, -1, 0, 0, false, false, false)
    end
end)

RegisterNetEvent('qb-fighting:client:startBetting', function(matchId, timeRemaining)
    if not currentFightData then return end
    
    -- Show betting UI for spectators
    if not Functions.IsPlayerFighting() then
        SendNUIMessage({
            action = "showBettingUI",
            matchId = matchId,
            timeRemaining = timeRemaining,
            fighter1 = currentFightData.fighter1,
            fighter2 = currentFightData.fighter2
        })
        SetNuiFocus(true, true)
    end
end)

RegisterNetEvent('qb-fighting:client:startRound', function(roundNumber)
    if not currentFightData then return end
    
    -- Reset round-specific states
    blocking = false
    canAttack = true
    comboCount = 0
    
    -- Update HUD
    Functions.UpdateFightHUD()
    
    -- Play round start animation for fighters
    if Functions.IsPlayerFighting() then
        QBCore.Functions.Notify('Round ' .. roundNumber .. ' - FIGHT!', 'primary', 3000)
        
        -- Reset player position if needed
        if not Functions.IsInRingSafeZone(activeVenue) then
            Functions.TeleportToRingCenter(activeVenue)
        end
    end
end)

RegisterNetEvent('qb-fighting:client:roundBreak', function(timeRemaining)
    if not currentFightData then return end
    
    if Functions.IsPlayerFighting() then
        QBCore.Functions.Notify('Round break - ' .. timeRemaining .. ' seconds', 'primary', 3000)
        
        -- Prevent movement during break
        canAttack = false
        blocking = false
        
        -- Play rest animation
        local playerPed = PlayerPedId()
        TaskStartScenarioInPlace(playerPed, "WORLD_HUMAN_STAND_MOBILE", 0, true)
    end
end)

RegisterNetEvent('qb-fighting:client:registerHit', function(attackerId, wasBlocked)
    if not currentFightData then return end
    
    local playerPed = PlayerPedId()
    local serverId = GetPlayerServerId(PlayerId())
    
    -- Handle hit effects
    if serverId == attackerId then
        -- Attacker feedback
        if wasBlocked then
            PlaySoundFrontend(-1, "Parry", "MP_GUN_SHOP_SOUNDS", true)
        else
            PlaySoundFrontend(-1, "VEHICLES_HORNS_SPORTS_CAR_1", "0", true)
            Functions.DrainPlayerStamina(Config.FightSettings.StaminaDrain.Punch)
        end
    else
        -- Defender feedback
        if wasBlocked then
            PlaySoundFrontend(-1, "Faster_Click", "RESPAWN_ONLINE_SOUNDSET", true)
            Functions.DrainPlayerStamina(Config.FightSettings.StaminaDrain.Block)
        else
            Functions.ApplyScreenEffect("damage", 500)
            SetPedToRagdollWithFall(playerPed, 1000, 1000, 1, GetEntityForwardVector(playerPed), 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        end
    end
    
    -- Update HUD
    Functions.UpdateFightHUD()
end)

RegisterNetEvent('qb-fighting:client:knockout', function(knockedOutId)
    if not currentFightData then return end
    
    if GetPlayerServerId(PlayerId()) == knockedOutId then
        isKnockedOut = true
        Functions.ApplyScreenEffect("DeathFailOut", Config.FightSettings.KnockoutRecoveryTime * 1000)
        
        -- Play knockout animation
        local dict = Config.Animations.Knockout.dict
        local anim = Config.Animations.Knockout.anim
        Functions.LoadAnimationDict(dict)
        TaskPlayAnim(PlayerPedId(), dict, anim, 8.0, -8.0, -1, 1, 0, false, false, false)
        
        -- Set recovery timer
        SetTimeout(Config.FightSettings.KnockoutRecoveryTime * 1000, function()
            isKnockedOut = false
            Functions.ResetPlayerState()
            Functions.RemoveAllScreenEffects()
        end)
    end
end)

RegisterNetEvent('qb-fighting:client:endFight', function(results)
    if not currentFightData then return end
    
    local serverId = GetPlayerServerId(PlayerId())
    local playerPed = PlayerPedId()
    
    -- Handle fight end for fighters
    if Functions.IsPlayerFighting() then
        -- Play appropriate animation
        if serverId == results.winner then
            Functions.PlayVictoryAnimation()
            QBCore.Functions.Notify('Victory!', 'success', 5000)
        else
            QBCore.Functions.Notify('Better luck next time!', 'primary', 5000)
        end
        
        -- Reset states
        Functions.ShowFightHUD(false)
        Functions.ResetPlayerState()
    end
    
    -- Show results to everyone
    Functions.ShowMatchResults(results)
    
    -- Clean up
    currentFightData = nil
    activeVenue = nil
    Functions.CleanupAnimations()
end)

-- Business Events
RegisterNetEvent('qb-fighting:client:openFightMenu', function()
    if not exports['qb-core']:GetPlayerData().job.name == Config.BusinessSettings.RequiredJob then return end
    
    SendNUIMessage({
        action = "showFightMenu",
        venues = Config.Venues
    })
    SetNuiFocus(true, true)
end)

-- NUI Callbacks
RegisterNUICallback('startFight', function(data, cb)
    if not data.venueId or not data.fighter1 or not data.fighter2 then
        cb('Invalid data')
        return
    end
    
    TriggerServerEvent('qb-fighting:server:startFight', data.venueId, data.fighter1, data.fighter2)
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('placeBet', function(data, cb)
    if not data.matchId or not data.fighterLicense or not data.amount then
        cb('Invalid bet data')
        return
    end
    
    TriggerServerEvent('qb-fighting:server:placeBet', data.matchId, data.fighterLicense, data.amount)
    cb('ok')
end)

RegisterNUICallback('closeMenu', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

-- Initialization Events
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    -- Initialize any player-specific data here
    TriggerServerEvent('qb-fighting:server:syncFightState')
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    -- Initialize resource-specific data here
    if LocalPlayer.state.isLoggedIn then
        TriggerServerEvent('qb-fighting:server:syncFightState')
    end
end)

-- Export event handlers for external use
exports('TriggerFightEvent', function(eventName, ...)
    TriggerEvent('qb-fighting:client:' .. eventName, ...)
end)