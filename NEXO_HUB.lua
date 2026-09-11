--[[
================================================================
  ____  _____ ____  ____   _   _
 |  _ \| ____/ ___|/ ___| / \ | |
 | |_) |  _| \___ \ \___ \/ _ \| |
 |  _ <| |___ ___) |___) / ___ \ |___
 |_| \_\_____|____/____/_/   \_\____|

  NEXO HUB v1.0.0
  universal script hub // pure monochrome
  https://nexo-bypass (your site)

---------------------------------------------------------------
  HOW TO HOST (the loadstring line)
---------------------------------------------------------------
  1) Create a GitHub repository, e.g.  YOURNAME/NEXO-HUB
  2) Upload this file as  NEXO_HUB.lua  (main branch)
  3) Your loadstring is:

loadstring(game:HttpGet("https://raw.githubusercontent.com/YOURNAME/NEXO-HUB/main/NEXO_HUB.lua"))()

  Optional - set these BEFORE the loadstring line:

  getgenv().NEXO_KEY = "your-key"        -- only needed if you enable the key system below
  getgenv().NEXO_AUTOLOAD_CONFIG = "default"

---------------------------------------------------------------
  KEY SYSTEM (disabled by default)
---------------------------------------------------------------
  Scroll to the KeySystem table below. Flip  Enabled = true
  and edit  ValidKeys / GetKeyLink / Check  when you are ready.

---------------------------------------------------------------
  GAME SUPPORT (auto-detected by PlaceId)
---------------------------------------------------------------
  Blox Fruits . Da Hood . Murder Mystery 2 . Blade Ball
  Arsenal . Pet Simulator 99 . Doors . Adopt Me
  + full universal suite in every other game

  Adding a game: copy any module at the bottom of this file,
  change the PlaceId and the cheats. That is it.
================================================================
]]

-- // anti double load
if getgenv().NEXO_LOADED and getgenv().NEXO then
    pcall(function() getgenv().NEXO.Notify("NEXO", "already loaded - toggling ui", 3) end)
    pcall(function() getgenv().NEXO.ToggleUI() end)
    return
end
getgenv().NEXO_LOADED = true

-- // services
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService      = game:GetService("HttpService")
local Lighting         = game:GetService("Lighting")
local TeleportService  = game:GetService("TeleportService")
local Stats            = game:GetService("Stats")
local GuiService       = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait()
    LocalPlayer = Players.LocalPlayer
end

-- //================================================================
-- // EXECUTOR COMPATIBILITY LAYER (works in all executors)
-- //================================================================

local NEXO = {
    Version    = "1.0.0",
    Connections = {},          -- every connection we make, cleaned on unload
    Flags       = {},          -- config registry     flag -> {Value, Set, Kind, ...}
    SearchIndex = {},          -- search registry     {page, title, row, section}
    Binds       = {},          -- keybinds            KeyCode.Value -> flag list
    Pages       = {},          -- ui pages
    NavOrder    = {},
    Modules     = {},          -- feature modules for unload cleanup
    Restore     = {},          -- original char / lighting values
    Unloaded    = false,
}
getgenv().NEXO = NEXO

-- task lib shim (ancient executors)
local unpack = unpack or table.unpack
if not task then
    task = {
        spawn = function(f, ...) local co = coroutine.wrap(f) co(...) end,
        defer = function(f, ...) local co = coroutine.wrap(f) co(...) end,
        wait  = function(t) return wait(t or 0.03) end,
        delay = function(t, f, ...) local args = {...} delay(t, function() f(unpack(args)) end) end,
    }
end
local wait = task.wait

-- table.find shim (lua 5.1 executors)
if not math.clamp then
    math.clamp = function(v, lo, hi)
        if v < lo then return lo elseif v > hi then return hi end
        return v
    end
end
local tfind = table.find or function(t, v)
    for i, x in ipairs(t) do if x == v then return i end end
    return nil
end
NEXO.tfind = tfind

local function shallowCopy(t)
    local o = {}
    for k, v in pairs(t) do o[k] = v end
    return o
end
NEXO.shallowCopy = shallowCopy

local function round(n) return math.floor(n + 0.5) end

-- // executor identity
local ExecutorName = "Unknown"
pcall(function()
    if identifyexecutor then
        ExecutorName = identifyexecutor()
    elseif getexecutorname then
        ExecutorName = getexecutorname()
    end
end)
NEXO.Executor = ExecutorName

-- // http layer - game:HttpGet / request / syn.request / http_request
local function rawRequest(url)
    local ok, body
    if syn and syn.request then
        local r = syn.request({Url = url, Method = "GET"})
        ok, body = pcall(function() return r.Body end)
    elseif http_request then
        local r = http_request({Url = url, Method = "GET"})
        ok, body = pcall(function() return r.Body end)
    elseif request then
        local r = request({Url = url, Method = "GET"})
        ok, body = pcall(function() return r.Body end)
    end
    if ok and body then return body end
    return game:HttpGet(url, true)
end
NEXO.HttpGet = function(url)
    local ok, res = pcall(function()
        if game.HttpGet then return game:HttpGet(url, true) end
        return rawRequest(url)
    end)
    if ok then return res end
    return nil
end

-- // filesystem layer
local FS = { available = false }
pcall(function()
    if writefile and readfile and isfile then
        FS.available = true
        FS.write = writefile
        FS.read  = readfile
        FS.exists = isfile
        FS.list  = listfiles or function() return {} end
        FS.makeFolder = makefolder or function() end
        FS.del = delfile or function() end
    end
end)
NEXO.FS = FS

local ROOT = "NEXO"
local CFG_DIR = "NEXO/configs"
if FS.available then
    pcall(function()
        if not FS.exists(ROOT .. "/.keep") then FS.makeFolder(ROOT) end
        FS.write(ROOT .. "/.keep", "nexo hub")
    end)
    pcall(function()
        local ok = pcall(function() return FS.list(CFG_DIR) end)
        if not ok then FS.makeFolder(CFG_DIR) end
    end)
end

-- // clipboard
NEXO.Copy = function(text)
    local ok = pcall(function()
        if setclipboard then setclipboard(text)
        elseif toclipboard then toclipboard(text)
        elseif setrbxclipboard then setrbxclipboard(text)
        else return error("noclipboard") end
    end)
    return ok
end

-- // queue on teleport (auto rejoin / keep hub after server hop)
NEXO.QueueOnTeleport = function(code)
    pcall(function()
        if queue_on_teleport then queue_on_teleport(code)
        elseif syn and syn.queue_on_teleport then syn.queue_on_teleport(code)
        elseif fluxus and fluxus.queue_on_teleport then fluxus.queue_on_teleport(code)
        end
    end)
end

-- // drawing library detect (for tracers / fov circle)
local DrawingOK = pcall(function()
    local d = Drawing.new("Square")
    d:Remove()
end)
NEXO.DrawingOK = DrawingOK

-- //================================================================
-- // KEY SYSTEM  (disabled - flip Enabled when you are ready)
-- //================================================================

local KeySystem = {
    Enabled    = false,                       -- <- set true to require a key
    Title      = "NEXO // KEY CHECK",
    Info       = "paste your key below to continue",
    GetKeyLink = "https://your-link-here.com",-- shown to the user (get key button)
    ValidKeys  = {"NEXO-TEST-1234"},          -- static keys, or leave Check below
    Attempts   = 5,
    -- custom check (optional). return true to pass.
    Check = nil, -- function(key) return true end
}
NEXO.KeySystem = KeySystem

local function runKeyGate()
    if not KeySystem.Enabled then return true end
    if getgenv().NEXO_KEY and KeySystem.Check then
        local ok, res = pcall(KeySystem.Check, getgenv().NEXO_KEY)
        if ok and res == true then return true end
    end
    if getgenv().NEXO_KEY and tfind(KeySystem.ValidKeys, getgenv().NEXO_KEY) then
        return true
    end
    -- ui gate is built later in the ui section; block here via flag
    NEXO._keyGatePending = true
    return false
end
NEXO.RunKeyGate = runKeyGate

if KeySystem.Enabled then
    runKeyGate()
end

-- //================================================================
-- // THEME - pure monochrome (black / gray / white)
-- //================================================================

local Theme = {
    Bg        = Color3.fromRGB(8, 8, 8),      -- window background
    Panel     = Color3.fromRGB(14, 14, 14),   -- sidebar / topbar
    Card      = Color3.fromRGB(20, 20, 20),   -- element rows
    CardHover = Color3.fromRGB(26, 26, 26),
    Inset     = Color3.fromRGB(10, 10, 10),   -- inputs / inner wells
    Stroke    = Color3.fromRGB(38, 38, 38),   -- 1px borders
    StrokeSoft= Color3.fromRGB(26, 26, 26),
    Text      = Color3.fromRGB(242, 242, 242),
    TextDim   = Color3.fromRGB(140, 140, 140),
    TextFaint = Color3.fromRGB(88, 88, 88),
    White     = Color3.fromRGB(255, 255, 255),
    Gray      = Color3.fromRGB(110, 110, 110),
    DarkGray  = Color3.fromRGB(60, 60, 60),
    Off       = Color3.fromRGB(45, 45, 45),   -- toggle off
    Scroller  = Color3.fromRGB(8, 8, 8),

    FTitle = Enum.Font.GothamBlack,
    FBold  = Enum.Font.GothamBold,
    FBody  = Enum.Font.Gotham,
    FMed   = Enum.Font.GothamMedium,
    FMono  = Enum.Font.Code,
}
NEXO.Theme = Theme

-- //================================================================
-- // UI HELPERS
-- //================================================================

local function Create(class, props, children)
    local inst = Instance.new(class)
    if props then
        for k, v in pairs(props) do
            if k ~= "Parent" then inst[k] = v end
        end
    end
    if children then
        for _, c in ipairs(children) do c.Parent = inst end
    end
    if props and props.Parent then inst.Parent = props.Parent end
    return inst
end
NEXO.Create = Create

local function Corner(r, parent)
    return Create("UICorner", {CornerRadius = UDim.new(0, r or 8), Parent = parent})
end
NEXO.Corner = Corner

local function Stroke(color, thickness, parent)
    return Create("UIStroke", {
        Color = color or Theme.Stroke,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
end
NEXO.Stroke = Stroke

local function Tween(obj, time, props, style, dir)
    local ti = TweenInfo.new(
        time or 0.2,
        style or Enum.EasingStyle.Quint,
        dir or Enum.EasingDirection.Out
    )
    local tw = TweenService:Create(obj, ti, props)
    tw:Play()
    return tw
end
NEXO.Tween = Tween

-- mono label styled like the website's INPUT / NEXO://RESOLVER tags
local function MonoLabel(parent, text, size, color)
    return Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Theme.FMono,
        Text = text,
        TextSize = size or 11,
        TextColor3 = color or Theme.TextFaint,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, 0, 0, size and (size + 6) or 16),
        Parent = parent,
    })
end
NEXO.MonoLabel = MonoLabel

local function fmtComma(n)
    local s = tostring(math.floor(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    out = out:gsub("^,", "")
    return out
end
NEXO.fmtComma = fmtComma

-- //================================================================
-- // NOTIFICATIONS  (bottom right stack, NEXO:// style)
-- //================================================================

NEXO.NotifyEnabled = true

local NotifyHolder
local NotifyList
local function ensureNotifyHolder()
    if NotifyHolder and NotifyHolder.Parent then return NotifyHolder, NotifyList end
    local guiParent = NEXO.GetGuiParent and NEXO.GetGuiParent() or LocalPlayer:FindFirstChildOfClass("PlayerGui")
    NotifyHolder = Create("ScreenGui", {
        Name = "NEXO_Notifications",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 9999,
        Parent = guiParent,
    })
    local holder = Create("Frame", {
        Name = "Holder",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -16, 1, -16),
        Size = UDim2.new(0, 300, 1, -32),
        BackgroundTransparency = 1,
        Parent = NotifyHolder,
    })
    Create("UIListLayout", {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        Parent = holder,
    })
    NotifyHolder = NotifyHolder
    NotifyList = holder
    return NotifyHolder, NotifyList
end

function NEXO.Notify(title, message, duration)
    if not NEXO.NotifyEnabled then return end
    duration = duration or 4
    task.spawn(function()
        local ok = pcall(function()
            local gui, list = ensureNotifyHolder()
            local card = Create("Frame", {
                BackgroundColor3 = Theme.Panel,
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                Parent = list,
            })
            Corner(8, card)
            Stroke(Theme.Stroke, 1, card)
            Create("UIPadding", {
                PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
                PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
                Parent = card,
            })
            Create("TextLabel", {
                BackgroundTransparency = 1,
                Font = Theme.FMono,
                Text = "NEXO://" .. string.upper(tostring(title or "notify")),
                TextColor3 = Theme.TextFaint,
                TextSize = 10,
                TextXAlignment = Enum.TextXAlignment.Left,
                Size = UDim2.new(1, 0, 0, 12),
                Parent = card,
            })
            Create("TextLabel", {
                BackgroundTransparency = 1,
                Font = Theme.FBold,
                Text = tostring(title or ""),
                TextColor3 = Theme.Text,
                TextSize = 14,
                TextXAlignment = Enum.TextXAlignment.Left,
                Position = UDim2.new(0, 0, 0, 14),
                Size = UDim2.new(1, 0, 0, 18),
                Parent = card,
            })
            Create("TextLabel", {
                BackgroundTransparency = 1,
                Font = Theme.FBody,
                Text = tostring(message or ""),
                TextColor3 = Theme.TextDim,
                TextSize = 12,
                TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left,
                Position = UDim2.new(0, 0, 0, 34),
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                Parent = card,
            })
            local bar = Create("Frame", {
                BackgroundColor3 = Theme.White,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 0, 1, -2),
                Size = UDim2.new(1, 0, 0, 2),
                Parent = card,
            })
            Corner(2, bar)
            -- progress bar
            Tween(bar, duration, {Size = UDim2.new(0, 0, 0, 2)})
            task.delay(duration, function()
                if card.Parent then
                    Tween(card, 0.25, {BackgroundTransparency = 1})
                    for _, d in ipairs(card:GetDescendants()) do
                        if d:IsA("TextLabel") then Tween(d, 0.25, {TextTransparency = 1}) end
                    end
                    task.wait(0.27)
                    card:Destroy()
                end
            end)
            card.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    card:Destroy()
                end
            end)
        end)
        return ok
    end)
end

-- //================================================================
-- // FPS / PING METER
-- //================================================================

local FpsMeter = { fps = 0, ping = 0, frames = 0, t = 0 }
do
    local conn = RunService.RenderStepped:Connect(function(dt)
        FpsMeter.frames = FpsMeter.frames + 1
        FpsMeter.t = FpsMeter.t + dt
        if FpsMeter.t >= 0.5 then
            FpsMeter.fps = round(FpsMeter.frames / FpsMeter.t)
            FpsMeter.frames = 0
            FpsMeter.t = 0
        end
    end)
    table.insert(NEXO.Connections, conn)
    task.spawn(function()
        while not NEXO.Unloaded do
            pcall(function() FpsMeter.ping = LocalPlayer:GetNetworkPing() * 1000 end)
            wait(2)
        end
    end)
end
NEXO.Meter = FpsMeter

-- //================================================================
-- // KEY GATE SCREEN (only shows if KeySystem.Enabled = true)
-- //================================================================

