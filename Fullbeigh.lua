--!strict
-- Nome: UltraAggressiveRenderDominance.LocalScript
-- Descrição: Camada dominante de renderização, iluminação e performance com detecção extrema e aniquilação de efeitos.
-- Autor: Sistema Automático (Ultra Profissional)
-- Versão: 3.0.0 (Extremo, Agressivo, Estruturado)

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Terrain = workspace:FindFirstChildOfClass("Terrain")
local StatsService = nil
pcall(function()
    StatsService = game:GetService("Stats")
end)

-- ========================
-- CONFIGURAÇÃO GLOBAL
-- ========================
local CONFIG = {
    LIGHTING = {
        BRIGHTNESS = 0.1,
        GLOBAL_SHADOWS = false,
        AMBIENT = Color3.fromRGB(200, 200, 200),
        OUTDOOR_AMBIENT = Color3.fromRGB(200, 200, 200),
        FOG_START = 0,
        FOG_END = 100000,
        DAY_EXPOSURE = 0.4,
        NIGHT_EXPOSURE = 1.2,
    },
    WATER = {
        WAVE_SIZE = 0,
        WAVE_SPEED = 0,
        REFLECTANCE = 0,
    },
    VISUAL_CONVERSION = {
        BLACK_TO_COLOR = Color3.fromRGB(180, 180, 180),
        NEON_TO_ICE = true,
        TEXTURE_SCALE = 1,
    },
    SCANNER = {
        CLASS_BLACKLIST = {
            -- Luzes
            "PointLight", "SpotLight", "SurfaceLight",
            -- Partículas e Rastros
            "ParticleEmitter", "Trail",
            -- Feixes
            "Beam",
            -- Fogo/Fumaça/Brilhos
            "Fire", "Smoke", "Sparkles",
            -- Efeitos de tela
            "BloomEffect", "BlurEffect", "ColorCorrectionEffect",
            "SunRaysEffect", "DepthOfFieldEffect",
            -- Atmósfera/Névoa
            "Atmosphere", "Fog",
        },
        BATCH_SIZE_PC = 100,
        BATCH_SIZE_MOBILE = 30,
        BATCH_SIZE_CONSOLE = 50,
        SCAN_INTERVAL_PC = 2.0,
        SCAN_INTERVAL_MOBILE = 5.0,
        SCAN_INTERVAL_CONSOLE = 4.0,
    },
    PROFILER = {
        TARGET_FPS = 240,
        LOW_FPS_THRESHOLD = 40,
        HIGH_FPS_THRESHOLD = 120,
        ADAPT_STEP = 0.05,
    },
}

-- ========================
-- DETECÇÃO DE AMBIENTE
-- ========================
local Environment = {}
do
    local platform = "Unknown"
    local isTouch = pcall(function() return UserInputService.TouchEnabled end) and UserInputService.TouchEnabled
    local isMouse = pcall(function() return UserInputService.MouseEnabled end) and UserInputService.MouseEnabled
    local isKeyboard = pcall(function() return UserInputService.KeyboardEnabled end) and UserInputService.KeyboardEnabled

    if isTouch and not isKeyboard then
        platform = "Mobile"
    elseif isKeyboard and isMouse then
        platform = "PC"
    elseif not isKeyboard and not isMouse and not isTouch then
        platform = "Console"
    else
        platform = "PC"  -- fallback seguro
    end

    Environment.Platform = platform
    Environment.IsMobile = (platform == "Mobile")
    Environment.IsConsole = (platform == "Console")
    Environment.IsPC = (platform == "PC")

    -- Verificação de executor (genérica)
    local executorDetected = false
    pcall(function()
        -- Heurísticas simples para ambientes alterados
        if getgenv or syn or identifyexecutor then
            executorDetected = true
        end
    end)
    Environment.ExecutorDetected = executorDetected
end

