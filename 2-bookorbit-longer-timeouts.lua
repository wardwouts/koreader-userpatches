-- Raises BookOrbit HTTP timeouts without affecting other plugins.
-- Adjust the four numbers below to taste.
local REQUEST_BLOCK  = 30    -- default 10 (socketutil.LARGE_BLOCK_TIMEOUT)
local REQUEST_TOTAL  = 180   -- default 30 (socketutil.LARGE_TOTAL_TIMEOUT)
local DOWNLOAD_BLOCK = 60    -- default 15 (socketutil.FILE_BLOCK_TIMEOUT)
local DOWNLOAD_TOTAL = 3600  -- default 60 (socketutil.FILE_TOTAL_TIMEOUT)

local logger = require("logger")
local socketutil = require("socketutil")

local function pack(...) return { n = select("#", ...), ... } end

-- Runs fn with socketutil.set_timeout temporarily widened, so the timeouts
-- bookorbit_api sets *inside* requestBlocking/downloadBlocking are raised
-- instead of overwriting ours. Only ever raises: a caller asking for less
-- than we want (opts.block_timeout) still gets at least our value.
local function withRaisedTimeouts(block, total, fn, ...)
    local saved_set_timeout = socketutil.set_timeout
    socketutil.set_timeout = function(self, b, t)
        if b and b > 0 then b = math.max(b, block) else b = block end
        if t and t > 0 then t = math.max(t, total) else t = total end
        return saved_set_timeout(self, b, t)
    end

    local r = pack(pcall(fn, ...))
    socketutil.set_timeout = saved_set_timeout -- restore before anything else

    if not r[1] then error(r[2], 0) end
    return unpack(r, 2, r.n)
end

local function install()
    local ok, BookOrbitApi = pcall(require, "bookorbit_api")
    if not ok or type(BookOrbitApi) ~= "table" then
        return false
    end
    if BookOrbitApi._bo_timeouts_patched then return true end

    local original_request  = BookOrbitApi.requestBlocking
    local original_download = BookOrbitApi.downloadBlocking

    BookOrbitApi.requestBlocking = function(self, ...)
        return withRaisedTimeouts(REQUEST_BLOCK, REQUEST_TOTAL,
            original_request, self, ...)
    end

    BookOrbitApi.downloadBlocking = function(self, ...)
        return withRaisedTimeouts(DOWNLOAD_BLOCK, DOWNLOAD_TOTAL,
            original_download, self, ...)
    end

    BookOrbitApi._bo_timeouts_patched = true
    logger.info(string.format(
        "bookorbit-timeouts: requests %ds/%ds, downloads %ds/%ds",
        REQUEST_BLOCK, REQUEST_TOTAL, DOWNLOAD_BLOCK, DOWNLOAD_TOTAL))
    return true
end

if not install() then
    -- Module not on package.path yet: patch when the plugin is instantiated.
    local ok, userpatch = pcall(require, "userpatch")
    if ok and userpatch.registerPatchPluginFunc then
        userpatch.registerPatchPluginFunc("bookorbit", function() install() end)
    else
        logger.warn("bookorbit-timeouts: bookorbit_api unavailable and no deferral hook")
    end
end