if NEXO._keyGatePending then
    NEXO._keyGatePending = false
    local gatePassed = false
    local attemptsLeft = KeySystem.Attempts or 5

    do
        local gateGui = Create("ScreenGui", {
            Name = "NEXO_KeyGate",
            ResetOnSpawn = false,
            IgnoreGuiInset = true,
            DisplayOrder = 99999,
            Parent = (function()
                local ok, p = pcall(function()
                    if gethui then return gethui() end
                    return game:GetService("CoreGui")
                end)
                if ok and p then return p end
                return LocalPlayer:FindFirstChildOfClass("PlayerGui")
            end)(),
        })
        pcall(function()
            if syn and syn.protect_gui then syn.protect_gui(gateGui) end
        end)

        local backdrop = Create("Frame", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundColor3 = Theme.Bg,
            BorderSizePixel = 0,
            Parent = gateGui,
        })

        -- // N logo
        local logo = Create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0.5, -120),
            Size = UDim2.new(0, 64, 0, 64),
            BackgroundColor3 = Theme.Bg,
            Parent = backdrop,
        })
        Corner(10, logo)
        Stroke(Theme.Stroke, 1, logo)
        do
            Create("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Parent = logo, Name = "art"})
            local art = logo.art
            Create("Frame", {BackgroundColor3 = Theme.White, BorderSizePixel = 0, Position = UDim2.new(0, 17, 0, 15), Size = UDim2.new(0, 6, 0, 34), Parent = art})
            Create("Frame", {BackgroundColor3 = Theme.White, BorderSizePixel = 0, Position = UDim2.new(0, 41, 0, 15), Size = UDim2.new(0, 6, 0, 34), Parent = art})
            local diag = Create("Frame", {BackgroundColor3 = Theme.White, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 6, 0, 46), Rotation = -40, Parent = art})
            local _ = diag
        end

        Create("TextLabel", {
            BackgroundTransparency = 1,
            Font = Theme.FMono,
            Text = "NEXO://KEYCHECK",
            TextColor3 = Theme.TextFaint,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Center,
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0.5, -44),
            Size = UDim2.new(0, 400, 0, 14),
            Parent = backdrop,
        })
        Create("TextLabel", {
            BackgroundTransparency = 1,
            Font = Theme.FTitle,
            Text = "NEXO HUB",
            TextColor3 = Theme.White,
            TextSize = 34,
            TextXAlignment = Enum.TextXAlignment.Center,
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0.5, -28),
            Size = UDim2.new(0, 400, 0, 40),
            Parent = backdrop,
        })
        Create("TextLabel", {
            BackgroundTransparency = 1,
            Font = Theme.FBody,
            Text = KeySystem.Info or "paste your key below to continue",
            TextColor3 = Theme.TextDim,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Center,
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0.5, 14),
            Size = UDim2.new(0, 400, 0, 18),
            Parent = backdrop,
        })

        -- // input panel (mirrors the website's INPUT panel)
        local panel = Create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0.5, 44),
            Size = UDim2.new(0, 560, 0, 110),
            BackgroundColor3 = Theme.Panel,
            Parent = backdrop,
        })
        Corner(10, panel)
        Stroke(Theme.Stroke, 1, panel)
        Create("UIPadding", {PaddingTop = UDim.new(0, 12), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingBottom = UDim.new(0, 12), Parent = panel})
        Create("TextLabel", {
            BackgroundTransparency = 1, Font = Theme.FMono, Text = "INPUT",
            TextColor3 = Theme.TextFaint, TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
            Size = UDim2.new(0, 200, 0, 12), Parent = panel,
        })
        Create("TextLabel", {
            BackgroundTransparency = 1, Font = Theme.FMono, Text = "NEXO://KEYCHECK",
            TextColor3 = Theme.TextFaint, TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Right,
            Size = UDim2.new(1, 0, 0, 12), Parent = panel,
        })
        local inputBox = Create("TextBox", {
            BackgroundColor3 = Theme.Inset,
            Position = UDim2.new(0, 0, 0, 22),
            Size = UDim2.new(1, -150, 0, 40),
            Font = Theme.FMono,
            Text = "",
            PlaceholderText = "paste key here",
            PlaceholderColor3 = Theme.TextFaint,
            TextColor3 = Theme.Text,
            TextSize = 13,
            ClearTextOnFocus = false,
            Parent = panel,
        })
        Corner(6, inputBox)
        Stroke(Theme.StrokeSoft, 1, inputBox)
        Create("UIPadding", {PaddingLeft = UDim.new(0, 10), Parent = inputBox})

        local continueBtn = Create("TextButton", {
            BackgroundColor3 = Theme.DarkGray,
            Position = UDim2.new(1, -136, 0, 22),
            Size = UDim2.new(0, 136, 0, 40),
            Font = Theme.FBold,
            Text = "CONTINUE  >",
            TextColor3 = Theme.White,
            TextSize = 13,
            AutoButtonColor = false,
            Parent = panel,
        })
        Corner(6, continueBtn)

        local statusLbl = Create("TextLabel", {
            BackgroundTransparency = 1, Font = Theme.FMono, Text = "attempts left: " .. tostring(attemptsLeft),
            TextColor3 = Theme.TextFaint, TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
            Position = UDim2.new(0, 0, 1, -16),
            Size = UDim2.new(0.6, 0, 0, 12), Parent = panel,
        })
        local _ = statusLbl

        local getKeyBtn = Create("TextButton", {
            BackgroundColor3 = Theme.Panel,
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0.5, 168),
            Size = UDim2.new(0, 180, 0, 34),
            Font = Theme.FMed,
            Text = "GET KEY",
            TextColor3 = Theme.TextDim,
            TextSize = 12,
            AutoButtonColor = false,
            Parent = backdrop,
        })
        Corner(6, getKeyBtn)
        Stroke(Theme.Stroke, 1, getKeyBtn)
        getKeyBtn.MouseButton1Click:Connect(function()
            NEXO.Copy(KeySystem.GetKeyLink or "")
            NEXO.Notify("Key", "link copied to clipboard", 3)
        end)

        local function fail(msg)
            attemptsLeft = attemptsLeft - 1
            statusLbl.Text = "attempts left: " .. tostring(math.max(attemptsLeft, 0))
            statusLbl.TextColor3 = Theme.Text
            if attemptsLeft <= 0 then
                LocalPlayer:Kick("NEXO // invalid key")
                return
            end
            NEXO.Notify("Key", msg or "invalid key", 3)
        end

        local function tryKey()
            local key = inputBox.Text
            if key == "" then return fail("enter a key first") end
            local passed = false
            if KeySystem.Check then
                local ok, res = pcall(KeySystem.Check, key)
                passed = ok and res == true
            else
                passed = tfind(KeySystem.ValidKeys, key) ~= nil
            end
            if passed then
                gatePassed = true
                NEXO.Notify("Key", "key accepted - loading hub", 3)
                Tween(backdrop, 0.3, {BackgroundTransparency = 1})
                task.delay(0.35, function() gateGui:Destroy() end)
            else
                fail("invalid key")
            end
        end
        continueBtn.MouseButton1Click:Connect(tryKey)
        inputBox.FocusLost:Connect(function(enter) if enter then tryKey() end end)

        while not gatePassed and not NEXO.Unloaded do
            wait(0.1)
        end
    end
end

-- //================================================================
-- // MAIN WINDOW
-- //================================================================

local function getGuiParent()
    local ok, p = pcall(function()
        if gethui then return gethui() end
        return game:GetService("CoreGui")
    end)
    if ok and p then return p end
    return LocalPlayer:FindFirstChildOfClass("PlayerGui")
end
NEXO.GetGuiParent = getGuiParent

local ScreenGui = Create("ScreenGui", {
    Name = "NEXO_HUB",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 9998,
    Parent = getGuiParent(),
})
pcall(function()
    if syn and syn.protect_gui then syn.protect_gui(ScreenGui) end
    if gethui and coregui_protect then coregui_protect(ScreenGui) end
end)
NEXO.ScreenGui = ScreenGui

local UIScaleObj = Create("UIScale", {Scale = 1, Parent = ScreenGui})
NEXO.UIScaleMult = 1
local function applyAutoScale()
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1366, 768)
    local auto = math.min(1, vp.X / 940, vp.Y / 660)
    UIScaleObj.Scale = auto * (NEXO.UIScaleMult or 1)
end
applyAutoScale()
NEXO.ApplyScale = applyAutoScale
pcall(function()
    table.insert(NEXO.Connections, workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyAutoScale))
end)

local WINDOW_W, WINDOW_H = 860, 560
local Root = Create("Frame", {
    Name = "Root",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.new(0, WINDOW_W, 0, WINDOW_H),
    BackgroundColor3 = Theme.Bg,
    BorderSizePixel = 0,
    Active = true,
    Parent = ScreenGui,
})
Corner(12, Root)
Stroke(Theme.Stroke, 1, Root)
NEXO.Root = Root

-- //------------------------------------------------
-- // TOPBAR
-- //------------------------------------------------
local Topbar = Create("Frame", {
    Name = "Topbar",
    Size = UDim2.new(1, 0, 0, 50),
    BackgroundColor3 = Theme.Panel,
    BorderSizePixel = 0,
    Parent = Root,
})
Corner(12, Topbar)
Create("Frame", { -- cover bottom rounded corners of topbar
    Name = "Cover",
    Position = UDim2.new(0, 0, 1, -14),
    Size = UDim2.new(1, 0, 0, 14),
    BackgroundColor3 = Theme.Panel,
    BorderSizePixel = 0,
    Parent = Topbar,
})
Create("Frame", { -- divider line under topbar
    Position = UDim2.new(0, 0, 1, -1),
    Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = Theme.StrokeSoft,
    BorderSizePixel = 0,
    Parent = Topbar,
})

-- // N logo (drawn with frames - matches your logo)
local LogoBox = Create("Frame", {
    Position = UDim2.new(0, 12, 0, 8),
    Size = UDim2.new(0, 34, 0, 34),
    BackgroundColor3 = Theme.Bg,
    Parent = Topbar,
})
Corner(8, LogoBox)
Stroke(Theme.Stroke, 1, LogoBox)
do
    local art = Create("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Parent = LogoBox, Name = "Art"})
    Create("Frame", {BackgroundColor3 = Theme.White, BorderSizePixel = 0, Position = UDim2.new(0, 9, 0, 8), Size = UDim2.new(0, 3, 0, 18), Parent = art})
    Create("Frame", {BackgroundColor3 = Theme.White, BorderSizePixel = 0, Position = UDim2.new(0, 22, 0, 8), Size = UDim2.new(0, 3, 0, 18), Parent = art})
    Create("Frame", {
        BackgroundColor3 = Theme.White, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 3, 0, 25),
        Rotation = -42,
        Parent = art,
    })
end

Create("TextLabel", {
    BackgroundTransparency = 1,
    Font = Theme.FTitle,
    Text = "NEXO",
    TextColor3 = Theme.White,
    TextSize = 19,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.new(0, 56, 0, 0),
    Size = UDim2.new(0, 90, 1, 0),
    Parent = Topbar,
})
Create("TextLabel", {
    BackgroundTransparency = 1,
    Font = Theme.FMono,
    Text = "H U B",
    TextColor3 = Theme.TextFaint,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.new(0, 132, 0, 0),
    Size = UDim2.new(0, 60, 1, -6),
    Parent = Topbar,
})

-- // game badge (right side)
local GameBadge = Create("TextLabel", {
    BackgroundColor3 = Theme.Inset,
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -130, 0.5, 0),
    Size = UDim2.new(0, 220, 0, 28),
    Font = Theme.FMono,
    Text = "GAME://SCANNING",
    TextColor3 = Theme.TextDim,
    TextSize = 11,
    Parent = Topbar,
})
Corner(6, GameBadge)
Stroke(Theme.StrokeSoft, 1, GameBadge)
function NEXO.SetGameBadge(text, active)
    GameBadge.Text = "GAME://" .. string.upper(text)
    GameBadge.TextColor3 = active and Theme.White or Theme.TextDim
end

-- // window buttons
local function WinButton(x, glyph, callback)
    local b = Create("TextButton", {
        BackgroundColor3 = Theme.Panel,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, x, 0, 10),
        Size = UDim2.new(0, 30, 0, 30),
        Font = Theme.FMono,
        Text = glyph,
        TextColor3 = Theme.TextDim,
        TextSize = 14,
        AutoButtonColor = false,
        Parent = Topbar,
    })
    Corner(6, b)
    b.MouseEnter:Connect(function() b.BackgroundColor3 = Theme.Card b.TextColor3 = Theme.White end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = Theme.Panel b.TextColor3 = Theme.TextDim end)
    b.MouseButton1Click:Connect(callback)
    return b
end

-- // minimize pill (shown when minimized)
local MinPill = Create("TextButton", {
    Visible = false,
    BackgroundColor3 = Theme.Panel,
    AnchorPoint = Vector2.new(0, 0),
    Position = UDim2.new(0, 12, 0, 12),
    Size = UDim2.new(0, 118, 0, 38),
    Font = Theme.FBold,
    Text = "  NEXO",
    TextColor3 = Theme.White,
    TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
    AutoButtonColor = false,
    Parent = ScreenGui,
})
Corner(8, MinPill)
Stroke(Theme.Stroke, 1, MinPill)
do
    local dot = Create("Frame", {
        BackgroundColor3 = Theme.White,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 10, 0.5, -7),
        Size = UDim2.new(0, 14, 0, 14),
        Parent = MinPill,
    })
    Corner(4, dot)
end
MinPill.MouseButton1Click:Connect(function()
    Root.Visible = true
    MinPill.Visible = false
end)

WinButton(-14, "X", function() NEXO.Unload() end)
WinButton(-50, "-", function()
    Root.Visible = false
    MinPill.Visible = true
end)

-- //------------------------------------------------
-- // DRAGGING
-- //------------------------------------------------
do
    local dragging, dragStart, startPos
    Topbar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = Root.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    table.insert(NEXO.Connections, UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            Root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end))
end

-- //------------------------------------------------
-- // SIDEBAR + NAVIGATION
-- //------------------------------------------------
local Sidebar = Create("Frame", {
    Name = "Sidebar",
    Position = UDim2.new(0, 0, 0, 50),
    Size = UDim2.new(0, 196, 1, -50 - 26),
    BackgroundColor3 = Theme.Panel,
    BorderSizePixel = 0,
    Parent = Root,
})
Create("Frame", {
    Position = UDim2.new(1, -1, 0, 0),
    Size = UDim2.new(0, 1, 1, 0),
    BackgroundColor3 = Theme.StrokeSoft,
    BorderSizePixel = 0,
    Parent = Sidebar,
})

local NavScroll = Create("ScrollingFrame", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 8, 0, 8),
    Size = UDim2.new(1, -16, 1, -16),
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollBarThickness = 2,
    ScrollBarImageColor3 = Theme.DarkGray,
    BorderSizePixel = 0,
    Parent = Sidebar,
})
Create("UIListLayout", {Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = NavScroll})

local NavLayoutOrder = 0
local function AddNavGroup(label)
    NavLayoutOrder = NavLayoutOrder + 1
    local g = Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Theme.FMono,
        Text = "// " .. string.upper(label),
        TextColor3 = Theme.TextFaint,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, 0, 0, 22),
        LayoutOrder = NavLayoutOrder,
        Parent = NavScroll,
    })
    local _ = g
end
NEXO.AddNavGroup = AddNavGroup

-- //------------------------------------------------
-- // CONTENT AREA
-- //------------------------------------------------
local Content = Create("Frame", {
    Name = "Content",
    Position = UDim2.new(0, 196, 0, 50),
    Size = UDim2.new(1, -196, 1, -50 - 26),
    BackgroundTransparency = 1,
    Parent = Root,
})

local Header = Create("Frame", {
    Size = UDim2.new(1, 0, 0, 62),
    BackgroundTransparency = 1,
    Parent = Content,
})
local PageTitle = Create("TextLabel", {
    BackgroundTransparency = 1,
    Font = Theme.FTitle,
    Text = "HOME",
    TextColor3 = Theme.White,
    TextSize = 22,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.new(0, 18, 0, 12),
    Size = UDim2.new(0.5, 0, 0, 26),
    Parent = Header,
})
local PageSub = Create("TextLabel", {
    BackgroundTransparency = 1,
    Font = Theme.FMono,
    Text = "nexo://universal",
    TextColor3 = Theme.TextFaint,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.new(0, 18, 0, 40),
    Size = UDim2.new(0.5, 0, 0, 14),
    Parent = Header,
})

local SearchBox = Create("TextBox", {
    BackgroundColor3 = Theme.Inset,
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -18, 0, 16),
    Size = UDim2.new(0, 230, 0, 32),
    Font = Theme.FMono,
    Text = "",
    PlaceholderText = "search cheats...",
    PlaceholderColor3 = Theme.TextFaint,
    TextColor3 = Theme.Text,
    TextSize = 12,
    ClearTextOnFocus = false,
    Parent = Header,
})
Corner(8, SearchBox)
Stroke(Theme.StrokeSoft, 1, SearchBox)
Create("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = SearchBox})
SearchBox.Focused:Connect(function() SearchBox.TextColor3 = Theme.White end)
SearchBox.FocusLost:Connect(function() SearchBox.TextColor3 = Theme.Text end)

-- // page host
local PageHost = Create("Frame", {
    Position = UDim2.new(0, 0, 0, 62),
    Size = UDim2.new(1, 0, 1, -62),
    BackgroundTransparency = 1,
    Parent = Content,
})

-- //------------------------------------------------
-- // STATUSBAR
-- //------------------------------------------------
local Statusbar = Create("Frame", {
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 0, 1, 0),
    Size = UDim2.new(1, 0, 0, 26),
    BackgroundColor3 = Theme.Panel,
    BorderSizePixel = 0,
    Parent = Root,
})
Corner(12, Statusbar)
Create("Frame", {
    Size = UDim2.new(1, 0, 0, 14),
    BackgroundColor3 = Theme.Panel,
    BorderSizePixel = 0,
    Parent = Statusbar,
})
Create("Frame", {
    Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = Theme.StrokeSoft,
    BorderSizePixel = 0,
    Parent = Statusbar,
})
local StatusLeft = Create("TextLabel", {
    BackgroundTransparency = 1,
    Font = Theme.FMono,
    Text = "nexo // ready",
    TextColor3 = Theme.TextFaint,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.new(0, 14, 0, 0),
    Size = UDim2.new(0.6, 0, 1, 0),
    Parent = Statusbar,
})
local StatusRight = Create("TextLabel", {
    BackgroundTransparency = 1,
    Font = Theme.FMono,
    Text = "v" .. NEXO.Version .. " | " .. ExecutorName,
    TextColor3 = Theme.TextFaint,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Right,
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -14, 0, 0),
    Size = UDim2.new(0.4, 0, 1, 0),
    Parent = Statusbar,
})
NEXO.SetStatus = function(text) StatusLeft.Text = "nexo // " .. text end

task.spawn(function()
    while not NEXO.Unloaded do
        pcall(function()
            StatusRight.Text = string.format(
                "v%s | %s | %dfps | %dms",
                NEXO.Version, ExecutorName, NEXO.Meter.fps, NEXO.Meter.ping
            )
        end)
        wait(0.5)
    end
end)

-- //------------------------------------------------
-- // WATERMARK
-- //------------------------------------------------
local Watermark = Create("Frame", {
    Visible = false,
    BackgroundColor3 = Theme.Panel,
    Position = UDim2.new(0, 12, 0, 12),
    Size = UDim2.new(0, 210, 0, 30),
    BackgroundTransparency = 0.15,
    Parent = ScreenGui,
})
Corner(8, Watermark)
Stroke(Theme.Stroke, 1, Watermark)
local WatermarkText = Create("TextLabel", {
    BackgroundTransparency = 1,
    Font = Theme.FMono,
    Text = "NEXO // " .. ExecutorName .. " | 60fps",
    TextColor3 = Theme.TextDim,
    TextSize = 11,
    Size = UDim2.new(1, -24, 1, 0),
    Position = UDim2.new(0, 12, 0, 0),
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = Watermark,
})
task.spawn(function()
    while not NEXO.Unloaded do
        pcall(function()
            WatermarkText.Text = string.format("NEXO // %s | %dfps | %dms", ExecutorName, NEXO.Meter.fps, NEXO.Meter.ping)
        end)
        wait(0.5)
    end
end)
function NEXO.SetWatermark(on)
    Watermark.Visible = on and true or false
end

-- //------------------------------------------------
-- // PAGE SYSTEM
-- //------------------------------------------------
NEXO.CurrentPage = nil

function NEXO.RegisterPage(id, label, subtitle)
    -- nav button
    NavLayoutOrder = NavLayoutOrder + 1
    local btn = Create("TextButton", {
        BackgroundColor3 = Theme.Panel,
        Size = UDim2.new(1, 0, 0, 32),
        Font = Theme.FMono,
        Text = "",
        TextColor3 = Theme.TextDim,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        AutoButtonColor = false,
        LayoutOrder = NavLayoutOrder,
        Parent = NavScroll,
    })
    Corner(6, btn)
    local pad = Create("UIPadding", {PaddingLeft = UDim.new(0, 12), Parent = btn})
    local lbl = Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Theme.FMono,
        Text = string.upper(label),
        TextColor3 = Theme.TextDim,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, 0, 1, 0),
        Parent = btn,
    })
    local bar = Create("Frame", {
        Visible = false,
        BackgroundColor3 = Theme.White,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0.5, -9),
        Size = UDim2.new(0, 3, 0, 18),
        Parent = btn,
    })
    Corner(2, bar)

    -- page frame + scroller
    local pageFrame = Create("ScrollingFrame", {
        Visible = false,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Theme.DarkGray,
        BorderSizePixel = 0,
        Parent = PageHost,
    })
    Create("UIPadding", {
        PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 16),
        PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18),
        Parent = pageFrame,
    })
    Create("UIListLayout", {Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder, Parent = pageFrame})

    local page = {
        Id = id,
        Label = label,
        Subtitle = subtitle or ("nexo://" .. id),
        Frame = pageFrame,
        NavButton = btn,
        NavLabel = lbl,
        NavBar = bar,
        NavPad = pad,
        LayoutOrder = NavLayoutOrder,
    }
    NEXO.Pages[id] = page

    btn.MouseButton1Click:Connect(function()
        if NEXO.ShowPage then NEXO.ShowPage(id) end
    end)
    btn.MouseEnter:Connect(function()
        if NEXO.CurrentPage ~= id then lbl.TextColor3 = Theme.Text end
    end)
    btn.MouseLeave:Connect(function()
        if NEXO.CurrentPage ~= id then lbl.TextColor3 = Theme.TextDim end
    end)
    return page