-- ========================
-- SERVIÇO: Scheduler Adaptativo
-- ========================
local Scheduler = {}
do
    local activeLoops = {}
    local nextId = 0

    function Scheduler:BindToHeartbeat(name: string, fn: (delta: number) -> ())
        local id = nextId
        nextId += 1
        local connection
        connection = RunService.Heartbeat:Connect(function(delta: number)
            local success, err = pcall(fn, delta)
            if not success then
                warn("[Scheduler] Heartbeat error in", name, ":", err)
                -- Watchdog reinicia automaticamente
                connection:Disconnect()
                task.wait(0.5)
                Scheduler:BindToHeartbeat(name, fn)
            end
        end)
        activeLoops["Heartbeat_" .. name] = connection
        return connection
    end

    function Scheduler:BindToRenderStepped(name: string, fn: (delta: number) -> ())
        local id = nextId
        nextId += 1
        local connection
        connection = RunService.RenderStepped:Connect(function(delta: number)
            local success, err = pcall(fn, delta)
            if not success then
                warn("[Scheduler] RenderStepped error in", name, ":", err)
                connection:Disconnect()
                task.wait(0.5)
                Scheduler:BindToRenderStepped(name, fn)
            end
        end)
        activeLoops["Render_" .. name] = connection
        return connection
    end

    function Scheduler:Defer(fn: () -> ())
        task.defer(function()
            pcall(fn)
        end)
    end

    function Scheduler:Spawn(fn: () -> ())
        task.spawn(function()
            pcall(fn)
        end)
    end

    function Scheduler:DestroyAll()
        for _, conn in pairs(activeLoops) do
            conn:Disconnect()
        end
        table.clear(activeLoops)
    end
end

-- ========================
-- CONTROLLER: Iluminação Hard Lock
-- ========================
local LightingController = {}
do
    local function isDaytime()
        local time = Lighting.ClockTime or 12
        return time >= 6 and time < 18
    end

    local function applyLighting()
        pcall(function()
            Lighting.Brightness = CONFIG.LIGHTING.BRIGHTNESS
            Lighting.GlobalShadows = CONFIG.LIGHTING.GLOBAL_SHADOWS
            Lighting.Ambient = CONFIG.LIGHTING.AMBIENT
            Lighting.OutdoorAmbient = CONFIG.LIGHTING.OUTDOOR_AMBIENT
            Lighting.FogStart = CONFIG.LIGHTING.FOG_START
            Lighting.FogEnd = CONFIG.LIGHTING.FOG_END

            local exposure = isDaytime() and CONFIG.LIGHTING.DAY_EXPOSURE or CONFIG.LIGHTING.NIGHT_EXPOSURE
            Lighting.ExposureCompensation = exposure

            -- Aniquilar objetos de névoa/atmosfera (reforço)
            for _, child in ipairs(Lighting:GetChildren()) do
                if child.ClassName == "Atmosphere" or child.ClassName == "Fog" then
                    child:Destroy()
                end
            end
        end)
    end

    function LightingController:Start()
        -- Aplicação contínua a cada frame de renderização
        Scheduler:BindToRenderStepped("LightingLock", applyLighting)
    end
end

-- ========================
-- CONTROLLER: Água Override
-- ========================
local WaterController = {}
do
    local function overrideWater()
        pcall(function()
            if Terrain then
                Terrain.WaterWaveSize = CONFIG.WATER.WAVE_SIZE
                Terrain.WaterWaveSpeed = CONFIG.WATER.WAVE_SPEED
                Terrain.WaterReflectance = CONFIG.WATER.REFLECTANCE
            end
            -- Remover quaisquer objetos Water existentes (classe "Water")
            for _, obj in ipairs(workspace:GetDescendants()) do
                if obj.ClassName == "Water" then
                    pcall(function() obj:Destroy() end)
                end
            end
        end)
    end

    function WaterController:Start()
        -- Reaplica a cada 2 segundos para garantir
        Scheduler:BindToHeartbeat("WaterOverride", function(delta)
            -- Usamos controle de tempo simples
        end)
        task.spawn(function()
            while true do
                overrideWater()
                task.wait(2)
            end
        end)
    end
