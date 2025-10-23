-- src/server/gameManager.server.lua
-- Entry point server: require các hệ thống, init services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("config"))

local GameManager = {}

function GameManager:Start()
    print("[GameManager] Starting", Config.GAME_NAME)
    -- Warm-up: require other server systems if cần
    -- e.g., economy, matchmaking
    -- local Economy = require(script:WaitForChild("systems"):WaitForChild("economy.server"))

    -- Example: schedule periodic tasks (cleanup, leaderboard update...)
    -- task.spawn(function() while true do task.wait(30) -- do work end end)
end

-- Auto-start if script executed
GameManager:Start()

return GameManager