end

function NEXO.ShowPage(id)
    local page = NEXO.Pages[id]
    if not page then return end
    NEXO.CurrentPage = id
    for _, p in pairs(NEXO.Pages) do
        local active = (p.Id == id)
        p.Frame.Visible = active
        p.NavButton.BackgroundColor3 = active and Theme.Card or Theme.Panel
        p.NavLabel.TextColor3 = active and Theme.White or Theme.TextDim
        p.NavBar.Visible = active
    end
    PageTitle.Text = string.upper(page.Label)
    PageSub.Text = page.Subtitle
    NEXO.ApplySearch(SearchBox.Text)
end

function NEXO.ToggleUI()
    if Root.Visible then
        Root.Visible = false
        MinPill.Visible = true
    else
        Root.Visible = true
        MinPill.Visible = false
    end
end

-- //------------------------------------------------
-- // UNLOAD
-- //------------------------------------------------
NEXO.CleanupFns = {}
function NEXO.Unload()
    if NEXO.Unloaded then return end
    NEXO.Unloaded = true
    for _, fn in ipairs(NEXO.CleanupFns) do
        pcall(fn)
    end
    for _, conn in ipairs(NEXO.Connections) do
        pcall(function() conn:Disconnect() end)
    end
    pcall(function()
        if NotifyHolder then NotifyHolder:Destroy() end
    end)
    pcall(function() ScreenGui:Destroy() end)
    getgenv().NEXO_LOADED = nil
    getgenv().NEXO = nil
end

-- //================================================================
-- // ELEMENT LIBRARY
-- //================================================================

local UI = {}
NEXO.UI = UI

NEXO.Sections = {}   -- {page, frame, entries}
NEXO._layoutOrder = {}

local function nextOrder(parent)
    NEXO._layoutOrder[parent] = (NEXO._layoutOrder[parent] or 0) + 1
    return NEXO._layoutOrder[parent]
end

local function registerSearch(pageId, title, row, section)
    table.insert(NEXO.SearchIndex, {page = pageId, title = title, row = row})
    if section then table.insert(section.entries, row) end
end

local function rowHover(row)
    row.MouseEnter:Connect(function() row.BackgroundColor3 = Theme.CardHover end)
    row.MouseLeave:Connect(function() row.BackgroundColor3 = Theme.Card end)
end

-- //------------------------------------------------
-- // SECTION
-- //------------------------------------------------
function UI.Section(page, title)
    local section = Create("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = nextOrder(page.Frame),
        Parent = page.Frame,
    })
    Create("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = section})
    local header = Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Theme.FMono,
        Text = "// " .. string.upper(title),
        TextColor3 = Theme.TextFaint,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, 0, 0, 14),
        LayoutOrder = 0,
        Parent = section,
    })
    local list = Create("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = 1,
        Parent = section,
    })
    Create("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list})

    local sec = {Frame = section, List = list, Page = page, entries = {}}
    table.insert(NEXO.Sections, {page = page.Id, frame = section, entries = sec.entries})
    local _ = header
    return sec
end

-- //------------------------------------------------
-- // PARAGRAPH
-- //------------------------------------------------
function UI.Paragraph(sec, opts)
    local row = Create("Frame", {
        BackgroundColor3 = Theme.Card,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = nextOrder(sec.List),
        Parent = sec.List,
    })
    Corner(8, row)
    Stroke(Theme.StrokeSoft, 1, row)
    Create("UIPadding", {
        PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
        Parent = row,
    })
    Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Theme.FBold,
        Text = tostring(opts.Title or ""),
        TextColor3 = Theme.Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, 0, 0, 16),
        Parent = row,
    })
    Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Theme.FBody,
        Text = tostring(opts.Body or ""),
        TextColor3 = Theme.TextDim,
        TextSize = 12,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 0, 0, 18),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = row,
    })
    registerSearch(sec.Page.Id, opts.Title or "", row, sec)
    return row
end

-- //------------------------------------------------
-- // TOGGLE  (with optional keybind chip)
-- //------------------------------------------------
function UI.Toggle(sec, opts)
    local row = Create("TextButton", {
        BackgroundColor3 = Theme.Card,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = nextOrder(sec.List),
        Parent = sec.List,
    })
    Corner(8, row)
    Stroke(Theme.StrokeSoft, 1, row)
    Create("UIPadding", {
        PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 10),
        Parent = row,
    })
    rowHover(row)

    local textCol = Create("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -120, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = row,
    })
    Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Theme.FMed,
        Text = tostring(opts.Title or "toggle"),
        TextColor3 = Theme.Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, 0, 0, 18),
        Parent = textCol,
    })
    if opts.Desc then
        Create("TextLabel", {
            BackgroundTransparency = 1,
            Font = Theme.FMono,
            Text = tostring(opts.Desc),
            TextColor3 = Theme.TextFaint,
            TextSize = 10,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            Position = UDim2.new(0, 0, 0, 18),
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Parent = textCol,
        })
    end

    -- // toggle pill
    local pill = Create("TextButton", {
        BackgroundColor3 = Theme.Off,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 38, 0, 20),
        Text = "",
        AutoButtonColor = false,
        Parent = row,
    })
    Corner(10, pill)
    local knob = Create("Frame", {
        BackgroundColor3 = Theme.Gray,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.new(0, 14, 0, 14),
        Parent = pill,
    })
    Corner(7, knob)

    -- // keybind chip
    local chip = nil
    if opts.Keybind then
        chip = Create("TextButton", {
            BackgroundColor3 = Theme.Inset,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -48, 0.5, 0),
            Size = UDim2.new(0, 42, 0, 22),
            Font = Theme.FMono,
            Text = "[   ]",
            TextColor3 = Theme.TextFaint,
            TextSize = 10,
            AutoButtonColor = false,
            Parent = row,
        })
        Corner(4, chip)
        Stroke(Theme.StrokeSoft, 1, chip)
        NEXO._chipMap = NEXO._chipMap or {}
    end

    local state = {Value = opts.Default and true or false}
    local flag = opts.Flag
    local function paint()
        if state.Value then
            pill.BackgroundColor3 = Theme.White
            knob.BackgroundColor3 = Theme.Bg
            Tween(knob, 0.15, {Position = UDim2.new(1, -17, 0.5, 0)})
        else
            pill.BackgroundColor3 = Theme.Off
            knob.BackgroundColor3 = Theme.Gray
            Tween(knob, 0.15, {Position = UDim2.new(0, 3, 0.5, 0)})
        end
    end

    local element
    local function fire(v)
        if opts.Callback then
            local ok, err = pcall(opts.Callback, v)
            if not ok then warn("[NEXO] callback error: " .. tostring(err)) end
        end
    end

    element = {
        Kind = "toggle",
        Title = opts.Title,
        Set = function(v)
            state.Value = v and true or false
            paint()
            fire(state.Value)
        end,
        QuietSet = function(v)
            state.Value = v and true or false
            paint()
        end,
        Get = function() return state.Value end,
        Row = row,
    }
    if chip then NEXO._chipMap[chip] = element end
    paint()

    local function onToggle()
        state.Value = not state.Value
        paint()
        fire(state.Value)
    end
    row.MouseButton1Click:Connect(onToggle)
    pill.MouseButton1Click:Connect(onToggle)

    -- // keybind listening
    if chip then
        chip.MouseButton1Click:Connect(function()
            if NEXO._listening == chip then
                NEXO._listening = nil
                chip.Text = "[   ]"
                chip.TextColor3 = Theme.TextFaint
                return
            end
            if NEXO._listening and NEXO._listening.Parent then
                NEXO._listening.Text = "[   ]"
                NEXO._listening.TextColor3 = Theme.TextFaint
            end
            NEXO._listening = chip
            chip.Text = "key?"
            chip.TextColor3 = Theme.White
        end)
        element.Chip = chip
        element.Flag = flag
    end

    if flag then
        NEXO.Flags[flag] = element
    end
    registerSearch(sec.Page.Id, opts.Title or "", row, sec)
    return element
end

-- //------------------------------------------------
-- // SLIDER
-- //------------------------------------------------
function UI.Slider(sec, opts)
    local min = opts.Min or 0
    local max = opts.Max or 100
    local suffix = opts.Suffix or ""
    local decimals = (max - min) <= 5 and 1 or 0

    local row = Create("Frame", {
        BackgroundColor3 = Theme.Card,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = nextOrder(sec.List),
        Parent = sec.List,
    })
    Corner(8, row)
    Stroke(Theme.StrokeSoft, 1, row)
    Create("UIPadding", {
        PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
        Parent = row,
    })
    rowHover(row)

    local headRow = Create("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 18),
        Parent = row,
    })
    Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Theme.FMed,
        Text = tostring(opts.Title or "slider"),
        TextColor3 = Theme.Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(0.6, 0, 1, 0),
        Parent = headRow,
    })
    local valLabel = Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Theme.FMono,
        Text = "",
        TextColor3 = Theme.White,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.new(0.4, 0, 1, 0),
        Parent = headRow,
    })

    local track = Create("Frame", {
        BackgroundColor3 = Theme.Inset,
        Position = UDim2.new(0, 0, 0, 24),
        Size = UDim2.new(1, 0, 0, 6),
        Parent = row,
    })
    Corner(3, track)
    local fill = Create("Frame", {
        BackgroundColor3 = Theme.White,
        Size = UDim2.new(0, 0, 1, 0),
        Parent = track,
    })
    Corner(3, fill)
    local knob = Create("Frame", {
        BackgroundColor3 = Theme.White,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(0, 12, 0, 12),
        Parent = track,
    })
    Corner(6, knob)

    local state = {Value = opts.Default or min}
    local flag = opts.Flag

    local element
    local function fire(v)
        if opts.Callback then
            local ok, err = pcall(opts.Callback, v)
            if not ok then warn("[NEXO] callback error: " .. tostring(err)) end
        end
    end
    local function paint(v)
        local rel = (v - min) / (max - min)
        rel = math.clamp(rel, 0, 1)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        knob.Position = UDim2.new(rel, 0, 0.5, 0)
        local txt = tostring(v)
        if decimals == 1 then txt = string.format("%.1f", v) else txt = tostring(round(v)) end
        valLabel.Text = txt .. suffix
    end
    element = {
        Kind = "slider",
        Title = opts.Title,
        Set = function(v)
            v = math.clamp(tonumber(v) or min, min, max)
            state.Value = v
            paint(v)
            fire(v)
        end,
        QuietSet = function(v)
            v = math.clamp(tonumber(v) or min, min, max)
            state.Value = v
            paint(v)
        end,
        Get = function() return state.Value end,
        Row = row,
    }
    paint(state.Value)

    -- // drag logic
    local dragging = false
    local function updateFromX(x)
        local rel = (x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
        rel = math.clamp(rel, 0, 1)
        local v = min + (max - min) * rel
        if decimals == 0 then v = round(v) end
        element.Set(v)
    end
    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            updateFromX(input.Position.X)
        end
    end)
    table.insert(NEXO.Connections, UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromX(input.Position.X)
        end
    end))
    table.insert(NEXO.Connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))

    if flag then NEXO.Flags[flag] = element end
    registerSearch(sec.Page.Id, opts.Title or "", row, sec)
    return element
end

-- //------------------------------------------------
-- // DROPDOWN
-- //------------------------------------------------
function UI.Dropdown(sec, opts)
    local row = Create("Frame", {
        BackgroundColor3 = Theme.Card,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = nextOrder(sec.List),
        Parent = sec.List,
    })
    Corner(8, row)
    Stroke(Theme.StrokeSoft, 1, row)
    Create("UIPadding", {
        PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
        Parent = row,
    })
    rowHover(row)

    local headBtn = Create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 22),
        Text = "",
        AutoButtonColor = false,
        Parent = row,
    })
    Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Theme.FMed,
        Text = tostring(opts.Title or "dropdown"),
        TextColor3 = Theme.Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(0.55, 0, 1, 0),
        Parent = headBtn,
    })
    local valLabel = Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Theme.FMono,
        Text = tostring(opts.Default or "select..."),
        TextColor3 = Theme.White,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -18, 0, 0),
        Size = UDim2.new(0.45, 0, 1, 0),
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = headBtn,
    })
    local arrow = Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Theme.FMono,
        Text = "v",
        TextColor3 = Theme.TextFaint,
        TextSize = 11,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.new(0, 14, 1, 0),
        Parent = headBtn,
    })

    local optionsFrame = Create("Frame", {
        BackgroundColor3 = Theme.Inset,
        Position = UDim2.new(0, 0, 0, 30),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Visible = false,
        Parent = row,
    })
    Corner(6, optionsFrame)
    Stroke(Theme.StrokeSoft, 1, optionsFrame)
    Create("UIPadding", {PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = optionsFrame})
    Create("UIListLayout", {Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = optionsFrame})

    local state = {Value = opts.Default}
    local flag = opts.Flag
    local open = false

    local element
    local function fire(v)
        if opts.Callback then
            local ok, err = pcall(opts.Callback, v)
            if not ok then warn("[NEXO] callback error: " .. tostring(err)) end
        end
    end
    element = {
        Kind = "dropdown",
        Title = opts.Title,
        Set = function(v)
            state.Value = v
            valLabel.Text = tostring(v)
            fire(v)
        end,
        QuietSet = function(v)
            state.Value = v
            valLabel.Text = tostring(v)
        end,
        Get = function() return state.Value end,
        Refresh = function(newOptions)
            for _, c in ipairs(optionsFrame:GetChildren()) do
                if c:IsA("TextButton") then c:Destroy() end
            end
            for i, opt in ipairs(newOptions or {}) do
                local ob = Create("TextButton", {
                    BackgroundColor3 = Theme.Inset,
                    Size = UDim2.new(1, 0, 0, 24),
                    Font = Theme.FMono,
                    Text = tostring(opt),
                    TextColor3 = Theme.TextDim,
                    TextSize = 11,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    AutoButtonColor = false,
                    LayoutOrder = i,
                    Parent = optionsFrame,
                })
                Corner(4, ob)
                Create("UIPadding", {PaddingLeft = UDim.new(0, 8), Parent = ob})
                ob.MouseEnter:Connect(function() ob.TextColor3 = Theme.White ob.BackgroundColor3 = Theme.Card end)
                ob.MouseLeave:Connect(function() ob.TextColor3 = Theme.TextDim ob.BackgroundColor3 = Theme.Inset end)
                ob.MouseButton1Click:Connect(function()
                    element.Set(opt)
                    open = false
                    optionsFrame.Visible = false
                    arrow.Text = "v"
                end)
            end
        end,
        Row = row,
    }
    element.Refresh(opts.Options or {})

    headBtn.MouseButton1Click:Connect(function()
        open = not open
        if NEXO._openDropdown and NEXO._openDropdown ~= optionsFrame then
            NEXO._openDropdown.Visible = false
        end
        optionsFrame.Visible = open
        NEXO._openDropdown = open and optionsFrame or nil
        arrow.Text = open and "^" or "v"
    end)

    if flag then NEXO.Flags[flag] = element end
    registerSearch(sec.Page.Id, opts.Title or "", row, sec)
    return element
end

-- //------------------------------------------------
-- // BUTTON
-- //------------------------------------------------
function UI.Button(sec, opts)
    local row = Create("TextButton", {
        BackgroundColor3 = Theme.Card,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = nextOrder(sec.List),
        Parent = sec.List,
    })
    Corner(8, row)
    Stroke(Theme.StrokeSoft, 1, row)
    Create("UIPadding", {
        PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
        Parent = row,
    })
    local textCol = Create("Frame", { -- left text col
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -30, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = row,
    })
    Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Theme.FMed,
        Text = tostring(opts.Title or "button"),
        TextColor3 = Theme.Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, 0, 0, 18),
        Parent = textCol,
    })
    if opts.Desc then
        Create("TextLabel", {
            BackgroundTransparency = 1,
            Font = Theme.FMono,
            Text = tostring(opts.Desc),
            TextColor3 = Theme.TextFaint,
            TextSize = 10,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            Position = UDim2.new(0, 0, 0, 18),
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Parent = textCol,
        })
    end
    Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Theme.FMono,
        Text = ">",
        TextColor3 = Theme.TextFaint,
        TextSize = 14,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 14, 0, 20),
        Parent = row,
    })
    row.MouseEnter:Connect(function() row.BackgroundColor3 = Theme.CardHover end)
    row.MouseLeave:Connect(function() row.BackgroundColor3 = Theme.Card end)
    row.MouseButton1Click:Connect(function()
        if opts.Callback then
            local ok, err = pcall(opts.Callback)
            if not ok then warn("[NEXO] callback error: " .. tostring(err)) end
        end
    end)
    registerSearch(sec.Page.Id, opts.Title or "", row, sec)
    return row
end