end

-- ========================
-- ENGINE: Hard Kill (Aniquilação Agressiva)
-- ========================
local HardKillEngine = {}
do
    local classSet = {}
    for _, className in ipairs(CONFIG.SCANNER.CLASS_BLACKLIST) do
        classSet[className] = true
    end

    -- Fila de prioridade para kills imediatos
    local immediateKillQueue = {}
    local function killInstance(obj: Instance)
        pcall(function()
            if obj and obj.Parent then
                obj:Destroy()
            end
        end)
    end

    local function processImmediateQueue()
        for _, obj in ipairs(immediateKillQueue) do
            killInstance(obj)
        end
        table.clear(immediateKillQueue)
    end

    -- Interceptação via eventos
    local function onDescendantAdded(descendant: Instance)
        if classSet[descendant.ClassName] then
            table.insert(immediateKillQueue, descendant)
        end
    end

    local function onAncestryChanged(descendant: Instance, parent: Instance?)
        if classSet[descendant.ClassName] then
            if parent then
                table.insert(immediateKillQueue, descendant)
            end
        end
    end

    local descendantAddedConn
    local ancestryChangedConn

    -- Scanner contínuo com batch processing
    local scanActive = true
    local function batchScan(batchSize: number)
        local descendants = workspace:GetDescendants()
        local index = 1
        while scanActive do
            local count = 0
            while index <= #descendants and count < batchSize do
                local obj = descendants[index]
                if obj and obj.Parent then -- ainda existe
                    if classSet[obj.ClassName] then
                        killInstance(obj)
                    end
                end
                index += 1
                count += 1
            end
            if index > #descendants then
                break
            end
            task.wait() -- cede para manter fps
        end
    end

    function HardKillEngine:Start()
        -- Conectar listeners
        descendantAddedConn = workspace.DescendantAdded:Connect(onDescendantAdded)
        ancestryChangedConn = workspace.AncestryChanged:Connect(onAncestryChanged)

        -- Processador de fila imediata via RenderStepped (máxima prioridade)
        Scheduler:BindToRenderStepped("ImmediateKill", processImmediateQueue)

        -- Determinar parâmetros baseados na plataforma
        local batchSize, scanInterval
        if Environment.IsMobile then
            batchSize = CONFIG.SCANNER.BATCH_SIZE_MOBILE
            scanInterval = CONFIG.SCANNER.SCAN_INTERVAL_MOBILE
        elseif Environment.IsConsole then
            batchSize = CONFIG.SCANNER.BATCH_SIZE_CONSOLE
            scanInterval = CONFIG.SCANNER.SCAN_INTERVAL_CONSOLE
        else
            batchSize = CONFIG.SCANNER.BATCH_SIZE_PC
            scanInterval = CONFIG.SCANNER.SCAN_INTERVAL_PC
        end

        -- Loop de scan contínuo em thread separada
        task.spawn(function()
            while true do
                task.wait(scanInterval)
                if not scanActive then break end
                batchScan(batchSize)
            end
        end)
    end

    function HardKillEngine:Stop()
        scanActive = false
        if descendantAddedConn then descendantAddedConn:Disconnect() end
        if ancestryChangedConn then ancestryChangedConn:Disconnect() end
    end
end

