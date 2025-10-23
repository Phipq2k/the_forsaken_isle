-- DataStore Service: Production-ready wrapper với session locking, validation, backup
-- Server-side only

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("config"))

-- ============================================================================
-- MODULE
-- ============================================================================
local DataStore = {}
DataStore.__index = DataStore

-- ============================================================================
-- PRIVATE STATE
-- ============================================================================

-- Cache các DataStore instances để tránh tạo lại
local storeCache = {}

-- Session locks để tránh data corruption
local sessionLocks = {}

-- ============================================================================
-- UTILITIES
-- ============================================================================

local function sleep_ms(ms)
    task.wait(ms / 1000)
end

-- Generate unique session ID
local function generateSessionId()
    return tostring(game.JobId .. "_" .. os.time() .. "_" .. math.random(10000, 99999))
end

-- Deep copy table
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

-- Validate data structure
local function validateData(data, schema)
    if type(data) ~= "table" then
        return false, "Data must be a table"
    end
    
    -- Check _dataVersion
    if not data._dataVersion then
        return false, "Missing _dataVersion"
    end
    
    -- Basic schema validation (có thể mở rộng)
    for key, expectedType in pairs(schema or {}) do
        if data[key] ~= nil and type(data[key]) ~= expectedType then
            return false, string.format("Invalid type for %s: expected %s, got %s", 
                key, expectedType, type(data[key]))
        end
    end
    
    return true
end

-- Logging helper
local function log(level, message, context)
    if not Config.LOGGING.ENABLED then return end
    
    local prefix = string.format("[DataStore][%s]", level)
    local contextStr = context and string.format(" [%s]", context) or ""
    
    if level == "ERROR" or level == "FATAL" then
        warn(prefix .. contextStr .. " " .. message)
    elseif level == "DEBUG" and Config.LOGGING.LOG_LEVEL ~= "DEBUG" then
        return
    else
        print(prefix .. contextStr .. " " .. message)
    end
end

-- ============================================================================
-- DATASTORE INSTANCE MANAGEMENT
-- ============================================================================

local function getStore(name)
    local storeName = tostring(Config.DATASTORE.NAMESPACE .. ":" .. (name or "default"))
    
    if not storeCache[storeName] then
        storeCache[storeName] = DataStoreService:GetDataStore(storeName)
        log("DEBUG", "Created DataStore instance: " .. storeName)
    end
    
    return storeCache[storeName]
end

-- ============================================================================
-- RETRY LOGIC WITH EXPONENTIAL BACKOFF
-- ============================================================================

local function callWithRetry(fn, context)
    local maxRetries = Config.DATASTORE.MAX_RETRIES
    local baseDelay = Config.DATASTORE.BASE_DELAY_MS
    local maxDelay = Config.DATASTORE.MAX_DELAY_MS or 5000
    
    local attempt = 0
    local lastError = nil
    
    while attempt <= maxRetries do
        attempt = attempt + 1
        
        -- Timeout wrapper
        local success, result
        local timeoutThread = task.delay(Config.DATASTORE.API_CALL_TIMEOUT, function()
            success = false
            result = "Request timeout"
        end)
        
        success, result = pcall(fn)
        task.cancel(timeoutThread)
        
        if success then
            log("DEBUG", string.format("Operation succeeded on attempt %d", attempt), context)
            return true, result
        end
        
        lastError = result
        
        -- Nếu đã hết retries
        if attempt > maxRetries then
            break
        end
        
        -- Exponential backoff với jitter
        local delayMs = math.min(baseDelay * (2 ^ (attempt - 1)), maxDelay)
        local jitter = delayMs * ((math.random() * 0.5) - 0.25)
        delayMs = math.max(50, delayMs + jitter)
        
        log("WARN", string.format(
            "Attempt %d/%d failed: %s. Retrying in %dms", 
            attempt, maxRetries, tostring(result), math.floor(delayMs)
        ), context)
        
        sleep_ms(delayMs)
    end
    
    log("ERROR", string.format(
        "Operation failed after %d attempts: %s", 
        maxRetries, tostring(lastError)
    ), context)
    
    return false, lastError
end