-- //------------------------------------------------
-- // TEXT INPUT
-- //------------------------------------------------
function UI.Input(sec, opts)
    local row = Create("Frame", {
        BackgroundColor3 = Theme.Card,
        Size = UDim2.new(1, 0, 0, 44),
        LayoutOrder = nextOrder(sec.List),
        Parent = sec.List,
    })
    Corner(8, row)
    Stroke(Theme.StrokeSoft, 1, row)
    Create("UIPadding", {
        PaddingTop = UDim.new(0, 11), PaddingBottom = UDim.new(0, 11),
        PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
        Parent = row,
    })
    Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Theme.FMed,
        Text = tostring(opts.Title or "input"),
        TextColor3 = Theme.Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(0.45, 0, 1, 0),
        Parent = row,
    })
    local box = Create("TextBox", {
        BackgroundColor3 = Theme.Inset,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0.5, 0, 1, 0),
        Font = Theme.FMono,
        Text = tostring(opts.Default or ""),
        PlaceholderText = tostring(opts.Placeholder or "type here..."),
        PlaceholderColor3 = Theme.TextFaint,
        TextColor3 = Theme.White,
        TextSize = 12,
        ClearTextOnFocus = false,
        Parent = row,
    })
    Corner(6, box)
    Stroke(Theme.StrokeSoft, 1, box)
    Create("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = box})

    local state = {Value = tostring(opts.Default or "")}
    local flag = opts.Flag
    local element = {
        Kind = "input",
        Title = opts.Title,
        Get = function() return state.Value end,
        Set = function(v)
            state.Value = tostring(v)
            box.Text = tostring(v)
        end,
        QuietSet = function(v)
            state.Value = tostring(v)
            box.Text = tostring(v)
        end,
        Row = row,
    }
    box:GetPropertyChangedSignal("Text"):Connect(function()
        state.Value = box.Text
        if opts.Callback then pcall(opts.Callback, box.Text) end
    end)
    if flag then NEXO.Flags[flag] = element end
    registerSearch(sec.Page.Id, opts.Title or "", row, sec)
    return element
end

-- //================================================================
-- // SEARCH FILTER
-- //================================================================

function NEXO.ApplySearch(query)
    query = string.lower(tostring(query or ""))
    local page = NEXO.CurrentPage
    for _, entry in ipairs(NEXO.SearchIndex) do
        if entry.page == page then
            local match = (query == "") or (string.find(string.lower(entry.title), query, 1, true) ~= nil)
            entry.row.Visible = match
        else
            entry.row.Visible = true
        end
    end
    for _, sec in ipairs(NEXO.Sections) do
        if sec.page == page and query ~= "" then
            local any = false
            for _, r in ipairs(sec.entries) do
                if r.Visible then any = true end
            end
            sec.frame.Visible = any
        else
            sec.frame.Visible = true
        end
    end
end

do
    local t
    t = SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        NEXO.ApplySearch(SearchBox.Text)
    end)
    table.insert(NEXO.Connections, t)
end

-- //================================================================
-- // KEYBIND ENGINE
-- //================================================================

NEXO.MenuKey = Enum.KeyCode.RightShift
NEXO._chipMap = {}
NEXO.BindNames = {}

local function unbindFlag(flag)
    for kv, flags in pairs(NEXO.Binds) do
        for i, f in ipairs(flags) do
            if f == flag then table.remove(NEXO.Binds[kv], i) end
        end
    end
    NEXO.BindNames[flag] = nil
end

local function bindKeyToFlag(keyCode, flag)
    -- remove old binding for this flag
    for kv, flags in pairs(NEXO.Binds) do
        for i, f in ipairs(flags) do
            if f == flag then table.remove(NEXO.Binds[kv], i) end
        end
    end
    NEXO.Binds[keyCode.Value] = NEXO.Binds[keyCode.Value] or {}
    table.insert(NEXO.Binds[keyCode.Value], flag)
    NEXO.BindNames[flag] = keyCode.Name
end

table.insert(NEXO.Connections, UserInputService.InputBegan:Connect(function(input, gpe)
    if NEXO.Unloaded then return end
    if NEXO._menuListening then return end -- settings page handles its own rebind
    if UserInputService:GetFocusedTextBox() then return end

    local kc = input.KeyCode
    if kc == Enum.KeyCode.Unknown then return end

    -- // listening for a new bind
    local chip = NEXO._listening
    if chip then
        NEXO._listening = nil
        local el = NEXO._chipMap[chip]
        if el and el.Flag then
            if kc == Enum.KeyCode.Escape then
                unbindFlag(el.Flag)
                chip.Text = "[   ]"
                chip.TextColor3 = Theme.TextFaint
                NEXO.Notify("Keybind", "bind cleared", 2)
                return
            end
            bindKeyToFlag(kc, el.Flag)
            chip.Text = "[ " .. string.sub(kc.Name, 1, 4) .. " ]"
            chip.TextColor3 = Theme.White
            NEXO.Notify("Keybind", kc.Name .. " bound to " .. tostring(el.Title), 2)
        end
        return
    end

    -- // menu key
    if kc == NEXO.MenuKey then
        NEXO.ToggleUI()
        return
    end

    -- // feature binds
    local flags = NEXO.Binds[kc.Value]
    if flags then
        for _, flag in ipairs(flags) do
            local el = NEXO.Flags[flag]
            if el and el.Set then
                task.spawn(function() el.Set(not el.Get()) end)
            end
        end
    end
end))

-- //================================================================
-- // CHARACTER HELPERS
-- //================================================================

local function getCharacter()
    local c = LocalPlayer.Character
    if c and c:FindFirstChildOfClass("Humanoid") and c:FindFirstChild("HumanoidRootPart") then
        return c
    end
    return nil
end
NEXO.GetCharacter = getCharacter

local function getHumanoid()
    local c = getCharacter()
    return c and c:FindFirstChildOfClass("Humanoid") or nil
end
NEXO.GetHumanoid = getHumanoid

local function getRoot()
    local c = getCharacter()
    return c and (c.PrimaryPart or c:FindFirstChild("HumanoidRootPart")) or nil
end
NEXO.GetRoot = getRoot

local function getTool()
    local c = getCharacter()
    return c and c:FindFirstChildOfClass("Tool") or nil
end
NEXO.GetTool = getTool

NEXO.otherPlayers = function()
    local out = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then table.insert(out, plr) end
    end
    return out
end

NEXO.getOtherChar = function(plr)
    local c = plr.Character
    if c and c:FindFirstChildOfClass("Humanoid") and c:FindFirstChild("HumanoidRootPart") and c:FindFirstChildOfClass("Humanoid").Health > 0 then
        return c
    end
    return nil
end

-- //================================================================
-- // CONFIG ENGINE
-- //================================================================

function NEXO.ListConfigs()
    if not FS.available then return {} end
    local out = {}
    local ok, files = pcall(function() return FS.list(CFG_DIR) end)
    if ok and files then
        for _, f in ipairs(files) do
            local name = string.match(f, "([^/\\]+)%.json$") or string.match(f, "([^/\\]+)$")
            if name and name ~= ".keep" then table.insert(out, name) end
        end
    end
    return out
end

function NEXO.SaveConfig(name)
    if not FS.available then
        NEXO.Notify("Config", "filesystem unavailable in this executor", 4)
        return
    end
    name = tostring(name or "default")
    local data = {}
    for flag, el in pairs(NEXO.Flags) do
        local ok, v = pcall(el.Get)
        if ok then data[flag] = v end
    end
    local ok2 = pcall(function()
        FS.write(CFG_DIR .. "/" .. name .. ".json", HttpService:JSONEncode(data))
    end)
    if ok2 then
        NEXO.Notify("Config", "saved '" .. name .. "'", 3)
    else
        NEXO.Notify("Config", "save failed - check executor file access", 4)
    end
end

function NEXO.LoadConfig(name, quiet)
    if not FS.available then
        NEXO.Notify("Config", "filesystem unavailable in this executor", 4)
        return false
    end
    local path = CFG_DIR .. "/" .. tostring(name) .. ".json"
    if not FS.exists(path) then
        if not quiet then NEXO.Notify("Config", "config not found: " .. tostring(name), 3) end
        return false
    end
    local ok, raw = pcall(function() return FS.read(path) end)
    if not ok or not raw then return false end
    local ok2, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok2 or type(data) ~= "table" then return false end
    local applied = 0
    for flag, value in pairs(data) do
        local el = NEXO.Flags[flag]
        if el and el.Set then
            pcall(function() el.Set(value) end)
            applied = applied + 1
        end
    end
    if not quiet then
        NEXO.Notify("Config", "loaded '" .. tostring(name) .. "' - " .. tostring(applied) .. " settings", 3)
    end
    return true
end

function NEXO.DeleteConfig(name)
    if not FS.available then return false end
    local path = CFG_DIR .. "/" .. tostring(name) .. ".json"
    if FS.exists(path) then
        pcall(function() FS.del(path) end)
        NEXO.Notify("Config", "deleted '" .. tostring(name) .. "'", 3)
        return true
    end
    return false
end

-- //================================================================
-- // SETTINGS PERSISTENCE (menu key / watermark / scale / autoload)
-- //================================================================

function NEXO.SaveSettings()
    if not FS.available then return end
    pcall(function()
        FS.write(ROOT .. "/settings.json", HttpService:JSONEncode({
            MenuKey = NEXO.MenuKey and NEXO.MenuKey.Name or "RightShift",
            Watermark = NEXO._watermarkOn or false,
            UIScale = NEXO.UIScaleMult or 1,
            AutoLoad = NEXO._autoLoadConfig or "",
        }))
    end)
end

function NEXO.LoadSettings()
    if not FS.available then return end
    pcall(function()
        if not FS.exists(ROOT .. "/settings.json") then return end
        local data = HttpService:JSONDecode(FS.read(ROOT .. "/settings.json"))
        if type(data) ~= "table" then return end
        if data.MenuKey and Enum.KeyCode[data.MenuKey] then
            NEXO.MenuKey = Enum.KeyCode[data.MenuKey]
        end
        NEXO._watermarkOn = data.Watermark and true or false
        if tonumber(data.UIScale) then NEXO.UIScaleMult = math.clamp(data.UIScale, 0.6, 1.3) end
        NEXO._autoLoadConfig = tostring(data.AutoLoad or "")
    end)
end

NEXO.LoadSettings()

-- //================================================================
-- // UNIVERSAL: ESP CORE
-- //================================================================

local ESP = {
    Enabled   = false,
    Boxes     = false,
    Names     = false,
    Health    = false,
    Distance  = false,
    Tracers   = false,
    TeamCheck = false,
    MaxDist   = 2000,
    Entries   = {},
    Objects   = {},
}
NEXO.ESP = ESP

local function newBillboard(nameText)
    local bb = Create("BillboardGui", {
        Name = "NEXO_ESP",
        Size = UDim2.new(0, 140, 0, 44),
        AlwaysOnTop = true,
        MaxDistance = ESP.MaxDist,
        StudsOffset = Vector3.new(0, 2.4, 0),
    })
    local nameLabel = Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Theme.FMono,
        Text = nameText or "",
        TextColor3 = Theme.White,
        TextSize = 11,
        TextStrokeTransparency = 0.6,
        Size = UDim2.new(1, 0, 0, 14),
        Position = UDim2.new(0, 0, 0, 0),
        Parent = bb,
    })
    local hpBack = Create("Frame", {
        BackgroundColor3 = Color3.fromRGB(30, 30, 30),
        BorderSizePixel = 0,
        Position = UDim2.new(0.5, -30, 0, 16),
        Size = UDim2.new(0, 60, 0, 4),
        Parent = bb,
    })
    Corner(2, hpBack)
    local hpFill = Create("Frame", {
        BackgroundColor3 = Theme.White,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        Parent = hpBack,
    })
    Corner(2, hpFill)
    local distLabel = Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Theme.FMono,
        Text = "",
        TextColor3 = Theme.TextDim,
        TextSize = 10,
        TextStrokeTransparency = 0.7,
        Size = UDim2.new(1, 0, 0, 12),
        Position = UDim2.new(0, 0, 0, 22),
        Parent = bb,
    })
    return bb, nameLabel, hpFill, distLabel
end

local function ensureEntry(plr)
    if ESP.Entries[plr] then return ESP.Entries[plr] end
    local bb, nameLabel, hpFill, distLabel = newBillboard(plr.Name)
    local tracer, boxAdorn
    if DrawingOK then
        pcall(function()
            tracer = Drawing.new("Line")
            tracer.Visible = false
            tracer.Thickness = 1
            tracer.Color = Color3.fromRGB(220, 220, 220)
            tracer.Transparency = 0.8
        end)
    end
    boxAdorn = Create("BoxHandleAdornment", {
        Name = "NEXO_BOX",
        Adornee = nil,
        AlwaysOnTop = true,
        ZIndex = 10,
        Transparency = 0.55,
        Color3 = Theme.White,
        Size = Vector3.new(4.2, 6.2, 2.2),
    })
    local entry = {BB = bb, Name = nameLabel, HP = hpFill, Dist = distLabel, Tracer = tracer, Box = boxAdorn}
    ESP.Entries[plr] = entry
    return entry
end

local function removeEntry(plr)
    local e = ESP.Entries[plr]
    if e then
        pcall(function() e.BB:Destroy() end)
        pcall(function() e.Box:Destroy() end)
        pcall(function() if e.Tracer then e.Tracer:Remove() end end)
        ESP.Entries[plr] = nil
    end
end
NEXO._espRemoveEntry = removeEntry

table.insert(NEXO.Connections, Players.PlayerRemoving:Connect(removeEntry))

local espAccum = 0
table.insert(NEXO.Connections, RunService.Heartbeat:Connect(function(dt)
    if NEXO.Unloaded then return end
    espAccum = espAccum + dt
    if espAccum < 0.08 then return end
    espAccum = 0

    local cam = workspace.CurrentCamera
    if not cam then return end
    local myChar = getCharacter()

    for plr, entry in pairs(ESP.Entries) do
        local show = ESP.Enabled and plr.Parent ~= nil
        local char = show and plr.Character or nil
        local head = char and char:FindFirstChild("Head") or nil
        local root = char and char:FindFirstChild("HumanoidRootPart") or nil
        local hum = char and char:FindFirstChildOfClass("Humanoid") or nil
        if show and head and root and hum then
            if ESP.TeamCheck and plr.Team ~= nil and plr.Team == LocalPlayer.Team then
                show = false
            end
            if hum.Health <= 0 then show = false end
        else
            show = false
        end

        if show then
            local dist = myChar and myChar.PrimaryPart and (root.Position - myChar.PrimaryPart.Position).Magnitude or 0
            entry.BB.Adornee = head
            if entry.BB.Parent ~= cam then entry.BB.Parent = cam end
            entry.Name.Visible = ESP.Names
            entry.Dist.Visible = ESP.Distance
            entry.Name.Text = plr.DisplayName
            if ESP.Distance then
                entry.Dist.Text = tostring(round(dist)) .. "m"
            end
            if ESP.Health then
                entry.HP.Parent.Visible = true
                entry.HP.Size = UDim2.new(math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1), 0, 1, 0)
            else
                entry.HP.Parent.Visible = false
            end
            if ESP.Boxes then
                entry.Box.Adornee = root
                if entry.Box.Parent ~= cam then entry.Box.Parent = cam end
            else
                entry.Box.Adornee = nil
            end
            if entry.Tracer then
                if ESP.Tracers then
                    local ok, sp, onScreen = pcall(function()
                        return cam:WorldToViewportPoint(root.Position)
                    end)
                    if ok and onScreen then
                        entry.Tracer.Visible = true
                        entry.Tracer.From = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y)
                        entry.Tracer.To = Vector2.new(sp.X, sp.Y)
                    else
                        entry.Tracer.Visible = false
                    end
                else
                    entry.Tracer.Visible = false
                end
            end
        else
            entry.BB.Adornee = nil
            entry.Box.Adornee = nil
            if entry.Tracer then entry.Tracer.Visible = false end
        end
    end
end))

function NEXO.SetESP(key, value)
    if ESP[key] == nil and key ~= "Enabled" then return end
    ESP[key] = value and true or false
    if key == "Enabled" and not value then
        for plr in pairs(ESP.Entries) do
            local e = ESP.Entries[plr]
            if e then
                e.BB.Adornee = nil
                e.Box.Adornee = nil
                if e.Tracer then e.Tracer.Visible = false end
            end
        end
    end
    if key == "Enabled" and value then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then ensureEntry(plr) end
        end
    end
end

table.insert(NEXO.Connections, Players.PlayerAdded:Connect(function(plr)
    task.wait(1)
    if ESP.Enabled and not NEXO.Unloaded then ensureEntry(plr) end
end))

-- //------------------------------------------------
-- // OBJECT ESP (fruits, coins, entities, items...)
-- //------------------------------------------------

function NEXO.AddObjectESP(instance, opts)
    if not instance or not instance.Parent then return end
    opts = opts or {}
    for _, o in ipairs(ESP.Objects) do
        if o.Instance == instance then return end
    end
    local record = {Instance = instance, Highlight = nil, BB = nil, Label = opts.Label or instance.Name, Source = opts.Source or "generic"}
    local hlCount = #ESP.Objects
    if hlCount < 28 then
        pcall(function()
            local hl = Create("Highlight", {
                FillColor = opts.Color or Theme.White,
                OutlineColor = Theme.White,
                FillTransparency = 0.75,
                OutlineTransparency = 0,
                DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                Adornee = instance,
                Parent = instance,
            })
            record.Highlight = hl
        end)
    end
    pcall(function()
        local bb, nameLabel = newBillboard(opts.Label or instance.Name)
        nameLabel.Text = opts.Label or instance.Name
        bb.Size = UDim2.new(0, 140, 0, 16)
        bb.AlwaysOnTop = true
        bb.Adornee = instance
        bb.Parent = workspace.CurrentCamera
        record.BB = bb
        record.NameLabel = nameLabel
        entryHide(record)
    end)
    table.insert(ESP.Objects, record)
end
function entryHide(record)
    pcall(function()
        record.NameLabel.Visible = false
        record.HP.Parent.Visible = false
        record.Dist.Visible = false
    end)
end

function NEXO.ClearObjectESP(sourceFilter)
    for i = #ESP.Objects, 1, -1 do
        local record = ESP.Objects[i]
        if not sourceFilter or record.Source == sourceFilter then
            pcall(function() if record.Highlight then record.Highlight:Destroy() end end)
            pcall(function() if record.BB then record.BB:Destroy() end end)
            table.remove(ESP.Objects, i)
        end
    end
end

-- object esp distance culling loop
table.insert(NEXO.Connections, RunService.Heartbeat:Connect(function()
    if NEXO.Unloaded then return end
    if #ESP.Objects == 0 then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    for i = #ESP.Objects, 1, -1 do
        local record = ESP.Objects[i]
        if not record.Instance or not record.Instance.Parent then
            pcall(function() if record.Highlight then record.Highlight:Destroy() end end)
            pcall(function() if record.BB then record.BB:Destroy() end end)
            table.remove(ESP.Objects, i)
        end
    end
end))

-- //================================================================
-- // UNIVERSAL: COMBAT (aimbot / silent aim / hitbox / kill aura)
-- //================================================================

local Combat = {
    Aimbot      = false,
    AimFOV      = 120,
    Smoothness  = 3,
    TargetPart  = "Head",
    TeamCheck   = false,
    AimOnRMB    = true,
    SilentAim   = false,
    HitboxOn    = false,
    HitboxSize  = 12,
    KillAura    = false,
    KillAuraRange = 12,
    AutoClick   = false,
    ClickCPS    = 10,
    CurrentTarget = nil,
}
NEXO.Combat = Combat

