-- PlayerDataManager: Quản lý player data lifecycle, autosave, session management
-- Server-side only

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("config"))
local DataStore = require(script.Parent.DataStore)

-- ============================================================================
-- MODULE
-- ============================================================================
local PlayerDataManager = {}

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

-- In-memory player data cache
-- Structure: { [userId] = { data = {...}, sessionId = "...", isDirty = bool, lastSave = tick() } }
local playerDataCache = {}

-- Session IDs để track mỗi player session
local sessionIds = {}

-- Autosave thread
local autosaveThread = nil

-- Shutdown flag
local isShuttingDown = false

-- ============================================================================
-- UTILITIES
-- ============================================================================

local function log(level, message, userId)
    if not Config.LOGGING.ENABLED then return end
    
    local prefix = string.format("[PlayerDataManager][%s]", level)
    local userContext = userId and string.format(" [User:%s]", userId) or ""
    
    if level == "ERROR" or level == "FATAL" then
        warn(prefix .. userContext .. " " .. message)
    elseif level == "DEBUG" and Config.LOGGING.LOG_LEVEL ~= "DEBUG" then
        return
    else
        print(prefix .. userContext .. " " .. message)
    end
end

local function generateSessionId()
    return tostring(game.JobId .. "_" .. os.time() .. "_" .. math.random(10000, 99999))
end

local function deepCopy(original)
    if type(original) ~= "table" then
        return original
    end
    local copy = {}
    for k, v in pairs(original) do
        copy[k] = deepCopy(v)
    end
    return copy
end

-- ============================================================================
-- DATA MIGRATION
-- ============================================================================

local function migrateData(data, fromVersion, toVersion)
    log("INFO", string.format("Migrating data from v%d to v%d", fromVersion, toVersion))
    
    -- Migration logic based on version
    if fromVersion < 1 and toVersion >= 1 then
        -- Example: Add new fields for v1
        data.settings = data.settings or Config.PLAYER_DATA_DEFAULT.settings
    end
    
    -- Update version
    data._dataVersion = toVersion
    
    return data
end

local function validateAndMigrateData(data)
    if not data then
        log("DEBUG", "No existing data, using defaults")
        return deepCopy(Config.PLAYER_DATA_DEFAULT)
    end
    
    -- Check if migration needed
    local currentVersion = data._dataVersion or 0
    local targetVersion = Config.DATASTORE.DATA_VERSION
    
    if currentVersion < targetVersion then
        data = migrateData(data, currentVersion, targetVersion)
    end
    
    -- Merge with defaults (add any missing fields)
    local merged = deepCopy(Config.PLAYER_DATA_DEFAULT)
    for key, value in pairs(data) do
        merged[key] = value
    end
    
    -- Update metadata
    if not merged._metadata then
        merged._metadata = {}
    end
    merged._metadata.lastLogin = os.time()
    
    return merged
end

-- ============================================================================
-- CORE FUNCTIONS
-- ============================================================================

function PlayerDataManager:LoadPlayerData(player)
    local userId = player.UserId
    
    log("INFO", "Loading player data...", userId)
    
    -- Generate session ID
    local sessionId = generateSessionId()
    sessionIds[userId] = sessionId
    
    -- Acquire session lock
    local lockAcquired = DataStore:AcquireLock(userId, sessionId)
    if not lockAcquired then
        log("ERROR", "Failed to acquire session lock - another session may be active", userId)
        player:Kick("Unable to load your data. Please try again in a few minutes.")
        return nil
    end
    
    log("DEBUG", "Session lock acquired", userId)
    
    -- Load data from DataStore
    local key = "Player_" .. tostring(userId)
    local rawData, loadError = DataStore:Get(key, "PlayerData")
    
    if loadError then
        log("ERROR", "Failed to load data: " .. tostring(loadError), userId)
        DataStore:ReleaseLock(userId, sessionId)
        player:Kick("Failed to load your data. Please try again later.")
        return nil
    end
    
    -- Validate and migrate data
    local data = validateAndMigrateData(rawData)
    
    -- Store in cache
    playerDataCache[userId] = {
        data = data,
        sessionId = sessionId,
        isDirty = false,
        lastSave = tick(),
        player = player,
    }
    
    log("INFO", string.format("Player data loaded successfully (Level: %d, Coins: %d)", 
        data.level or 0, data.coins or 0), userId)
    
    return data
end

