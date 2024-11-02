Config = {}

-- Debug Mode
Config.Debug = false

-- General Settings
Config.Framework = 'qb-core'
Config.UseTarget = true -- Use qb-target for interactions
Config.MaxFightsPerVenue = 1 -- Maximum concurrent fights per venue
Config.ReviveTime = 10 -- Time in seconds before fighter is revived after knockout
Config.PreventDeathDistance = 100.0 -- Distance from ring where death is prevented

-- Fight Settings
Config.FightSettings = {
    MaxRounds = 3,
    RoundTime = 180, -- in seconds
    BreakTime = 30, -- Time between rounds in seconds
    MaxHealth = 200,
    DamageMultiplier = 1.0,
    KnockoutHits = 5, -- Hits required for knockout
    KnockoutRecoveryTime = 15, -- Time in seconds
    StaminaDrain = {
        Punch = 5,
        Block = 2,
        Dodge = 3
    }
}

-- Scoring System
Config.ScoringSystem = {
    PointsPerHit = 10,
    PointsPerKnockdown = 50,
    PointsPerBlock = 5,
    WinBonus = 100,
    DrawPoints = 50
}

-- Business Settings
Config.BusinessSettings = {
    RequiredJob = 'fighting_promoter',
    RequiredJobGrade = 1,
    SetupCooldown = 300, -- Time in seconds between fights
    BusinessCommission = 0.10, -- 10% commission on bets
}

-- Betting System
Config.BettingSystem = {
    Enabled = true,
    MinBet = 100,
    MaxBet = 10000,
    BettingTime = 120, -- Time in seconds allowed for betting
    PayoutMultiplier = {
        Favorite = 1.5,
        Underdog = 2.5
    },
    HouseCommission = 0.05 -- 5% commission on winning bets
}

-- Fight Venues
Config.Venues = {
    ['vanilla_underground'] = {
        label = "Vanilla Underground Arena",
        coords = vector4(116.78, -1290.42, 28.08, 300.0),
        ring = {
            center = vector3(116.78, -1290.42, 28.08),
            radius = 5.0,
            height = 3.0
        },
        spawnPoints = {
            fighter1 = vector4(114.78, -1288.42, 28.08, 120.0),
            fighter2 = vector4(118.78, -1292.42, 28.08, 300.0)
        },
        blip = {
            sprite = 491,
            color = 1,
            scale = 0.8,
            display = 4,
            shortRange = true
        },
        storage = vector3(113.78, -1287.42, 28.08),
        cashier = vector3(119.78, -1293.42, 28.08)
    }
}

-- Animation Settings
Config.Animations = {
    Knockout = {
        dict = "missarmenian2",
        anim = "drunk_loop",
        time = 5000
    },
    Victory = {
        dict = "anim@arena@celeb@flat@solo@no_props@",
        anim = "jump_a_player_a",
        time = 3000
    },
    Ready = {
        dict = "anim@arena@celeb@flat@solo@no_props@",
        anim = "makerain_intro_a_player_a",
        time = 2000
    }
}

-- Notification Settings
Config.NotificationSettings = {
    ShowNotifications = true,
    NotificationType = 'qb', -- 'qb' or 'custom'
    NotificationDuration = 5000
}

-- Database Tables Structure
Config.DatabaseTables = {
    fights = [[
        CREATE TABLE IF NOT EXISTS `fighting_matches` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `venue_id` varchar(50) NOT NULL,
            `fighter1_id` varchar(50) NOT NULL,
            `fighter2_id` varchar(50) NOT NULL,
            `winner_id` varchar(50) DEFAULT NULL,
            `fight_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `rounds` int(11) NOT NULL,
            `total_bets` int(11) DEFAULT 0,
            `prize_pool` int(11) DEFAULT 0,
            PRIMARY KEY (`id`)
        );
    ]],
    bets = [[
        CREATE TABLE IF NOT EXISTS `fighting_bets` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `match_id` int(11) NOT NULL,
            `player_id` varchar(50) NOT NULL,
            `bet_amount` int(11) NOT NULL,
            `fighter_id` varchar(50) NOT NULL,
            `won` tinyint(1) DEFAULT NULL,
            `processed` tinyint(1) DEFAULT 0,
            PRIMARY KEY (`id`)
        );
    ]]
}

-- Leaderboard Settings
Config.LeaderboardSettings = {
    DisplayLimit = 10, -- Number of entries to show
    Categories = {
        ['most_wins'] = 'Most Wins',
        ['highest_winrate'] = 'Best Win Rate',
        ['most_knockouts'] = 'Most Knockouts',
        ['highest_earnings'] = 'Highest Earnings'
    },
    UpdateInterval = 300 -- Update interval in seconds
}

return Config