-- ========================
-- CONTROLLER: Conversão Visual Agressiva
-- ========================
local VisualConverter = {}
do
    local function convertVisuals()
        local parts = workspace:GetDescendants()
        for _, obj in ipairs(parts) do
            pcall(function()
                if obj:IsA("BasePart") then
                    -- Conversão de cor preta extrema para cinza claro
                    if obj.Color == Color3.new(0, 0, 0) then
                        obj.Color = CONFIG.VISUAL_CONVERSION.BLACK_TO_COLOR
                    end
                    -- Conversão Neon -> Ice (preservando cor)
                    if obj.Material == Enum.Material.Neon and CONFIG.VISUAL_CONVERSION.NEON_TO_ICE then
                        local originalColor = obj.Color
                        obj.Material = Enum.Material.Ice
                        obj.Color = originalColor
                    end
                elseif obj:IsA("Texture") or obj:IsA("Decal") then
                    -- Nitidez máxima adaptativa
                    if obj:IsA("Texture") then
                        obj.StudsPerTileU = CONFIG.VISUAL_CONVERSION.TEXTURE_SCALE
                        obj.StudsPerTileV = CONFIG.VISUAL_CONVERSION.TEXTURE_SCALE
                    end
                end
            end)
        end
    end

    function VisualConverter:Start()
        -- Executa a conversão periodicamente, menos frequente
        local interval = Environment.IsMobile and 10 or 5
        task.spawn(function()
            while true do
                task.wait(interval)
                convertVisuals()
            end
        end)
    end
end

-- ========================
--- PROFILER & ADAPTIVE CONTROLLER (Auto-Perfil)
-- ========================
local Profiler = {}
do
    local fpsSamples = {}
    local avgFps = 60
    local adaptFactor = 1.0  -- 1.0 = normal, <1 reduz intensidade, >1 aumenta

    local function updateFps(delta: number)
        if delta > 0 then
            local fps = 1 / delta
            table.insert(fpsSamples, fps)
            if #fpsSamples > 30 then
                table.remove(fpsSamples, 1)
            end
            local sum = 0
            for _, v in ipairs(fpsSamples) do
                sum += v
            end
            avgFps = sum / #fpsSamples
        end
    end

    local function adaptIntensity()
        if avgFps < CONFIG.PROFILER.LOW_FPS_THRESHOLD then
            adaptFactor = math.max(adaptFactor - CONFIG.PROFILER.ADAPT_STEP, 0.3)  -- reduz agressividade
        elseif avgFps > CONFIG.PROFILER.HIGH_FPS_THRESHOLD then
            adaptFactor = math.min(adaptFactor + CONFIG.PROFILER.ADAPT_STEP, 2.0)  -- pode aumentar
        end
        -- Ajuste dinâmico do intervalo de scan (ainda não implementado dinamicamente, mas podemos expor)
    end

    function Profiler:Start()
        Scheduler:BindToHeartbeat("FpsMonitor", function(delta: number)
            updateFps(delta)
            adaptIntensity()
        end)
    end

    function Profiler:GetAdaptiveScale()
        return adaptFactor
    end
end

-- ========================
-- WATCHDOG & AUTO-REPAIR
-- ========================
local Watchdog = {}
do
    local restartSignal = false
    function Watchdog:Start(coreFunction: () -> ())
        task.spawn(function()
            while true do
                local success, err = pcall(coreFunction)
                if not success then
                    warn("[Watchdog] Critical failure:", err, "Restarting core in 2s...")
                    restartSignal = true
                    task.wait(2)
                    -- Reiniciar loops principais será feito via novas chamadas de Start
                else
                    restartSignal = false
                end
                task.wait(1)
            end
        end)
    end
    function Watchdog:IsRestarting()
        return restartSignal
    end
end

-- ========================
-- INICIALIZAÇÃO PRINCIPAL
-- ========================
local function Main()
    -- Operações iniciais seguras
    print("=== ULTRA AGGRESSIVE RENDER DOMINANCE ENGINE ===")
    print("Platform:", Environment.Platform, "| Executor?", Environment.ExecutorDetected)
    
    -- Iniciar todos os subsistemas
    LightingController:Start()
    HardKillEngine:Start()
    WaterController:Start()
    VisualConverter:Start()
    Profiler:Start()

    print("Engine fully operational.")
end

-- Ativação com proteção total
Scheduler:Spawn(Main)

-- WATCHDOG GLOBAL: monitora a thread principal
Watchdog:Start(Main)

-- Limpeza ao destruir o script
script.AncestoryChanged:Connect(function(_, parent)
    if not parent then
        Scheduler:DestroyAll()
        HardKillEngine:Stop()
    end
end)

-- Garantir que o script não seja desativado por erros fatais
return {} 