local fovCircle
if DrawingOK then
    pcall(function()
        fovCircle = Drawing.new("Circle")
        fovCircle.Visible = false
        fovCircle.Thickness = 1
        fovCircle.NumSides = 60
        fovCircle.Radius = Combat.AimFOV
        fovCircle.Filled = false
        fovCircle.Color = Color3.fromRGB(200, 200, 200)
        fovCircle.Transparency = 0.6
    end)
end

local function findAimTarget()
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local mouseLoc = UserInputService:GetMouseLocation()
    local best, bestDist = nil, Combat.AimFOV
    local myChar = getCharacter()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local char = plr.Character
            local part = char and (char:FindFirstChild(Combat.TargetPart) or char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")) or nil
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if char and part and hum and hum.Health > 0 then
                if Combat.TeamCheck and plr.Team ~= nil and plr.Team == LocalPlayer.Team then
                    -- skip teammate
                else
                    local ok, sp, onScreen = pcall(function()
                        return cam:WorldToViewportPoint(part.Position)
                    end)
                    if ok and onScreen then
                        local msp = Vector2.new(sp.X, sp.Y) - Vector2.new(mouseLoc.X, mouseLoc.Y)
                        local d = msp.Magnitude
                        if d < bestDist then
                            best = part
                            bestDist = d
                        end
                    end
                end
            end
        end
    end
    return best
end

-- aimbot + fov loop
table.insert(NEXO.Connections, RunService.RenderStepped:Connect(function()
    if NEXO.Unloaded then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    if fovCircle then
        fovCircle.Radius = Combat.AimFOV
        local m = UserInputService:GetMouseLocation()
        fovCircle.Position = Vector2.new(m.X, m.Y)
        fovCircle.Visible = Combat.Aimbot or Combat.SilentAim
    end
    Combat.CurrentTarget = nil
    if not (Combat.Aimbot or Combat.SilentAim) then return end

    local wantAim = true
    if Combat.Aimbot and Combat.AimOnRMB then
        wantAim = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
    end
    local target = findAimTarget()
    Combat.CurrentTarget = target
    if Combat.Aimbot and wantAim and target then
        local alpha = math.clamp(11 - Combat.Smoothness, 1, 10) / 10
        local goal = CFrame.lookAt(cam.CFrame.Position, target.Position)
        cam.CFrame = cam.CFrame:Lerp(goal, alpha * 0.5)
    end
end))

-- silent aim hook
do
    local hooked = false
    function NEXO.TryHookSilentAim()
        if hooked then return true end
        local ok = pcall(function()
            if not hookmetamethod then return error("no hookmetamethod") end
            local oldNamecall
            oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
                local method = getnamecallmethod()
                if (method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist")
                    and Combat.SilentAim and Combat.CurrentTarget and Combat.CurrentTarget.Parent then
                    local args = {...}
                    local ray = args[1]
                    if ray and ray.Origin and ray.Direction then
                        local origin = ray.Origin
                        local dir = (Combat.CurrentTarget.Position - origin)
                        args[1] = Ray.new(origin, dir.Unit * math.max(dir.Magnitude, 10))
                        return oldNamecall(self, unpack(args))
                    end
                end
                return oldNamecall(self, ...)
            end)
            hooked = true
        end)
        return ok
    end
end

-- hitbox expander
do
    local expanded = {}
    local function restoreAll()
        for char, saved in pairs(expanded) do
            pcall(function()
                local root = char and char:FindFirstChild("HumanoidRootPart")
                if root then
                    root.Size = saved.size
                    root.Transparency = saved.transp
                end
            end)
        end
        expanded = {}
    end
    local acc = 0
    table.insert(NEXO.Connections, RunService.Heartbeat:Connect(function(dt)
        if NEXO.Unloaded then return end
        acc = acc + dt
        if acc < 0.3 then return end
        acc = 0
        if Combat.HitboxOn then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer then
                    local char = plr.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    if root and not expanded[char] then
                        expanded[char] = {size = root.Size, transp = root.Transparency}
                    end
                    if root then
                        root.Size = Vector3.new(Combat.HitboxSize, Combat.HitboxSize, Combat.HitboxSize)
                        root.Transparency = 0.6
                    end
                end
            end
        else
            restoreAll()
        end
    end))
    table.insert(NEXO.CleanupFns, restoreAll)
end

-- kill aura
do
    local acc = 0
    table.insert(NEXO.Connections, RunService.Heartbeat:Connect(function(dt)
        if NEXO.Unloaded then return end
        if not Combat.KillAura then return end
        acc = acc + dt
        if acc < 0.25 then return end
        acc = 0
        local myRoot = getRoot()
        local tool = getTool()
        if not myRoot or not tool then return end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local char = NEXO.getOtherChar(plr)
                local root = char and char:FindFirstChild("HumanoidRootPart")
                if root and (root.Position - myRoot.Position).Magnitude <= Combat.KillAuraRange then
                    pcall(function() tool:Activate() end)
                    task.delay(0.12, function() pcall(function() tool:Deactivate() end) end)
                    break
                end
            end
        end
    end))
end

-- auto clicker
do
    task.spawn(function()
        while not NEXO.Unloaded do
            if Combat.AutoClick then
                pcall(function()
                    local vim = game:GetService("VirtualInputManager")
                    local m = UserInputService:GetMouseLocation()
                    vim:SendMouseButtonEvent(m.X, m.Y, 0, true, game, 1)
                    vim:SendMouseButtonEvent(m.X, m.Y, 0, false, game, 1)
                end)
                wait(1 / math.max(Combat.ClickCPS, 1))
            else
                wait(0.15)
            end
        end
    end)
end

-- //================================================================
-- // UNIVERSAL: MOVEMENT
-- //================================================================

local Movement = {
    Speed    = 16,
    JumpPower= 50,
    InfJump  = false,
    Fly      = false,
    FlySpeed = 50,
    Noclip   = false,
    ClickTP  = false,
}
NEXO.Movement = Movement

-- capture originals once
table.insert(NEXO.Connections, LocalPlayer.CharacterAdded:Connect(function(char)
    local hum = char:WaitForChild("Humanoid", 10)
    if hum then
        if not NEXO.Restore.WalkSpeed then NEXO.Restore.WalkSpeed = hum.WalkSpeed end
        if not NEXO.Restore.JumpPower then NEXO.Restore.JumpPower = hum.JumpPower end
        task.wait(0.3)
        pcall(function()
            hum.WalkSpeed = Movement.Speed
            hum.UseJumpPower = true
            hum.JumpPower = Movement.JumpPower
        end)
    end
end))

do
    local hum = getHumanoid()
    if hum then
        NEXO.Restore.WalkSpeed = hum.WalkSpeed
        NEXO.Restore.JumpPower = hum.JumpPower
    end
end

-- infinite jump
table.insert(NEXO.Connections, UserInputService.JumpRequest:Connect(function()
    if Movement.InfJump and not NEXO.Unloaded then
        local hum = getHumanoid()
        if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end) end
    end
end))

-- fly + noclip loop
table.insert(NEXO.Connections, RunService.RenderStepped:Connect(function(dt)
    if NEXO.Unloaded then return end
    local char = getCharacter()
    local root = getRoot()
    if not char or not root then return end

    -- noclip
    if Movement.Noclip or Movement.Fly then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end

    -- fly
    if Movement.Fly then
        local cam = workspace.CurrentCamera
        if cam then
            local move = Vector3.new(0, 0, 0)
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then move = move + cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then move = move - cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then move = move + cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then move = move - cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move = move + Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then move = move - Vector3.new(0, 1, 0) end
            if move.Magnitude > 0 then
                root.CFrame = CFrame.new(root.Position + move.Unit * Movement.FlySpeed * dt)
            end
            pcall(function()
                root.Velocity = Vector3.new(0, 0, 0)
                root.RotVelocity = Vector3.new(0, 0, 0)
            end)
        end
    end
end))

-- click teleport
table.insert(NEXO.Connections, UserInputService.InputBegan:Connect(function(input, gpe)
    if NEXO.Unloaded then return end
    if not Movement.ClickTP or gpe then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        local mouse = LocalPlayer:GetMouse()
        local root = getRoot()
        if mouse and mouse.Hit and root then
            local pos = mouse.Hit.Position + Vector3.new(0, 4, 0)
            pcall(function() root.CFrame = CFrame.new(pos) end)
        end
    end
end))

-- teleport to player
function NEXO.TeleportToPlayer(name)
    for _, plr in ipairs(Players:GetPlayers()) do
        if string.lower(plr.Name) == string.lower(tostring(name)) or string.lower(plr.DisplayName) == string.lower(tostring(name)) then
            local char = NEXO.getOtherChar(plr)
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local myRoot = getRoot()
            if root and myRoot then
                pcall(function() myRoot.CFrame = root.CFrame * CFrame.new(0, 0, 3) end)
                NEXO.Notify("Teleport", "teleported to " .. plr.DisplayName, 2)
                return true
            end
        end
    end
    NEXO.Notify("Teleport", "player not found or not alive", 3)
    return false
end

-- //================================================================
-- // UNIVERSAL: UTILITY
-- //================================================================

local Utility = {
    AntiAFK        = false,
    AutoRejoin     = false,
    LowGfx         = false,
    RemoveTextures = false,
    Fullbright     = false,
    NoFog          = false,
    AutoInteract   = false,
}
NEXO.Utility = Utility

-- // anti afk
pcall(function()
    table.insert(NEXO.Connections, LocalPlayer.Idled:Connect(function()
        if Utility.AntiAFK and not NEXO.Unloaded then
            local vu = game:GetService("VirtualUser")
            vu:CaptureController()
            vu:ClickButton2(Vector2.new())
        end
    end))
end)

-- // auto rejoin + rejoin button
local REJOIN_CODE = 'game:GetService("TeleportService"):Teleport(' .. tostring(game.PlaceId) .. ', game:GetService("Players").LocalPlayer)'

function NEXO.RejoinServer()
    NEXO.Notify("Rejoin", "rejoining server...", 3)
    pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
    end)
end

function NEXO.SetAutoRejoin(on)
    Utility.AutoRejoin = on and true or false
    if on then
        NEXO.QueueOnTeleport(REJOIN_CODE)
        if not NEXO._rejoinConn then
            pcall(function()
                NEXO._rejoinConn = TeleportService.TeleportInitFailed:Connect(function()
                    if Utility.AutoRejoin and not NEXO.Unloaded then
                        wait(2)
                        NEXO.RejoinServer()
                    end
                end)
            end)
        end
        NEXO.Notify("Utility", "auto rejoin armed", 3)
    end
end

-- // server hop
function NEXO.ServerHop()
    NEXO.Notify("Utility", "scanning servers...", 3)
    task.spawn(function()
        local body = NEXO.HttpGet("https://games.roblox.com/v1/games/" .. tostring(game.PlaceId) .. "/servers/Public?sortOrder=Desc&limit=100")
        if not body then
            NEXO.Notify("Utility", "http blocked in this executor", 4)
            return
        end
        local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
        if not ok or not data or not data.data then
            NEXO.Notify("Utility", "could not read server list", 4)
            return
        end
        local candidates = {}
        for _, srv in ipairs(data.data) do
            if srv.id and srv.id ~= game.JobId and (srv.playing or 0) < (srv.maxPlayers or 50) then
                table.insert(candidates, srv.id)
            end
        end
        if #candidates == 0 then
            NEXO.Notify("Utility", "no other servers found", 4)
            return
        end
        local target = candidates[math.random(1, #candidates)]
        NEXO.Notify("Utility", "hopping to new server", 3)
        pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, target, LocalPlayer)
        end)
    end)
end

-- // fps boost + low gfx
pcall(function()
    if setfpscap then setfpscap(360) end
end)

local gfxApplied = false
local function applyLowGfx()
    pcall(function()
        local settings = UserSettings():GetService("UserGameSettings")
        settings.SavedQualityLevel = Enum.SavedQualitySetting.One
    end)
    pcall(function()
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") then
                d.Enabled = false
            elseif d:IsA("SurfaceGui") then
                d.Enabled = false
            end
        end
    end)
    gfxApplied = true
end

table.insert(NEXO.Connections, workspace.DescendantAdded:Connect(function(d)
    if Utility.LowGfx and not NEXO.Unloaded then
        task.defer(function()
            if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") then
                d.Enabled = false
            end
        end)
    end
end))

-- // lighting (fullbright / no fog)
NEXO.Restore.Lighting = {
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    FogEnd = Lighting.FogEnd,
    FogStart = Lighting.FogStart,
    GlobalShadows = Lighting.GlobalShadows,
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    ExposureCompensation = Lighting.ExposureCompensation,
}

local function applyFullbright(on)
    if on then
        pcall(function()
            Lighting.Brightness = 3
            Lighting.ClockTime = 14
            Lighting.FogEnd = 1e6
            Lighting.FogStart = 0
            Lighting.GlobalShadows = false
            Lighting.Ambient = Color3.fromRGB(190, 190, 190)
            Lighting.OutdoorAmbient = Color3.fromRGB(190, 190, 190)
            Lighting.ExposureCompensation = 0
        end)
    else
        local r = NEXO.Restore.Lighting
        pcall(function()
            Lighting.Brightness = r.Brightness
            Lighting.ClockTime = r.ClockTime
            Lighting.FogEnd = r.FogEnd
            Lighting.FogStart = r.FogStart
            Lighting.GlobalShadows = r.GlobalShadows
            Lighting.Ambient = r.Ambient
            Lighting.OutdoorAmbient = r.OutdoorAmbient
            Lighting.ExposureCompensation = r.ExposureCompensation
        end)
    end
end

local function applyNoFog(on)
    if on then
        pcall(function()
            Lighting.FogEnd = 1e6
            Lighting.FogStart = 0
        end)
    else
        local r = NEXO.Restore.Lighting
        pcall(function()
            Lighting.FogEnd = r.FogEnd
            Lighting.FogStart = r.FogStart
        end)
    end
end

-- // remove textures
local function applyRemoveTextures(on)
    task.spawn(function()
        pcall(function()
            for _, d in ipairs(workspace:GetDescendants()) do
                if d:IsA("Texture") or d:IsA("Decal") then
                    d.Transparency = on and 1 or 0
                end
            end
        end)
    end)
end

table.insert(NEXO.Connections, workspace.DescendantAdded:Connect(function(d)
    if Utility.RemoveTextures and not NEXO.Unloaded then
        task.defer(function()
            if d:IsA("Texture") or d:IsA("Decal") then d.Transparency = 1 end
        end)
    end
end))

-- // auto interact (proximity prompts)
do
    local acc = 0
    table.insert(NEXO.Connections, RunService.Heartbeat:Connect(function(dt)
        if NEXO.Unloaded then return end
        if not Utility.AutoInteract then return end
        acc = acc + dt
        if acc < 0.5 then return end
        acc = 0
        local myRoot = getRoot()
        if not myRoot then return end
        for _, prompt in ipairs(workspace:GetDescendants()) do
            if prompt:IsA("ProximityPrompt") and prompt.Enabled then
                local parent = prompt.Parent
                local target = parent and (parent:IsA("BasePart") and parent or (parent:IsA("Model") and parent.PrimaryPart) or nil)
                if target and (target.Position - myRoot.Position).Magnitude <= (prompt.MaxActivationDistance + 2) then
                    task.spawn(function()
                        pcall(function()
                            prompt:InputHoldBegin()
                            task.wait(math.max(prompt.HoldDuration, 0.05) + 0.05)
                            prompt:InputHoldEnd()
                        end)
                    end)
                end
            end
        end
    end))
end

-- // appliers used by settings ui
function NEXO.ApplyUtility(key, value)
    Utility[key] = value and true or false
    if key == "Fullbright" then applyFullbright(Utility.Fullbright) end
    if key == "NoFog" then applyNoFog(Utility.NoFog) end
    if key == "LowGfx" then if value then applyLowGfx() end end
    if key == "RemoveTextures" then applyRemoveTextures(Utility.RemoveTextures) end
    if key == "AutoRejoin" then NEXO.SetAutoRejoin(value) end
end

-- // restore everything on unload
table.insert(NEXO.CleanupFns, function()
    local r = NEXO.Restore.Lighting
    if r then
        pcall(function()
            Lighting.Brightness = r.Brightness
            Lighting.ClockTime = r.ClockTime
            Lighting.FogEnd = r.FogEnd
            Lighting.FogStart = r.FogStart
            Lighting.GlobalShadows = r.GlobalShadows
            Lighting.Ambient = r.Ambient
            Lighting.OutdoorAmbient = r.OutdoorAmbient
            Lighting.ExposureCompensation = r.ExposureCompensation
        end)
    end
    pcall(function()
        local hum = getHumanoid()
        if hum and NEXO.Restore.WalkSpeed then
            hum.WalkSpeed = NEXO.Restore.WalkSpeed
            hum.JumpPower = NEXO.Restore.JumpPower
        end
    end)
    NEXO.ClearObjectESP()
end)

-- //================================================================
-- // PAGE: HOME
-- //================================================================

local FeatureCount = 0
NEXO.SetFeatureCount = function(n)
    FeatureCount = n
end