function PlayerDataManager:SavePlayerData(userId, force)
    local cached = playerDataCache[userId]
    
    if not cached then
        log("WARN", "No cached data to save", userId)
        return false
    end
    
    -- Skip save if not dirty (unless forced)
    if not force and not cached.isDirty then
        log("DEBUG", "Data not dirty, skipping save", userId)
        return true
    end
    
    local sessionId = cached.sessionId
    local data = cached.data
    
    log("INFO", "Saving player data...", userId)
    
    -- Validate session lock
    if not DataStore:HasLock(userId, sessionId) then
        log("ERROR", "Session lock lost, cannot save", userId)
        return false
    end
    
    -- Update metadata before save
    if not data._metadata then
        data._metadata = {}
    end
    data._metadata.lastSaveAt = os.time()
    
    -- Save to DataStore
    local key = "Player_" .. tostring(userId)
    local success, saveError = DataStore:Set(key, data, "PlayerData", userId, sessionId)
    
    if success then
        cached.isDirty = false
        cached.lastSave = tick()
        log("INFO", "Player data saved successfully", userId)
        return true
    else
        log("ERROR", "Failed to save data: " .. tostring(saveError), userId)
        return false
    end
end

function PlayerDataManager:UnloadPlayerData(userId)
    local cached = playerDataCache[userId]
    
    if not cached then
        log("WARN", "No data to unload", userId)
        return true
    end
    
    log("INFO", "Unloading player data...", userId)
    
    -- Final save
    local saveSuccess = self:SavePlayerData(userId, true)
    
    if not saveSuccess then
        log("ERROR", "Failed final save during unload", userId)
    end
    
    -- Release session lock
    local sessionId = cached.sessionId
    DataStore:ReleaseLock(userId, sessionId)
    
    -- Clear cache
    playerDataCache[userId] = nil
    sessionIds[userId] = nil
    
    log("INFO", "Player data unloaded", userId)
    
    return saveSuccess
end

-- ============================================================================
-- DATA ACCESS
-- ============================================================================

function PlayerDataManager:GetData(userId)
    local cached = playerDataCache[userId]
    if not cached then
        log("WARN", "Data not loaded for user", userId)
        return nil
    end
    
    -- Return deep copy to prevent external modifications
    return deepCopy(cached.data)
end

function PlayerDataManager:UpdateData(userId, updateFn)
    local cached = playerDataCache[userId]
    
    if not cached then
        log("ERROR", "Cannot update - data not loaded", userId)
        return false
    end
    
    -- Apply update function
    local success, result = pcall(updateFn, cached.data)
    
    if not success then
        log("ERROR", "Update function failed: " .. tostring(result), userId)
        return false
    end
    
    -- Mark as dirty
    cached.isDirty = true
    
    log("DEBUG", "Data updated", userId)
    
    return true
end

-- Convenience functions for common operations
function PlayerDataManager:AddCoins(userId, amount)
    return self:UpdateData(userId, function(data)
        data.coins = math.min(data.coins + amount, Config.LIMITS.MAX_COINS)
    end)
end

function PlayerDataManager:RemoveCoins(userId, amount)
    return self:UpdateData(userId, function(data)
        if data.coins >= amount then
            data.coins = data.coins - amount
            return true
        end
        return false
    end)
end

function PlayerDataManager:AddExperience(userId, amount)
    return self:UpdateData(userId, function(data)
        data.experience = data.experience + amount
        
        -- Level up logic
        local xpNeeded = Config.GAMEPLAY.BASE_XP_TO_LEVEL * 
                        (Config.GAMEPLAY.XP_MULTIPLIER_PER_LEVEL ^ (data.level - 1))
        
        while data.experience >= xpNeeded and data.level < Config.LIMITS.MAX_LEVEL do
            data.level = data.level + 1
            data.experience = data.experience - xpNeeded
            
            log("INFO", string.format("Player leveled up to %d!", data.level), userId)
            
            -- Recalculate for next level
            xpNeeded = Config.GAMEPLAY.BASE_XP_TO_LEVEL * 
                      (Config.GAMEPLAY.XP_MULTIPLIER_PER_LEVEL ^ (data.level - 1))
        end
    end)
end

function PlayerDataManager:GetPlayerData(player)
    return self:GetData(player.UserId)
end

function PlayerDataManager:IsDataLoaded(userId)
    return playerDataCache[userId] ~= nil
end

-- ============================================================================
-- AUTOSAVE SYSTEM
-- ============================================================================

local function runAutosave()
    while not isShuttingDown do
        local interval = Config.TESTING.FAST_AUTOSAVE and 5 or Config.DATASTORE.AUTOSAVE_INTERVAL
        task.wait(interval)
        
        if isShuttingDown then break end
        
        log("DEBUG", string.format("Running autosave (interval: %ds)...", interval))
        
        local savedCount = 0
        local failedCount = 0
        
        for userId, cached in pairs(playerDataCache) do
            -- Only save if dirty
            if cached.isDirty then
                local success = PlayerDataManager:SavePlayerData(userId, false)
                if success then
                    savedCount = savedCount + 1
                else
                    failedCount = failedCount + 1
                end
            end
        end
        
        if savedCount > 0 or failedCount > 0 then
            log("INFO", string.format("Autosave complete: %d saved, %d failed", 
                savedCount, failedCount))
        end
    end