-- ============================================================================
-- SESSION LOCKING
-- ============================================================================

function DataStore:AcquireLock(userId, sessionId)
    if not Config.DATASTORE.USE_SESSION_LOCK then
        return true
    end
    
    local lockKey = "SessionLock_" .. tostring(userId)
    local store = getStore("SessionLocks")
    
    local success, lockData = callWithRetry(function()
        return store:UpdateAsync(lockKey, function(currentLock)
            -- Nếu không có lock hoặc lock đã expire
            local now = os.time()
            if not currentLock or (now - currentLock.timestamp) > Config.DATASTORE.SESSION_LOCK_TIMEOUT then
                return {
                    sessionId = sessionId,
                    timestamp = now,
                    userId = userId,
                }
            end
            
            -- Nếu đã có lock và chưa expire
            return nil -- Không update, giữ nguyên lock cũ
        end)
    end, "AcquireLock:" .. userId)
    
    if success and lockData and lockData.sessionId == sessionId then
        sessionLocks[userId] = sessionId
        log("DEBUG", string.format("Lock acquired for user %s", userId))
        return true
    end
    
    log("WARN", string.format("Failed to acquire lock for user %s", userId))
    return false
end

function DataStore:ReleaseLock(userId, sessionId)
    if not Config.DATASTORE.USE_SESSION_LOCK then
        return true
    end
    
    local lockKey = "SessionLock_" .. tostring(userId)
    local store = getStore("SessionLocks")
    
    local success = callWithRetry(function()
        return store:UpdateAsync(lockKey, function(currentLock)
            -- Chỉ release nếu sessionId khớp
            if currentLock and currentLock.sessionId == sessionId then
                return nil -- Xóa lock
            end
            return currentLock -- Giữ nguyên nếu không phải lock của mình
        end)
    end, "ReleaseLock:" .. userId)
    
    if success then
        sessionLocks[userId] = nil
        log("DEBUG", string.format("Lock released for user %s", userId))
    end
    
    return success
end

function DataStore:HasLock(userId, sessionId)
    return sessionLocks[userId] == sessionId
end

-- ============================================================================
-- CORE OPERATIONS
-- ============================================================================

function DataStore:Get(keyName, storeName)
    assert(keyName, "keyName is required")
    
    local store = getStore(storeName)
    local context = string.format("Get:%s:%s", storeName or "default", keyName)
    
    local success, data = callWithRetry(function()
        return store:GetAsync(keyName)
    end, context)
    
    if success then
        log("DEBUG", string.format("Retrieved data for key: %s", keyName), context)
        return data
    else
        log("ERROR", string.format("Failed to get data for key: %s", keyName), context)
        return nil, data
    end
end

function DataStore:Set(keyName, value, storeName, userId, sessionId)
    assert(keyName, "keyName is required")
    assert(value, "value is required")
    
    -- Session lock check
    if userId and Config.DATASTORE.USE_SESSION_LOCK then
        if not self:HasLock(userId, sessionId) then
            log("ERROR", string.format("No valid session lock for user %s", userId))
            return false, "No valid session lock"
        end
    end
    
    -- Validate data
    local isValid, validationError = validateData(value, {
        coins = "number",
        level = "number",
        inventory = "table",
    })
    
    if not isValid then
        log("ERROR", string.format("Data validation failed: %s", validationError))
        return false, validationError
    end
    
    local store = getStore(storeName)
    local context = string.format("Set:%s:%s", storeName or "default", keyName)
    
    -- Backup current data before saving
    local backupKey = keyName .. "_backup"
    local oldData = self:Get(keyName, storeName)
    if oldData then
        self:Set(backupKey, oldData, storeName)
    end
    
    -- Deep copy để tránh reference issues
    local dataCopy = deepCopy(value)
    
    -- Add metadata
    if not dataCopy._metadata then
        dataCopy._metadata = {}
    end
    dataCopy._metadata.lastSaveAt = os.time()
    dataCopy._metadata.saveCount = (dataCopy._metadata.saveCount or 0) + 1
    
    local success, result = callWithRetry(function()
        return store:SetAsync(keyName, dataCopy)
    end, context)
    
    if success then
        log("INFO", string.format("Saved data for key: %s", keyName), context)
        return true
    else
        log("ERROR", string.format("Failed to save data for key: %s - %s", keyName, result), context)
        return false, result
    end