do
    NEXO.AddNavGroup("main")
    local page = NEXO.RegisterPage("home", "Home", "nexo://home")

    local hero = Create("Frame", {
        BackgroundColor3 = Theme.Panel,
        Size = UDim2.new(1, 0, 0, 92),
        LayoutOrder = 0,
        Parent = page.Frame,
    })
    Corner(10, hero)
    Stroke(Theme.Stroke, 1, hero)
    do
        local art = Create("Frame", {BackgroundTransparency = 1, Position = UDim2.new(1, -76, 0.5, -25), Size = UDim2.new(0, 50, 0, 50), Parent = hero, Name = "Art"})
        Create("Frame", {BackgroundColor3 = Theme.White, BorderSizePixel = 0, Position = UDim2.new(0, 13, 0, 12), Size = UDim2.new(0, 5, 0, 26), Parent = art})
        Create("Frame", {BackgroundColor3 = Theme.White, BorderSizePixel = 0, Position = UDim2.new(0, 32, 0, 12), Size = UDim2.new(0, 5, 0, 26), Parent = art})
        Create("Frame", {
            BackgroundColor3 = Theme.White, BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.new(0, 5, 0, 37),
            Rotation = -42,
            Parent = art,
        })
    end
    Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Theme.FMono,
        Text = "> nexo hub v" .. NEXO.Version .. " loaded_",
        TextColor3 = Theme.TextDim,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 16, 0, 14),
        Size = UDim2.new(0.7, 0, 0, 14),
        Parent = hero,
    })
    Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Theme.FTitle,
        Text = "NEXO HUB",
        TextColor3 = Theme.White,
        TextSize = 28,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 14, 0, 30),
        Size = UDim2.new(0.7, 0, 0, 34),
        Parent = hero,
    })
    Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Theme.FMono,
        Text = "no login . no key . no queue",
        TextColor3 = Theme.TextFaint,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 16, 0, 66),
        Size = UDim2.new(0.7, 0, 0, 14),
        Parent = hero,
    })

    -- // stat cards row
    local stats = Create("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 64),
        LayoutOrder = 1,
        Parent = page.Frame,
    })
    Create("UIListLayout", {
        Padding = UDim.new(0, 8),
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = stats,
    })
    local function statCard(order, big, small)
        local c = Create("Frame", {
            BackgroundColor3 = Theme.Card,
            Size = UDim2.new(1 / 3, -6, 1, 0),
            LayoutOrder = order,
            Parent = stats,
        })
        Corner(8, c)
        Stroke(Theme.StrokeSoft, 1, c)
        local bigLbl = Create("TextLabel", {
            BackgroundTransparency = 1,
            Font = Theme.FBold,
            Text = big,
            TextColor3 = Theme.White,
            TextSize = 18,
            TextXAlignment = Enum.TextXAlignment.Left,
            Position = UDim2.new(0, 12, 0, 12),
            Size = UDim2.new(1, -24, 0, 22),
            Parent = c,
        })
        Create("TextLabel", {
            BackgroundTransparency = 1,
            Font = Theme.FMono,
            Text = string.upper(small),
            TextColor3 = Theme.TextFaint,
            TextSize = 9,
            TextXAlignment = Enum.TextXAlignment.Left,
            Position = UDim2.new(0, 12, 0, 36),
            Size = UDim2.new(1, -24, 0, 12),
            Parent = c,
        })
        return bigLbl
    end
    local featureLbl = statCard(1, "0", "features")
    statCard(2, ExecutorName, "executor")
    local gameLbl = statCard(3, "SCANNING", "game")

    NEXO.UpdateHomeStats = function(gameName)
        featureLbl.Text = tostring(FeatureCount)
        gameLbl.Text = gameName and string.upper(string.sub(gameName, 1, 12)) or "UNIVERSAL"
    end

    -- // sections
    local secInfo = UI.Section(page, "Session")
    local secLinks = UI.Section(page, "Links")
    local secNotes = UI.Section(page, "Notes")

    UI.Paragraph(secNotes, {
        Title = "Game support",
        Body = "NEXO auto-detects the game you are playing and unlocks a dedicated module for it: Blox Fruits, Da Hood, Murder Mystery 2, Blade Ball, Arsenal, Pet Sim 99, Doors, Adopt Me. Every other game gets the full universal suite - ESP, movement, combat, utility.",
    })
    UI.Paragraph(secNotes, {
        Title = "Keybinds",
        Body = "Click the [    ] chip on any cheat, then press a key to bind it. RightShift opens/closes the menu. Press ESC on a chip to clear its bind.",
    })

    UI.Button(secLinks, {
        Title = "Copy Discord invite",
        Desc = "join the community",
        Callback = function()
            NEXO.Copy("https://discord.gg/YOUR-INVITE")
            NEXO.Notify("Links", "discord invite copied", 3)
        end,
    })
    UI.Button(secLinks, {
        Title = "Copy website link",
        Desc = "nexo bypass",
        Callback = function()
            NEXO.Copy("https://your-site.com")
            NEXO.Notify("Links", "website link copied", 3)
        end,
    })
    UI.Button(secLinks, {
        Title = "Copy loadstring",
        Desc = "share the script",
        Callback = function()
            NEXO.Copy('loadstring(game:HttpGet("https://raw.githubusercontent.com/YOURNAME/NEXO-HUB/main/NEXO_HUB.lua"))()')
            NEXO.Notify("Links", "loadstring copied", 3)
        end,
    })

    local _ = secInfo
end

-- //================================================================
-- // PAGE: PLAYER (movement / character)
-- //================================================================

do
    NEXO.AddNavGroup("universal")
    local page = NEXO.RegisterPage("player", "Player", "nexo://universal/player")

    local secChar = UI.Section(page, "Character")
    UI.Slider(secChar, {Title = "Walk Speed", Min = 16, Max = 500, Default = 16, Suffix = " st/s", Flag = "walkspeed", Callback = function(v)
        Movement.Speed = v
        local hum = getHumanoid()
        if hum then pcall(function() hum.WalkSpeed = v end) end
    end})
    UI.Slider(secChar, {Title = "Jump Power", Min = 50, Max = 500, Default = 50, Suffix = " power", Flag = "jumppower", Callback = function(v)
        Movement.JumpPower = v
        local hum = getHumanoid()
        if hum then pcall(function()
            hum.UseJumpPower = true
            hum.JumpPower = v
        end) end
    end})
    UI.Toggle(secChar, {Title = "Infinite Jump", Desc = "jump in mid air, forever", Keybind = true, Flag = "infjump", Callback = function(v)
        Movement.InfJump = v
    end})
    UI.Toggle(secChar, {Title = "Noclip", Desc = "walk through walls", Keybind = true, Flag = "noclip", Callback = function(v)
        Movement.Noclip = v
    end})
    UI.Toggle(secChar, {Title = "Fly", Desc = "WASD + space/shift to move", Keybind = true, Flag = "fly", Callback = function(v)
        Movement.Fly = v
        local hum = getHumanoid()
        if hum and v then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end) end
    end})
    UI.Slider(secChar, {Title = "Fly Speed", Min = 10, Max = 300, Default = 50, Suffix = " st/s", Flag = "flyspeed", Callback = function(v)
        Movement.FlySpeed = v
    end})
    UI.Toggle(secChar, {Title = "Click Teleport", Desc = "left click anywhere to teleport", Keybind = true, Flag = "clicktp", Callback = function(v)
        Movement.ClickTP = v
    end})

    local secTp = UI.Section(page, "Teleport")
    local playerDrop
    local function refreshPlayers()
        local names = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then table.insert(names, plr.Name) end
        end
        if #names == 0 then table.insert(names, "no players") end
        if playerDrop then playerDrop.Refresh(names) end
    end
    playerDrop = UI.Dropdown(secTp, {Title = "Target Player", Options = {"refreshing..."}, Default = "select...", Flag = "tpplayer"})
    UI.Button(secTp, {Title = "Refresh Player List", Desc = "reload the dropdown", Callback = refreshPlayers})
    UI.Button(secTp, {Title = "Teleport To Player", Desc = "warp to the selected player", Callback = function()
        local el = NEXO.Flags["tpplayer"]
        local name = el and el.Get()
        if name and name ~= "select..." and name ~= "no players" then
            NEXO.TeleportToPlayer(name)
        else
            NEXO.Notify("Teleport", "select a player first", 3)
        end
    end})
    refreshPlayers()
end

-- //================================================================
-- // PAGE: COMBAT
-- //================================================================

do
    local page = NEXO.RegisterPage("combat", "Combat", "nexo://universal/combat")

    local secAim = UI.Section(page, "Aimbot")
    UI.Toggle(secAim, {Title = "Aimbot", Desc = "hold right mouse to lock on", Keybind = true, Flag = "aimbot", Callback = function(v)
        Combat.Aimbot = v
    end})
    UI.Slider(secAim, {Title = "Aim FOV", Min = 20, Max = 400, Default = 120, Suffix = " px", Flag = "aimfov", Callback = function(v)
        Combat.AimFOV = v
    end})
    UI.Slider(secAim, {Title = "Smoothness", Min = 1, Max = 10, Default = 3, Suffix = " (10 = snappy)", Flag = "aimsmooth", Callback = function(v)
        Combat.Smoothness = v
    end})
    UI.Dropdown(secAim, {Title = "Target Part", Options = {"Head", "Torso", "HumanoidRootPart"}, Default = "Head", Flag = "aimpart", Callback = function(v)
        Combat.TargetPart = v
    end})
    UI.Toggle(secAim, {Title = "Team Check", Desc = "ignore teammates", Flag = "aimteam", Callback = function(v)
        Combat.TeamCheck = v
    end})
    UI.Toggle(secAim, {Title = "Aim Only On Right Click", Desc = "off = always aim", Flag = "aimrmb", Default = true, Callback = function(v)
        Combat.AimOnRMB = v
    end})

    local secSilent = UI.Section(page, "Silent Aim")
    UI.Toggle(secSilent, {Title = "Silent Aim", Desc = "redirect rays to the locked target", Keybind = true, Flag = "silentaim", Callback = function(v)
        Combat.SilentAim = v
        if v then
            task.spawn(function()
                local ok = NEXO.TryHookSilentAim()
                if ok then
                    NEXO.Notify("Silent Aim", "hook installed", 3)
                else
                    NEXO.Notify("Silent Aim", "unsupported in this executor", 4)
                end
            end)
        end
    end})

    local secMelee = UI.Section(page, "Melee")
    UI.Toggle(secMelee, {Title = "Kill Aura", Desc = "auto swing your equipped tool", Keybind = true, Flag = "killaura", Callback = function(v)
        Combat.KillAura = v
    end})
    UI.Slider(secMelee, {Title = "Kill Aura Range", Min = 5, Max = 40, Default = 12, Suffix = " studs", Flag = "karange", Callback = function(v)
        Combat.KillAuraRange = v
    end})
    UI.Toggle(secMelee, {Title = "Auto Clicker", Desc = "spam left click", Keybind = true, Flag = "autoclick", Callback = function(v)
        Combat.AutoClick = v
    end})
    UI.Slider(secMelee, {Title = "Clicks Per Second", Min = 1, Max = 50, Default = 10, Suffix = " cps", Flag = "cps", Callback = function(v)
        Combat.ClickCPS = v
    end})

    local secHit = UI.Section(page, "Hitbox")
    UI.Toggle(secHit, {Title = "Hitbox Expander", Desc = "giant headshots on everyone", Flag = "hitbox", Callback = function(v)
        Combat.HitboxOn = v
    end})
    UI.Slider(secHit, {Title = "Hitbox Size", Min = 6, Max = 30, Default = 12, Suffix = " studs", Flag = "hitboxsize", Callback = function(v)
        Combat.HitboxSize = v
    end})
end

-- //================================================================
-- // PAGE: VISUALS
-- //================================================================

do
    local page = NEXO.RegisterPage("visuals", "Visuals", "nexo://universal/visuals")

    local secEsp = UI.Section(page, "Player ESP")
    UI.Toggle(secEsp, {Title = "ESP Master", Desc = "show players through walls", Keybind = true, Flag = "esp_master", Callback = function(v)
        NEXO.SetESP("Enabled", v)
    end})
    UI.Toggle(secEsp, {Title = "Boxes", Flag = "esp_box", Callback = function(v) NEXO.SetESP("Boxes", v) end})
    UI.Toggle(secEsp, {Title = "Names", Default = true, Flag = "esp_name", Callback = function(v) NEXO.SetESP("Names", v) end})
    UI.Toggle(secEsp, {Title = "Health Bar", Flag = "esp_hp", Callback = function(v) NEXO.SetESP("Health", v) end})
    UI.Toggle(secEsp, {Title = "Distance", Flag = "esp_dist", Callback = function(v) NEXO.SetESP("Distance", v) end})
    UI.Toggle(secEsp, {Title = "Tracers", Flag = "esp_tracer", Callback = function(v) NEXO.SetESP("Tracers", v) end})
    UI.Toggle(secEsp, {Title = "Team Check", Desc = "hide teammates", Flag = "esp_team", Callback = function(v) NEXO.SetESP("TeamCheck", v) end})

    local secWorld = UI.Section(page, "World")
    UI.Toggle(secWorld, {Title = "Fullbright", Desc = "max brightness, no shadows", Flag = "fullbright", Callback = function(v)
        NEXO.ApplyUtility("Fullbright", v)
    end})
    UI.Toggle(secWorld, {Title = "Remove Fog", Flag = "nofog", Callback = function(v)
        NEXO.ApplyUtility("NoFog", v)
    end})

    local secFx = UI.Section(page, "Effects")
    UI.Toggle(secFx, {Title = "Low Graphics", Desc = "kills particles for fps", Flag = "lowgfx", Callback = function(v)
        NEXO.ApplyUtility("LowGfx", v)
    end})
    UI.Toggle(secFx, {Title = "Remove Textures", Desc = "strips decals for fps", Flag = "rmtex", Callback = function(v)
        NEXO.ApplyUtility("RemoveTextures", v)
    end})
end

-- //================================================================
-- // PAGE: UTILITY
-- //================================================================

do
    local page = NEXO.RegisterPage("utility", "Utility", "nexo://universal/utility")

    local secSession = UI.Section(page, "Session")
    UI.Toggle(secSession, {Title = "Anti AFK", Desc = "never get kicked for idling", Default = true, Flag = "antiafk", Callback = function(v)
        Utility.AntiAFK = v
    end})
    UI.Toggle(secSession, {Title = "Auto Rejoin", Desc = "rejoin this server after teleports", Flag = "autorejoin", Callback = function(v)
        NEXO.ApplyUtility("AutoRejoin", v)
    end})
    UI.Button(secSession, {Title = "Rejoin Server", Desc = "instant rejoin this server", Callback = function()
        NEXO.RejoinServer()
    end})
    UI.Button(secSession, {Title = "Server Hop", Desc = "jump to a random fresh server", Callback = function()
        NEXO.ServerHop()
    end})

    local secInteract = UI.Section(page, "Interaction")
    UI.Toggle(secInteract, {Title = "Auto Interact", Desc = "auto-fire nearby proximity prompts", Keybind = true, Flag = "autointeract", Callback = function(v)
        NEXO.ApplyUtility("AutoInteract", v)
    end})

    local secMisc = UI.Section(page, "Misc")
    UI.Button(secMisc, {Title = "Rejoin New Account Slot", Desc = "quick teleport refresh", Callback = function()
        pcall(function()
            LocalPlayer:LoadCharacter()
        end)
        NEXO.Notify("Misc", "character refreshed", 2)
    end})
end

-- //================================================================
-- // GAME MODULE HELPERS
-- //================================================================

local ScanESP = {}     -- id -> {names, match, rootFn, notifyNew, known}
local Collectors = {}  -- id -> true

function NEXO.ScanESPStart(id, opts)
    opts = opts or {}
    local rec = {opts = opts, known = {}}
    ScanESP[id] = rec
    task.spawn(function()
        while ScanESP[id] == rec and not NEXO.Unloaded do
            local okR, container = pcall(opts.root or function() return workspace end)
            if okR and container then
                local count = 0
                for _, d in ipairs(container:GetDescendants()) do
                    count = count + 1
                    if count > 3000 then break end
                    local isTarget = d:IsA("BasePart") or (d:IsA("Model") and d.PrimaryPart ~= nil)
                    if isTarget and not rec.known[d] then
                        local okM, m = pcall(opts.match, d)
                        if okM and m then
                            rec.known[d] = true
                            NEXO.AddObjectESP(d, {Label = m, Source = id})
                            if opts.notifyNew then
                                NEXO.Notify(opts.notifyTitle or "ESP", tostring(m) .. " spawned", 3)
                            end
                        end
                    end
                end
            end
            wait(opts.interval or 2)
        end
    end)
end

function NEXO.ScanESPStop(id)
    ScanESP[id] = nil
    NEXO.ClearObjectESP(id)
end

function NEXO.CollectorStart(id, opts)
    opts = opts or {}
    Collectors[id] = true
    task.spawn(function()
        while Collectors[id] and not NEXO.Unloaded do
            local myRoot = getRoot()
            if myRoot then
                local okR, container = pcall(opts.root or function() return workspace end)
                if okR and container then
                    local best, bestD = nil, opts.range or 800
                    local scanned = 0
                    for _, p in ipairs(container:GetDescendants()) do
                        scanned = scanned + 1
                        if scanned > 3000 or not Collectors[id] then break end
                        if p:IsA("BasePart") or (p:IsA("Model") and p.PrimaryPart) then
                            local pos = p:IsA("BasePart") and p.Position or p.PrimaryPart.Position
                            if pos then
                                local dist = (pos - myRoot.Position).Magnitude
                                if dist < bestD then
                                    local okM, m = pcall(opts.match, p)
                                    if okM and m then
                                        best = p
                                        bestD = dist
                                    end
                                end
                            end
                        end
                    end
                    if best then
                        local target = best:IsA("BasePart") and best or best.PrimaryPart
                        if target then
                            if firetouchinterest then
                                pcall(function() firetouchinterest(target, myRoot, 0) end)
                                pcall(function() firetouchinterest(target, myRoot, 1) end)
                            end
                            if opts.tp then
                                pcall(function()
                                    myRoot.CFrame = CFrame.new(target.Position + Vector3.new(0, 3, 0))
                                end)
                            end
                        end
                    end
                end
            end
            wait(opts.interval or 0.6)
        end
    end)
end

function NEXO.CollectorStop(id)
    Collectors[id] = nil
end

local function nameHas(inst, words)
    local n = string.lower(inst.Name)
    for _, w in ipairs(words) do
        if string.find(n, w, 1, true) then return true end
    end
    return false
end
NEXO.nameHas = nameHas

-- //================================================================
-- // GAME MODULE: BLOX FRUITS (2753915549)
-- //================================================================

