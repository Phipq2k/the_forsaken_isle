-- Module cấu hình chung cho toàn project (ReplicatedStorage)
-- Chỉ chứa giá trị cấu hình, không logic.
local RunService = game:GetService("RunService")

local config = {}

-- ============================================================================
-- ENVIRONMENT
-- ============================================================================
config.ENVIRONMENT = {
    IS_STUDIO = RunService:IsStudio(),
    IS_PRODUCTION = not RunService:IsStudio(),
}

-- ============================================================================
-- GAME INFO
-- ============================================================================
config.GAME_NAME = "The Forsaken Isle"
config.UNIVERSE_ID = 12345678 -- TODO: Đổi thành Universe ID thật
config.PLACE_ID = game.PlaceId
config.VERSION = "1.0.0"

-- ============================================================================
-- DATASTORE
-- ============================================================================
config.DATASTORE = {
    -- Namespace cho DataStore (phải unique cho mỗi game)
    NAMESPACE = "the_forsaken_isle_v1",
    
    -- Versioning để migrate data
    DATA_VERSION = 1,
    
    -- Session locking (ngăn data bị ghi đè khi player rejoin nhanh)
    USE_SESSION_LOCK = true,
    SESSION_LOCK_TIMEOUT = 300, -- 5 phút
    
    -- Autosave
    AUTOSAVE_INTERVAL = config.ENVIRONMENT.IS_STUDIO and 30 or 60, -- Studio save nhanh hơn
    SAVE_ON_LEAVE = true,
    
    -- Retry logic
    MAX_RETRIES = 5,
    BASE_DELAY_MS = 250, -- Exponential backoff base
    MAX_DELAY_MS = 5000,
    
    -- Timeout
    API_CALL_TIMEOUT = 10, -- giây
    
    -- OrderedDataStore (cho leaderboards)
    USE_ORDERED_DATASTORE = true,
}

-- ============================================================================
-- PLAYER DATA
-- ============================================================================
config.PLAYER_DATA_DEFAULT = {
    -- Data version (để migration khi schema thay đổi)
    _dataVersion = config.DATASTORE.DATA_VERSION,
    
    -- Core game data
    coins = 0,
    gems = 0,
    level = 1,
    experience = 0,
    inventory = {},
    
    -- Settings
    settings = {
        musicVolume = 0.5,
        sfxVolume = 0.8,
        uiScale = 1.0,
    },
    
    -- Stats tracking
    stats = {
        totalPlayTime = 0,
        gamesPlayed = 0,
        lastDailyReward = 0,
    },
    
    -- Metadata (không được edit bởi player)
    _metadata = {
        createdAt = 0, -- Unix timestamp
        lastSaveAt = 0,
        lastLogin = 0,
        saveCount = 0,
    }
}

-- ============================================================================
-- GAME LIMITS
-- ============================================================================
config.LIMITS = {
    MAX_INVENTORY_SIZE = 200,
    MAX_COINS = 999999999,
    MAX_LEVEL = 100,
    MAX_PARTY_SIZE = 4,
}

-- ============================================================================
-- NETWORK (Rate limiting & Security)
-- ============================================================================
config.NETWORK = {
    -- Rate limiting cho RemoteEvents
    MAX_REQUESTS_PER_MINUTE = 60,
    MAX_REQUESTS_PER_SECOND = 5,
    
    -- Security
    KICK_ON_SPAM = true,
    KICK_ON_EXPLOIT_ATTEMPT = true,
    
    -- Timeout cho Client requests
    CLIENT_TIMEOUT = 30, -- giây
}

-- ============================================================================
-- LOGGING
-- ============================================================================
config.LOGGING = {
    ENABLED = true,
    
    -- Log levels: DEBUG, INFO, WARN, ERROR, FATAL
    LOG_LEVEL = config.ENVIRONMENT.IS_STUDIO and "DEBUG" or "INFO",
    
    -- Specific logging flags
    LOG_DATASTORE_OPERATIONS = true,
    LOG_PLAYER_JOINS = true,
    LOG_ERRORS_TO_ANALYTICS = not config.ENVIRONMENT.IS_STUDIO,
    
    -- Error tracking
    TRACK_WARNINGS = true,
}

-- ============================================================================
-- TESTING (Studio only)
-- ============================================================================
config.TESTING = {
    -- Bypass DataStore trong Studio
    MOCK_DATASTORE = false,
    
    -- Override autosave interval
    FAST_AUTOSAVE = false, -- Nếu true, save mỗi 5s
    
    -- Starting resources cho testing
    DEBUG_START_COINS = 0,
    DEBUG_START_LEVEL = 1,
    
    -- Enable/disable features
    ENABLE_DEV_COMMANDS = config.ENVIRONMENT.IS_STUDIO,
}

-- ============================================================================
-- GAME MECHANICS (Tùy game)
-- ============================================================================
config.GAMEPLAY = {
    -- Economy
    STARTING_COINS = 100,
    DAILY_REWARD_COINS = 50,
    
    -- Progression
    BASE_XP_TO_LEVEL = 100,
    XP_MULTIPLIER_PER_LEVEL = 1.5,
    
    -- Combat (ví dụ)
    BASE_HEALTH = 100,
    BASE_DAMAGE = 10,
}

-- ============================================================================
-- MONETIZATION (nếu có)
-- ============================================================================
config.MONETIZATION = {
    ENABLED = not config.ENVIRONMENT.IS_STUDIO,
    
    -- Developer Products
    DEV_PRODUCTS = {
        COINS_100 = 123456, -- Product ID
        COINS_500 = 123457,
        -- ...
    },
    
    -- Game Passes
    GAME_PASSES = {
        VIP = 123458,
        DOUBLE_XP = 123459,
    },
}

-- ============================================================================
-- UTILITIES
-- ============================================================================

-- Validate config on load (chỉ trong Studio)
if config.ENVIRONMENT.IS_STUDIO then
    assert(type(config.GAME_NAME) == "string", "GAME_NAME must be string")
    assert(type(config.DATASTORE.NAMESPACE) == "string", "NAMESPACE must be string")
    assert(config.DATASTORE.AUTOSAVE_INTERVAL > 0, "AUTOSAVE_INTERVAL must be positive")
end

-- Freeze config để prevent modifications (optional, tăng security)
if not config.ENVIRONMENT.IS_STUDIO then
    table.freeze(config)
end

return config