end

function DataStore:Update(keyName, transformFn, storeName, userId, sessionId)
    assert(keyName, "keyName is required")
    assert(transformFn, "transformFn is required")
    assert(type(transformFn) == "function", "transformFn must be a function")
    
    -- Session lock check
    if userId and Config.DATASTORE.USE_SESSION_LOCK then
        if not self:HasLock(userId, sessionId) then
            log("ERROR", string.format("No valid session lock for user %s", userId))
            return false, "No valid session lock"
        end
    end
    
    local store = getStore(storeName)
    local context = string.format("Update:%s:%s", storeName or "default", keyName)
    
    local success, updatedValue = callWithRetry(function()
        return store:UpdateAsync(keyName, function(oldData)
            -- Transform data
            local transformSuccess, newData = pcall(transformFn, oldData)
            
            if not transformSuccess then
                log("ERROR", string.format("Transform function failed: %s", newData), context)
                return nil -- Abort update
            end
            
            -- Validate new data
            if newData then
                local isValid, validationError = validateData(newData, {
                    coins = "number",
                    level = "number",
                    inventory = "table",
                })
                
                if not isValid then
                    log("ERROR", string.format("Validation failed: %s", validationError), context)
                    return nil -- Abort update
                end
                
                -- Add metadata
                if not newData._metadata then
                    newData._metadata = {}
                end
                newData._metadata.lastSaveAt = os.time()
                newData._metadata.saveCount = (newData._metadata.saveCount or 0) + 1
            end
            
            return newData
        end)
    end, context)
    
    if success then
        log("INFO", string.format("Updated data for key: %s", keyName), context)
        return true, updatedValue
    else
        log("ERROR", string.format("Failed to update data for key: %s", keyName), context)
        return false, updatedValue
    end
end

function DataStore:Remove(keyName, storeName)
    assert(keyName, "keyName is required")
    
    local store = getStore(storeName)
    local context = string.format("Remove:%s:%s", storeName or "default", keyName)
    
    local success, result = callWithRetry(function()
        return store:RemoveAsync(keyName)
    end, context)
    
    if success then
        log("INFO", string.format("Removed data for key: %s", keyName), context)
        return true
    else
        log("ERROR", string.format("Failed to remove data for key: %s", keyName), context)
        return false, result
    end
end

-- ============================================================================
-- ORDERED DATASTORE (for Leaderboards)
-- ============================================================================

function DataStore:GetOrderedStore(name)
    if not Config.DATASTORE.USE_ORDERED_DATASTORE then
        log("WARN", "OrderedDataStore is disabled in config")
        return nil
    end
    
    local storeName = tostring(Config.DATASTORE.NAMESPACE .. ":Ordered:" .. (name or "default"))
    return DataStoreService:GetOrderedDataStore(storeName)
end

-- ============================================================================
-- MOCK DATASTORE (for Testing)
-- ============================================================================

if RunService:IsStudio() and Config.TESTING.MOCK_DATASTORE then
    log("WARN", "Using MOCK DataStore - data will not persist!")
    
    local mockData = {}
    
    function DataStore:Get(keyName, storeName)
        local key = (storeName or "default") .. ":" .. keyName
        return mockData[key]
    end
    
    function DataStore:Set(keyName, value, storeName)
        local key = (storeName or "default") .. ":" .. keyName
        mockData[key] = deepCopy(value)
        return true
    end
    
    function DataStore:Update(keyName, transformFn, storeName)
        local key = (storeName or "default") .. ":" .. keyName
        local oldData = mockData[key]
        local success, newData = pcall(transformFn, oldData)
        if success and newData then
            mockData[key] = deepCopy(newData)
            return true, newData
        end
        return false, newData
    end
end

-- ============================================================================
-- INITIALIZE
-- ============================================================================

log("INFO", string.format("DataStore Service initialized (Namespace: %s)", Config.DATASTORE.NAMESPACE))

return DataStore