local function buildBloxFruits()
    local page = NEXO.RegisterPage("gamemodule", "Blox Fruits", "nexo://game/blox-fruits")

    local secFarm = UI.Section(page, "Farming [beta]")
    local enemiesRoot = function()
        return workspace:FindFirstChild("Enemies") or workspace
    end
    UI.Toggle(secFarm, {Title = "Auto Farm [BETA]", Desc = "warps to nearest enemy and attacks", Keybind = true, Flag = "bf_autofarm", Callback = function(v)
        if v then
            NEXO.CollectorStop("bf_farm")
            -- custom farm loop
            task.spawn(function()
                while NEXO.Flags["bf_autofarm"] and NEXO.Flags["bf_autofarm"].Get() and not NEXO.Unloaded do
                    local myRoot = getRoot()
                    local tool = getTool()
                    if myRoot then
                        local best, bestD = nil, 3000
                        local okR, container = pcall(enemiesRoot)
                        if okR and container then
                            for _, m in ipairs(container:GetChildren()) do
                                if m:IsA("Model") then
                                    local hum = m:FindFirstChildOfClass("Humanoid")
                                    local root = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Head")
                                    if hum and hum.Health > 0 and root then
                                        local d = (root.Position - myRoot.Position).Magnitude
                                        if d < bestD then best = m bestD = d end
                                    end
                                end
                            end
                        end
                        if best then
                            local broot = best:FindFirstChild("HumanoidRootPart") or best:FindFirstChild("Head")
                            if broot then
                                pcall(function()
                                    myRoot.CFrame = broot.CFrame * CFrame.new(0, 0, 4)
                                end)
                                if tool then
                                    pcall(function() tool:Activate() end)
                                    task.delay(0.1, function() pcall(function() tool:Deactivate() end) end)
                                else
                                    pcall(function()
                                        local vim = game:GetService("VirtualInputManager")
                                        local cam = workspace.CurrentCamera
                                        local sp = cam:WorldToViewportPoint(broot.Position)
                                        vim:SendMouseButtonEvent(sp.X, sp.Y, 0, true, game, 1)
                                        vim:SendMouseButtonEvent(sp.X, sp.Y, 0, false, game, 1)
                                    end)
                                end
                            end
                        end
                    end
                    wait(0.35)
                end
            end)
        else
            NEXO.CollectorStop("bf_farm")
        end
    end})
    UI.Toggle(secFarm, {Title = "Auto Attack Nearest", Desc = "spams clicks at the closest enemy", Flag = "bf_autoatk", Callback = function(v)
        if v then
            task.spawn(function()
                while NEXO.Flags["bf_autoatk"] and NEXO.Flags["bf_autoatk"].Get() and not NEXO.Unloaded do
                    local myRoot = getRoot()
                    if myRoot then
                        pcall(function()
                            local vim = game:GetService("VirtualInputManager")
                            local cam = workspace.CurrentCamera
                            vim:SendMouseButtonEvent(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2, 0, true, game, 1)
                            vim:SendMouseButtonEvent(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2, 0, false, game, 1)
                        end)
                    end
                    wait(0.12)
                end
            end)
        end
    end})

    local secFruit = UI.Section(page, "Fruits")
    UI.Toggle(secFruit, {Title = "Fruit ESP", Desc = "highlights devil fruits", Flag = "bf_fruitesp", Callback = function(v)
        if v then
            NEXO.ScanESPStart("bf_fruits", {
                root = function() return workspace end,
                match = function(d) if nameHas(d, {"fruit"}) and not nameHas(d, {"seller", "dealer", "shop"}) then return d.Name end return nil end,
                interval = 2,
            })
        else
            NEXO.ScanESPStop("bf_fruits")
        end
    end})
    UI.Toggle(secFruit, {Title = "Fruit Sniper", Desc = "teleports you to spawned fruits", Flag = "bf_sniper", Callback = function(v)
        if v then
            NEXO.CollectorStart("bf_snipe", {
                root = function() return workspace end,
                match = function(d) if nameHas(d, {"fruit"}) and not nameHas(d, {"seller", "dealer", "shop"}) then return true end return false end,
                tp = true,
                interval = 1.5,
                range = 50000,
            })
        else
            NEXO.CollectorStop("bf_snipe")
        end
    end})
    UI.Toggle(secFruit, {Title = "Fruit Notifier", Desc = "alerts when a fruit spawns", Flag = "bf_fruitnoti", Callback = function(v)
        if v then
            NEXO.ScanESPStart("bf_fruitnoti", {
                root = function() return workspace end,
                match = function(d) if nameHas(d, {"fruit"}) and not nameHas(d, {"seller", "dealer", "shop"}) then return d.Name end return nil end,
                interval = 3,
                notifyNew = true,
                notifyTitle = "Fruit",
            })
        else
            NEXO.ScanESPStop("bf_fruitnoti")
        end
    end})

    local secItems = UI.Section(page, "World")
    UI.Toggle(secItems, {Title = "Chest ESP", Flag = "bf_chestesp", Callback = function(v)
        if v then
            NEXO.ScanESPStart("bf_chests", {
                root = function() return workspace end,
                match = function(d) if nameHas(d, {"chest"}) then return d.Name end return nil end,
                interval = 3,
            })
        else
            NEXO.ScanESPStop("bf_chests")
        end
    end})
    UI.Toggle(secItems, {Title = "Island Players ESP", Desc = "universal player esp works too", Flag = "bf_playeresp", Callback = function(v)
        NEXO.SetESP("Enabled", v)
        NEXO.SetESP("Names", true)
        NEXO.SetESP("Boxes", v)
    end})

    UI.Paragraph(UI.Section(page, "Info"), {
        Title = "Module status",
        Body = "Blox Fruits module v1. Auto features are best-effort: the game updates often. Universal tabs (combat, visuals, movement, utility) always work alongside this module.",
    })
end

-- //================================================================
-- // GAME MODULE: DA HOOD (2788229376)
-- //================================================================

local function buildDaHood()
    local page = NEXO.RegisterPage("gamemodule", "Da Hood", "nexo://game/da-hood")

    local secCombat = UI.Section(page, "Combat")
    UI.Toggle(secCombat, {Title = "Silent Aim", Desc = "locks your shots to the target", Keybind = true, Flag = "dh_silent", Callback = function(v)
        Combat.SilentAim = v
        Combat.TargetPart = "UpperTorso"
        if v then
            task.spawn(function()
                local ok = NEXO.TryHookSilentAim()
                NEXO.Notify("Silent Aim", ok and "hook installed" or "unsupported in this executor", ok and 3 or 4)
            end)
        end
    end})
    UI.Toggle(secCombat, {Title = "Auto Attack Nearest", Desc = "swings at whoever is close", Flag = "dh_autoatk", Callback = function(v)
        Combat.KillAura = v
        Combat.KillAuraRange = 8
    end})

    local secFarm = UI.Section(page, "Farming [beta]")
    UI.Toggle(secFarm, {Title = "Auto Collect Cash [BETA]", Desc = "grabs dropped money around you", Keybind = true, Flag = "dh_cash", Callback = function(v)
        if v then
            NEXO.CollectorStart("dh_cash", {
                root = function() return workspace end,
                match = function(d) if nameHas(d, {"cash", "money", "drop"}) and not nameHas(d, {"map", "building"}) then return true end return false end,
                tp = true,
                interval = 0.5,
                range = 2000,
            })
        else
            NEXO.CollectorStop("dh_cash")
        end
    end})

    local secEsp = UI.Section(page, "ESP")
    UI.Toggle(secEsp, {Title = "Cash ESP", Flag = "dh_cashesp", Callback = function(v)
        if v then
            NEXO.ScanESPStart("dh_cashesp", {
                root = function() return workspace end,
                match = function(d) if d:IsA("BasePart") and nameHas(d, {"cash", "money"}) then return "$" end return nil end,
                interval = 2,
            })
        else
            NEXO.ScanESPStop("dh_cashesp")
        end
    end})
    UI.Toggle(secEsp, {Title = "Player ESP", Flag = "dh_playeresp", Callback = function(v)
        NEXO.SetESP("Enabled", v)
        NEXO.SetESP("Names", true)
        NEXO.SetESP("Boxes", v)
        NEXO.SetESP("Distance", v)
    end})

    local secGun = UI.Section(page, "Guns [beta]")
    UI.Button(secGun, {Title = "Gun Mods [BETA]", Desc = "attempts fire rate tweaks on equipped gun", Callback = function()
        local tool = getTool()
        if not tool then
            NEXO.Notify("Gun Mods", "equip a gun first", 3)
            return
        end
        local changed = 0
        pcall(function()
            for _, d in ipairs(tool:GetDescendants()) do
                if d:IsA("NumberValue") and nameHas(d, {"firerate", "cooldown", "delay"}) then
                    d.Value = 0.01
                    changed = changed + 1
                elseif d:IsA("NumberValue") and nameHas(d, {"reload"}) then
                    d.Value = 0.1
                    changed = changed + 1
                end
            end
        end)
        NEXO.Notify("Gun Mods", changed > 0 and ("tweaked " .. changed .. " values") or "no moddable values found (client-side only)", 4)
    end})
    UI.Paragraph(secGun, {
        Title = "Heads up",
        Body = "Da Hood is heavily server-authoritative. Gun mods and kill features only work where the game trusts the client - results vary by server and update.",
    })
end

-- //================================================================
-- // GAME MODULE: MURDER MYSTERY 2 (142823291)
-- //================================================================

local function buildMM2()
    local page = NEXO.RegisterPage("gamemodule", "Murder Mystery 2", "nexo://game/mm2")

    local secRoles = UI.Section(page, "Roles")
    local roleTags = {}
    local function scanRoles()
        local murderer, sheriff = nil, nil
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Character then
                if plr.Character:FindFirstChild("Knife") or (plr:FindFirstChild("Backpack") and plr.Backpack:FindFirstChild("Knife")) then
                    murderer = plr
                end
                if plr.Character:FindFirstChild("Gun") or (plr:FindFirstChild("Backpack") and plr.Backpack:FindFirstChild("Gun")) then
                    sheriff = plr
                end
            end
        end
        return murderer, sheriff
    end
    local function setRoleTag(plr, label)
        if roleTags[plr] then
            if roleTags[plr].label == label then return end
            pcall(function() roleTags[plr].hl:Destroy() end)
            pcall(function() roleTags[plr].bb:Destroy() end)
            roleTags[plr] = nil
        end
        local char = plr.Character
        local head = char and char:FindFirstChild("Head")
        if not char or not head then return end
        local hl = Create("Highlight", {
            FillTransparency = 0.8,
            OutlineColor = Theme.White,
            OutlineTransparency = 0,
            DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
            Adornee = char,
            Parent = char,
        })
        local bb = Create("BillboardGui", {
            Size = UDim2.new(0, 140, 0, 18),
            AlwaysOnTop = true,
            StudsOffset = Vector3.new(0, 3.2, 0),
            Adornee = head,
            Parent = workspace.CurrentCamera,
        })
        Create("TextLabel", {
            BackgroundTransparency = 1,
            Font = Theme.FMono,
            Text = label .. " | " .. plr.DisplayName,
            TextColor3 = Theme.White,
            TextSize = 11,
            TextStrokeTransparency = 0.5,
            Size = UDim2.new(1, 0, 1, 0),
            Parent = bb,
        })
        roleTags[plr] = {hl = hl, bb = bb, label = label}
    end
    local function clearRoleTags()
        for plr, tags in pairs(roleTags) do
            pcall(function() tags.hl:Destroy() end)
            pcall(function() tags.bb:Destroy() end)
            roleTags[plr] = nil
        end
    end
    table.insert(NEXO.CleanupFns, clearRoleTags)
    UI.Toggle(secRoles, {Title = "Role ESP", Desc = "tags the murderer and sheriff", Flag = "mm2_roles", Callback = function(v)
        if v then
            NEXO.SetESP("Enabled", true)
            NEXO.SetESP("Names", true)
            task.spawn(function()
                while NEXO.Flags["mm2_roles"] and NEXO.Flags["mm2_roles"].Get() and not NEXO.Unloaded do
                    local murderer, sheriff = scanRoles()
                    local wanted = {}
                    if murderer then wanted[murderer] = "MURDERER" end
                    if sheriff then wanted[sheriff] = "SHERIFF" end
                    for plr, label in pairs(wanted) do
                        setRoleTag(plr, label)
                    end
                    for plr in pairs(roleTags) do
                        if not wanted[plr] then
                            pcall(function() roleTags[plr].hl:Destroy() end)
                            pcall(function() roleTags[plr].bb:Destroy() end)
                            roleTags[plr] = nil
                        end
                    end
                    wait(1)
                end
                clearRoleTags()
            end)
        else
            clearRoleTags()
        end
    end})
    UI.Toggle(secRoles, {Title = "Murderer Alert", Desc = "notifies you who the murderer is", Flag = "mm2_alert", Callback = function(v)
        if v then
            task.spawn(function()
                local lastMsg = ""
                while NEXO.Flags["mm2_alert"] and NEXO.Flags["mm2_alert"].Get() and not NEXO.Unloaded do
                    local murderer = scanRoles()
                    if murderer and murderer.Name ~= lastMsg then
                        lastMsg = murderer.Name
                        NEXO.Notify("MM2", "murderer: " .. murderer.DisplayName, 5)
                    end
                    wait(1.5)
                end
            end)
        end
    end})

    local secItems = UI.Section(page, "Items")
    UI.Toggle(secItems, {Title = "Auto Gun Grab", Desc = "teleports to the dropped gun", Keybind = true, Flag = "mm2_gungrab", Callback = function(v)
        if v then
            NEXO.CollectorStart("mm2_gun", {
                root = function() return workspace end,
                match = function(d) if nameHas(d, {"gun", "revolver", "handle"}) and not nameHas(d, {"shop"}) then return true end return false end,
                tp = true,
                interval = 0.4,
                range = 50000,
            })
        else
            NEXO.CollectorStop("mm2_gun")
        end
    end})
    UI.Toggle(secItems, {Title = "Coin Farm", Desc = "teleports around collecting coins", Keybind = true, Flag = "mm2_coins", Callback = function(v)
        if v then
            NEXO.CollectorStart("mm2_coinfarm", {
                root = function() return workspace end,
                match = function(d) if nameHas(d, {"coin"}) then return true end return false end,
                tp = true,
                interval = 0.45,
                range = 50000,
            })
        else
            NEXO.CollectorStop("mm2_coinfarm")
        end
    end})
    UI.Toggle(secItems, {Title = "Coin ESP", Flag = "mm2_coinesp", Callback = function(v)
        if v then
            NEXO.ScanESPStart("mm2_coinesp", {
                root = function() return workspace end,
                match = function(d) if nameHas(d, {"coin"}) then return "$" end return nil end,
                interval = 2,
            })
        else
            NEXO.ScanESPStop("mm2_coinesp")
        end
    end})

    local secKill = UI.Section(page, "Murderer [beta]")
    UI.Toggle(secKill, {Title = "Kill All (as Murderer) [BETA]", Desc = "spams knife swings at everyone near", Keybind = true, Flag = "mm2_killall", Callback = function(v)
        if v then
            task.spawn(function()
                while NEXO.Flags["mm2_killall"] and NEXO.Flags["mm2_killall"].Get() and not NEXO.Unloaded do
                    local myRoot = getRoot()
                    if myRoot then
                        for _, plr in ipairs(Players:GetPlayers()) do
                            if plr ~= LocalPlayer then
                                local char = plr.Character
                                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                                local hum = char and char:FindFirstChildOfClass("Humanoid")
                                if hrp and hum and hum.Health > 0 and (hrp.Position - myRoot.Position).Magnitude < 12 then
                                    local knife = getTool()
                                    if knife then
                                        pcall(function() knife:Activate() end)
                                        task.delay(0.08, function() pcall(function() knife:Deactivate() end) end)
                                    end
                                    pcall(function()
                                        myRoot.CFrame = hrp.CFrame * CFrame.new(0, 0, 1.5)
                                    end)
                                    break
                                end
                            end
                        end
                    end
                    wait(0.25)
                end
            end)
        end
    end})
    UI.Paragraph(secKill, {
        Title = "How it works",
        Body = "Stay near the sheriff's corpse to pick up the gun, or use Auto Gun Grab. Kill All swings your knife at anyone inside 12 studs - the game decides if the hit counts.",
    })
end

-- //================================================================
-- // GAME MODULE: BLADE BALL (13772394625)
-- //================================================================

local function buildBladeBall()
    local page = NEXO.RegisterPage("gamemodule", "Blade Ball", "nexo://game/blade-ball")

    local function findBall()
        local ok, ball = pcall(function()
            local balls = workspace:FindFirstChild("Balls")
            if balls and #balls:GetChildren() > 0 then
                return balls:GetChildren()[1]
            end
            return workspace:FindFirstChild("Football") or workspace:FindFirstChild("Ball")
        end)
        if ok then return ball end
        return nil
    end

    local ParryState = {enabled = false, spam = false, dist = 22}
    NEXO._bladeParry = ParryState

    local function fireParry()
        pcall(function()
            local vim = game:GetService("VirtualInputManager")
            vim:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
            vim:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
        end)
        pcall(function()
            local rs = game:GetService("ReplicatedStorage")
            local remotes = rs:FindFirstChild("Remotes")
            if remotes then
                local r = remotes:FindFirstChild("Parry") or remotes:FindFirstChild("ParryButtonPress")
                if r then r:FireServer() end
            end
        end)
    end

    local secParry = UI.Section(page, "Parry")
    UI.Toggle(secParry, {Title = "Auto Parry", Desc = "parries when the ball closes in", Keybind = true, Flag = "bb_autoparry", Callback = function(v)
        ParryState.enabled = v
        if v then
            task.spawn(function()
                while ParryState.enabled and not NEXO.Unloaded do
                    local ball = findBall()
                    local myRoot = getRoot()
                    if ball and myRoot then
                        local pos = ball:IsA("BasePart") and ball.Position or (ball.PrimaryPart and ball.PrimaryPart.Position)
                        local vel = ball:IsA("BasePart") and ball.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
                        if pos then
                            local d = (pos - myRoot.Position).Magnitude
                            local closing = vel.Magnitude > 5
                            if d <= ParryState.dist and closing then
                                fireParry()
                            end
                        end
                    end
                    wait(0.05)
                end
            end)
        end
    end})
    UI.Toggle(secParry, {Title = "Spam Parry", Desc = "fires the parry constantly", Keybind = true, Flag = "bb_spam", Callback = function(v)
        ParryState.spam = v
        if v then
            task.spawn(function()
                while ParryState.spam and not NEXO.Unloaded do
                    fireParry()
                    wait(0.15)
                end
            end)
        end
    end})
    UI.Slider(secParry, {Title = "Parry Distance", Min = 5, Max = 60, Default = 22, Suffix = " studs", Flag = "bb_dist", Callback = function(v)
        ParryState.dist = v
    end})

    local secBall = UI.Section(page, "Ball")
    UI.Toggle(secBall, {Title = "Ball ESP", Desc = "highlight + label on the ball", Flag = "bb_ballesp", Callback = function(v)
        if v then
            NEXO.ScanESPStart("bb_ball", {
                root = function() return workspace end,
                match = function(d) if nameHas(d, {"football", "ball"}) and not nameHas(d, {"player", "pit"}) then return "BALL" end return nil end,
                interval = 1,
            })
        else
            NEXO.ScanESPStop("bb_ball")
        end
    end})
    UI.Toggle(secBall, {Title = "Player ESP", Flag = "bb_playeresp", Callback = function(v)
        NEXO.SetESP("Enabled", v)
        NEXO.SetESP("Names", true)
        NEXO.SetESP("Boxes", v)
    end})

    UI.Paragraph(UI.Section(page, "Info"), {
        Title = "Parry tips",
        Body = "Auto Parry triggers when the ball is inside your distance slider and moving. If the server updates its anti-cheat, raise the distance to 25-30 for a safer window.",
    })