end

function PlayerDataManager:StartAutosave()
    if autosaveThread then
        log("WARN", "Autosave already running")
        return
    end
    
    log("INFO", "Starting autosave system...")
    autosaveThread = task.spawn(runAutosave)
end

function PlayerDataManager:StopAutosave()
    log("INFO", "Stopping autosave system...")
    isShuttingDown = true
    
    if autosaveThread then
        task.cancel(autosaveThread)
        autosaveThread = nil
    end
end

-- ============================================================================
-- PLAYER LIFECYCLE HANDLERS
-- ============================================================================

local function onPlayerAdded(player)
    log("INFO", "Player joined, loading data...", player.UserId)
    
    -- Load player data
    local data = PlayerDataManager:LoadPlayerData(player)
    
    if not data then
        -- Player was kicked due to load failure
        return
    end
    
    -- TODO: Setup player UI, leaderstats, etc.
    -- Example: Create leaderstats
    local leaderstats = Instance.new("Folder")
    leaderstats.Name = "leaderstats"
    leaderstats.Parent = player
    
    local coins = Instance.new("IntValue")
    coins.Name = "Coins"
    coins.Value = data.coins
    coins.Parent = leaderstats
    
    local level = Instance.new("IntValue")
    level.Name = "Level"
    level.Value = data.level
    level.Parent = leaderstats
    
    log("INFO", "Player ready", player.UserId)
end

local function onPlayerRemoving(player)
    log("INFO", "Player leaving, saving data...", player.UserId)
    
    -- Unload and save player data
    local success = PlayerDataManager:UnloadPlayerData(player.UserId)
    
    if not success then
        log("ERROR", "Failed to save data on player leave", player.UserId)
    end
end

-- ============================================================================
-- GRACEFUL SHUTDOWN
-- ============================================================================

local function saveAllPlayers()
    log("INFO", "Saving all player data before shutdown...")
    
    local savedCount = 0
    local failedCount = 0
    
    for userId, cached in pairs(playerDataCache) do
        local success = PlayerDataManager:SavePlayerData(userId, true)
        if success then
            savedCount = savedCount + 1
        else
            failedCount = failedCount + 1
        end
    end
    
    log("INFO", string.format("Shutdown save complete: %d saved, %d failed", 
        savedCount, failedCount))
    
    return failedCount == 0
end

local function onServerShutdown()
    log("WARN", "Server shutting down...")
    
    isShuttingDown = true
    
    -- Stop autosave
    PlayerDataManager:StopAutosave()
    
    -- Save all players
    saveAllPlayers()
    
    -- Release all locks
    for userId, cached in pairs(playerDataCache) do
        DataStore:ReleaseLock(userId, cached.sessionId)
    end
    
    log("INFO", "Shutdown complete")
end

-- ============================================================================
-- INITIALIZE
-- ============================================================================

function PlayerDataManager:Initialize()
    log("INFO", "Initializing PlayerDataManager...")
    
    -- Connect player lifecycle events
    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(onPlayerRemoving)
    
    -- Handle players already in game (for testing)
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(onPlayerAdded, player)
    end
    
    -- Start autosave
    self:StartAutosave()
    
    -- Bind close handlers
    game:BindToClose(function()
        onServerShutdown()
        
        -- Give time for saves to complete
        task.wait(5)
    end)
    
    log("INFO", "PlayerDataManager initialized successfully")
end

-- ============================================================================
-- ADMIN/DEBUG COMMANDS
-- ============================================================================

if Config.TESTING.ENABLE_DEV_COMMANDS then
    function PlayerDataManager:ForceSaveAll()
        log("INFO", "[DEV] Force saving all players...")
        return saveAllPlayers()
    end
    
    function PlayerDataManager:ResetPlayerData(userId)
        log("WARN", string.format("[DEV] Resetting data for user %s", userId))
        
        local cached = playerDataCache[userId]
        if cached then
            cached.data = deepCopy(Config.PLAYER_DATA_DEFAULT)
            cached.isDirty = true
            return self:SavePlayerData(userId, true)
        end
        
        return false
    end
    
    function PlayerDataManager:GetAllLoadedPlayers()
        local list = {}
        for userId, cached in pairs(playerDataCache) do
            table.insert(list, {
                userId = userId,
                isDirty = cached.isDirty,
                lastSave = cached.lastSave,
                level = cached.data.level,
                coins = cached.data.coins,
            })
        end
        return list
    end
end

-- ============================================================================
-- EXPORT
-- ============================================================================

return PlayerDataManager