end

-- //================================================================
-- // GAME MODULE: ARSENAL (286090429)
-- //================================================================

local function buildArsenal()
    local page = NEXO.RegisterPage("gamemodule", "Arsenal", "nexo://game/arsenal")

    local secCombat = UI.Section(page, "Combat")
    UI.Toggle(secCombat, {Title = "Aimbot (use universal tab)", Desc = "enables the universal aimbot", Keybind = true, Flag = "ar_aimbot", Callback = function(v)
        Combat.Aimbot = v
        Combat.TargetPart = "Head"
    end})
    UI.Toggle(secCombat, {Title = "Silent Aim", Keybind = true, Flag = "ar_silent", Callback = function(v)
        Combat.SilentAim = v
        if v then
            task.spawn(function()
                local ok = NEXO.TryHookSilentAim()
                NEXO.Notify("Silent Aim", ok and "hook installed" or "unsupported in this executor", ok and 3 or 4)
            end)
        end
    end})

    local secEsp = UI.Section(page, "ESP")
    UI.Toggle(secEsp, {Title = "Player ESP", Flag = "ar_esp", Callback = function(v)
        NEXO.SetESP("Enabled", v)
        NEXO.SetESP("Names", true)
        NEXO.SetESP("Boxes", v)
        NEXO.SetESP("Health", v)
    end})

    local secMods = UI.Section(page, "Weapon mods [beta]")
    UI.Button(secMods, {Title = "No Recoil [BETA]", Desc = "attempts to zero viewmodel recoil", Callback = function()
        local changed = 0
        pcall(function()
            local char = getCharacter()
            if char then
                for _, d in ipairs(char:GetDescendants()) do
                    if d:IsA("NumberValue") and nameHas(d, {"recoil", "kick", "spread", "scatter"}) then
                        d.Value = 0
                        changed = changed + 1
                    end
                end
            end
        end)
        NEXO.Notify("No Recoil", changed > 0 and ("zeroed " .. changed .. " values") or "no client recoil values found", 3)
    end})
    UI.Button(secMods, {Title = "Rapid Fire [BETA]", Desc = "attempts fire rate tweaks", Callback = function()
        local changed = 0
        pcall(function()
            local char = getCharacter()
            local bp = LocalPlayer:FindFirstChild("Backpack")
            local roots = {}
            if char then table.insert(roots, char) end
            if bp then table.insert(roots, bp) end
            for _, root in ipairs(roots) do
                for _, d in ipairs(root:GetDescendants()) do
                    if d:IsA("NumberValue") and nameHas(d, {"firerate", "cooldown", "delay"}) then
                        d.Value = 0.01
                        changed = changed + 1
                    end
                end
            end
        end)
        NEXO.Notify("Rapid Fire", changed > 0 and ("tweaked " .. changed .. " values") or "no client values found", 3)
    end})
end

-- //================================================================
-- // GAME MODULE: PET SIMULATOR 99 (8737899170)
-- //================================================================

local function buildPS99()
    local page = NEXO.RegisterPage("gamemodule", "Pet Simulator 99", "nexo://game/pet-sim-99")

    local secFarm = UI.Section(page, "Farming [beta]")
    UI.Toggle(secFarm, {Title = "Auto Farm Breakables [BETA]", Desc = "warps to and breaks the nearest breakable", Keybind = true, Flag = "ps_farm", Callback = function(v)
        if v then
            NEXO.CollectorStart("ps_farm", {
                root = function() return workspace end,
                match = function(d) if nameHas(d, {"breakable", "coin", "chest", "gem"}) and not nameHas(d, {"shop", "ui", "display"}) then return true end return false end,
                tp = true,
                interval = 0.6,
                range = 2000,
            })
        else
            NEXO.CollectorStop("ps_farm")
        end
    end})
    UI.Toggle(secFarm, {Title = "Auto Collect Lootbags", Desc = "grabs lootbags and diamonds", Keybind = true, Flag = "ps_loot", Callback = function(v)
        if v then
            NEXO.CollectorStart("ps_lootbags", {
                root = function() return workspace end,
                match = function(d) if nameHas(d, {"loot", "bag", "diamond", "orb"}) then return true end return false end,
                tp = true,
                interval = 0.45,
                range = 5000,
            })
        else
            NEXO.CollectorStop("ps_lootbags")
        end
    end})

    local secEsp = UI.Section(page, "ESP")
    UI.Toggle(secEsp, {Title = "Breakables ESP", Flag = "ps_brespesp", Callback = function(v)
        if v then
            NEXO.ScanESPStart("ps_bresp", {
                root = function() return workspace end,
                match = function(d) if nameHas(d, {"breakable", "chest"}) and not nameHas(d, {"shop", "ui"}) then return d.Name end return nil end,
                interval = 2.5,
            })
        else
            NEXO.ScanESPStop("ps_bresp")
        end
    end})
    UI.Toggle(secEsp, {Title = "Lootbag ESP", Flag = "ps_lootesp", Callback = function(v)
        if v then
            NEXO.ScanESPStart("ps_lootesp", {
                root = function() return workspace end,
                match = function(d) if nameHas(d, {"loot", "bag", "diamond"}) then return "$" end return nil end,
                interval = 2.5,
            })
        else
            NEXO.ScanESPStop("ps_lootesp")
        end
    end})

    UI.Paragraph(UI.Section(page, "Info"), {
        Title = "Module status",
        Body = "PS99 runs most progression on the server. Farm features are best-effort collection loops - they grab whatever spawns near you. Big updates may need match list tweaks.",
    })
end

-- //================================================================
-- // GAME MODULE: DOORS (6516141723)
-- //================================================================

local function buildDoors()
    local page = NEXO.RegisterPage("gamemodule", "Doors", "nexo://game/doors")

    local ENTITY_WORDS = {"rush", "ambush", "screech", "eyes", "seek", "figure", "halt", "dupe"}

    local secEntities = UI.Section(page, "Entities")
    UI.Toggle(secEntities, {Title = "Entity ESP", Desc = "highlights rush, ambush, seek...", Flag = "dr_entesp", Callback = function(v)
        if v then
            NEXO.ScanESPStart("dr_entesp", {
                root = function() return workspace end,
                match = function(d) if nameHas(d, ENTITY_WORDS) and not nameHas(d, {"room"}) then return string.upper(d.Name) end return nil end,
                interval = 1,
            })
        else
            NEXO.ScanESPStop("dr_entesp")
        end
    end})
    UI.Toggle(secEntities, {Title = "Entity Alerts", Desc = "notifies you when a killer spawns", Flag = "dr_alert", Callback = function(v)
        if v then
            NEXO.ScanESPStart("dr_alert", {
                root = function() return workspace end,
                match = function(d) if nameHas(d, {"rush", "ambush"}) then return d.Name .. " INCOMING" end return nil end,
                interval = 0.8,
                notifyNew = true,
                notifyTitle = "Doors",
            })
        else
            NEXO.ScanESPStop("dr_alert")
        end
    end})

    local secItems = UI.Section(page, "Items")
    UI.Toggle(secItems, {Title = "Item ESP", Desc = "keys, gold, batteries, lighters", Flag = "dr_itemesp", Callback = function(v)
        if v then
            NEXO.ScanESPStart("dr_items", {
                root = function() return workspace end,
                match = function(d) if nameHas(d, {"key", "gold", "battery", "lighter", "bandage", "vitamin", "lockpick"}) and not nameHas(d, {"door", "room"}) then return d.Name end return nil end,
                interval = 2,
            })
        else
            NEXO.ScanESPStop("dr_items")
        end
    end})
    UI.Toggle(secItems, {Title = "Auto Grab Keys", Desc = "teleports you onto dropped keys", Flag = "dr_keys", Callback = function(v)
        if v then
            NEXO.CollectorStart("dr_keygrab", {
                root = function() return workspace end,
                match = function(d) if string.lower(d.Name) == "key" or string.lower(d.Name) == "keys" then return true end return false end,
                tp = true,
                interval = 0.6,
                range = 5000,
            })
        else
            NEXO.CollectorStop("dr_keygrab")
        end
    end})

    local secPlay = UI.Section(page, "Gameplay")
    UI.Toggle(secPlay, {Title = "Instant Interact", Desc = "auto-fires doors, drawers, prompts", Flag = "dr_interact", Callback = function(v)
        NEXO.ApplyUtility("AutoInteract", v)
    end})
    UI.Button(secPlay, {Title = "Hide In Nearest Closet", Desc = "warps you inside close cover", Callback = function()
        local myRoot = getRoot()
        if not myRoot then return end
        local best, bestD = nil, 200
        for _, d in ipairs(workspace:GetDescendants()) do
            if nameHas(d, {"closet", "wardrobe", "bed", "locker"}) and d:IsA("BasePart") then
                local dist = (d.Position - myRoot.Position).Magnitude
                if dist < bestD then best = d bestD = dist end
            end
        end
        if best then
            pcall(function() myRoot.CFrame = CFrame.new(best.Position + Vector3.new(0, 3, 0)) end)
            NEXO.Notify("Doors", "warped to cover", 2)
        else
            NEXO.Notify("Doors", "no cover found nearby", 3)
        end
    end})
end

-- //================================================================
-- // GAME MODULE: ADOPT ME (920587237)
-- //================================================================

local function buildAdoptMe()
    local page = NEXO.RegisterPage("gamemodule", "Adopt Me", "nexo://game/adopt-me")

    local secFarm = UI.Section(page, "Farming [beta]")
    UI.Toggle(secFarm, {Title = "Auto Collect Orbs [BETA]", Desc = "collects candy and event orbs", Keybind = true, Flag = "am_orbs", Callback = function(v)
        if v then
            NEXO.CollectorStart("am_orbs", {
                root = function() return workspace end,
                match = function(d) if nameHas(d, {"orb", "candy", "gift", "buck"}) then return true end return false end,
                tp = true,
                interval = 0.5,
                range = 3000,
            })
        else
            NEXO.CollectorStop("am_orbs")
        end
    end})

    local secEsp = UI.Section(page, "ESP")
    UI.Toggle(secEsp, {Title = "Gift / Candy ESP", Flag = "am_giftesp", Callback = function(v)
        if v then
            NEXO.ScanESPStart("am_gifts", {
                root = function() return workspace end,
                match = function(d) if nameHas(d, {"gift", "candy", "orb"}) then return d.Name end return nil end,
                interval = 2,
            })
        else
            NEXO.ScanESPStop("am_gifts")
        end
    end})
    UI.Toggle(secEsp, {Title = "Player ESP", Flag = "am_playeresp", Callback = function(v)
        NEXO.SetESP("Enabled", v)
        NEXO.SetESP("Names", true)
        NEXO.SetESP("Boxes", v)
    end})

    UI.Paragraph(UI.Section(page, "Info"), {
        Title = "Module status",
        Body = "Adopt Me locks almost everything behind the server, so this module focuses on event collection and ESP. Pair it with Anti AFK in the utility tab for long farm sessions.",
    })
end

-- //================================================================
-- // GAME DETECTION
-- //================================================================

local GAME_MODULES = {
    [2753915549]  = {name = "Blox Fruits",       build = buildBloxFruits},
    [2788229376]  = {name = "Da Hood",           build = buildDaHood},
    [142823291]   = {name = "Murder Mystery 2",  build = buildMM2},
    [13772394625] = {name = "Blade Ball",        build = buildBladeBall},
    [286090429]   = {name = "Arsenal",           build = buildArsenal},
    [8737899170]  = {name = "Pet Simulator 99",  build = buildPS99},
    [6516141723]  = {name = "Doors",             build = buildDoors},
    [920587237]   = {name = "Adopt Me",          build = buildAdoptMe},
}

local DetectedGame = nil
do
    local module = GAME_MODULES[game.PlaceId]
    if module then
        DetectedGame = module.name
        NEXO.AddNavGroup("game module")
        pcall(module.build)
        NEXO.SetGameBadge(module.name, true)
    else
        NEXO.SetGameBadge("UNIVERSAL MODE", false)
    end
end
NEXO.DetectedGame = DetectedGame

-- //================================================================
-- // PAGE: CONFIG
-- //================================================================

do
    NEXO.AddNavGroup("system")
    local page = NEXO.RegisterPage("config", "Config", "nexo://system/config")

    if not FS.available then
        UI.Paragraph(UI.Section(page, "Warning"), {
            Title = "Filesystem unavailable",
            Body = "Your executor does not expose writefile/readfile, so configs cannot be saved to disk. Every other feature still works - configs just will not persist between sessions.",
        })
    end

    local secFile = UI.Section(page, "Config File")
    local nameInput = UI.Input(secFile, {Title = "Config Name", Default = getgenv().NEXO_AUTOLOAD_CONFIG or "default", Placeholder = "my config"})

    local listDrop = UI.Dropdown(secFile, {Title = "Saved Configs", Options = {"none yet"}, Default = "select..."})
    local function refreshConfigs()
        local list = NEXO.ListConfigs()
        if #list == 0 then
            list = {"none yet"}
        end
        listDrop.Refresh(list)
    end
    refreshConfigs()

    UI.Button(secFile, {Title = "Save Config", Desc = "writes every toggle, slider and dropdown", Callback = function()
        NEXO.SaveConfig(nameInput.Get())
        refreshConfigs()
    end})
    UI.Button(secFile, {Title = "Load Config", Desc = "applies the selected config", Callback = function()
        local name = listDrop.Get()
        if name and name ~= "select..." and name ~= "none yet" then
            NEXO.LoadConfig(name)
        else
            NEXO.Notify("Config", "select a config from the dropdown first", 3)
        end
    end})
    UI.Button(secFile, {Title = "Delete Config", Desc = "removes the selected config file", Callback = function()
        local name = listDrop.Get()
        if name and name ~= "select..." and name ~= "none yet" then
            NEXO.DeleteConfig(name)
            refreshConfigs()
        end
    end})
    UI.Button(secFile, {Title = "Refresh List", Callback = refreshConfigs})

    UI.Toggle(secFile, {Title = "Auto Load On Start", Desc = "loads the selected config every launch", Flag = "autoloadcfg", Callback = function(v)
        if v then
            NEXO._autoLoadConfig = listDrop.Get() or ""
            NEXO.SaveSettings()
            NEXO.Notify("Config", "will auto-load '" .. tostring(NEXO._autoLoadConfig) .. "'", 3)
        else
            NEXO._autoLoadConfig = ""
            NEXO.SaveSettings()
        end
    end})
end

-- //================================================================
-- // PAGE: SETTINGS
-- //================================================================

do
    local page = NEXO.RegisterPage("settings", "Settings", "nexo://system/settings")

    local secMenu = UI.Section(page, "Menu")
    menuBtn = UI.Button(secMenu, {
        Title = "Menu Key: " .. NEXO.MenuKey.Name,
        Desc = "click, then press any key to rebind the menu",
        Callback = function()
            NEXO._menuListening = true
            NEXO.Notify("Settings", "press any key for the menu...", 3)
        end,
    })

    -- menu key rebinding listener
    table.insert(NEXO.Connections, UserInputService.InputBegan:Connect(function(input, gpe)
        if not NEXO._menuListening then return end
        if gpe then return end
        NEXO._menuListening = false
        if input.UserInputType == Enum.UserInputType.Keyboard then
            NEXO.MenuKey = input.KeyCode
            NEXO.SaveSettings()
            NEXO.Notify("Settings", "menu key set to " .. input.KeyCode.Name, 3)
            task.defer(function()
                -- rebuild the button label
                local titleLbl = menuBtn and menuBtn:FindFirstChildWhichIsA("Frame")
                if titleLbl then
                    local t = titleLbl:FindFirstChildWhichIsA("TextLabel")
                    if t then t.Text = "Menu Key: " .. input.KeyCode.Name end
                end
            end)
        end
    end))

    UI.Slider(secMenu, {Title = "UI Scale", Min = 0.6, Max = 1.3, Default = NEXO.UIScaleMult or 1, Suffix = "x", Flag = "uiscale", Callback = function(v)
        NEXO.UIScaleMult = v
        if NEXO.ApplyScale then NEXO.ApplyScale() end
        NEXO.SaveSettings()
    end})

    local secVisual = UI.Section(page, "Interface")
    UI.Toggle(secVisual, {Title = "Watermark", Desc = "small fps/ping badge top left", Flag = "watermark", Default = NEXO._watermarkOn, Callback = function(v)
        NEXO._watermarkOn = v
        NEXO.SetWatermark(v)
        NEXO.SaveSettings()
    end})
    UI.Toggle(secVisual, {Title = "Notifications", Default = true, Flag = "notifications", Callback = function(v)
        NEXO.NotifyEnabled = v
    end})

    local secDanger = UI.Section(page, "Danger Zone")
    UI.Button(secDanger, {Title = "Unload NEXO", Desc = "kills the ui and restores everything", Callback = function()
        NEXO.Unload()
    end})
end

-- //================================================================
-- // BOOT
-- //================================================================

-- wrap unload to persist settings
do
    local oldUnload = NEXO.Unload
    NEXO.Unload = function()
        pcall(NEXO.SaveSettings)
        oldUnload()
    end
end

-- feature count + home stats
local featureN = 0
for _ in pairs(NEXO.Flags) do featureN = featureN + 1 end
NEXO.SetFeatureCount(featureN)
if NEXO.UpdateHomeStats then
    NEXO.UpdateHomeStats(NEXO.DetectedGame)
end

-- apply persisted settings
if NEXO._watermarkOn then NEXO.SetWatermark(true) end
if NEXO.ApplyScale then NEXO.ApplyScale() end

-- open home page
NEXO.ShowPage("home")

-- autoload config
if NEXO._autoLoadConfig and NEXO._autoLoadConfig ~= "" then
    task.delay(1, function()
        NEXO.LoadConfig(NEXO._autoLoadConfig, true)
    end)
end

-- welcome
task.delay(0.4, function()
    if NEXO.DetectedGame then
        NEXO.Notify("NEXO", "loaded - " .. NEXO.DetectedGame .. " module unlocked", 4)
    else
        NEXO.Notify("NEXO", "loaded - universal mode", 4)
    end
    NEXO.Notify("NEXO", "press " .. NEXO.MenuKey.Name .. " to toggle the menu", 6)
end)

-- console banner
print("==========================================")
print("  NEXO HUB v" .. NEXO.Version .. " | pure monochrome")
print("  executor: " .. ExecutorName)
print("  game: " .. (NEXO.DetectedGame or "universal mode"))
print("  features: " .. tostring(featureN))
print("  menu key: " .. NEXO.MenuKey.Name)
print("==========================================")
