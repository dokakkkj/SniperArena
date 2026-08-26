-- ============== CARREGAR MÓDULO ESP ==============
local ESPModule = loadstring(game:HttpGet("https://raw.githubusercontent.com/dokakkkj/M-duloESP/refs/heads/main/ModuloESP"))()

-- ============== VARIÁVEIS GLOBAIS ==============
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera
local LocalPlayer = game.Players.LocalPlayer
local Mouse = game.Players.LocalPlayer:GetMouse()

local Settings = {
    Enabled = true,
    FOVRadius = 180,
}

-- ============== FOV CIRCLE (GUI) ==============
local FOVGui = Instance.new("ScreenGui")
FOVGui.Name = "FOVCircleGui"
FOVGui.ResetOnSpawn = false
FOVGui.DisplayOrder = 9999
FOVGui.IgnoreGuiInset = true
FOVGui.Parent = game:GetService("CoreGui")

local FOVCircle = Instance.new("Frame")
FOVCircle.Name = "FOVCircle"
FOVCircle.Size = UDim2.new(0, Settings.FOVRadius * 2, 0, Settings.FOVRadius * 2)
FOVCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
FOVCircle.AnchorPoint = Vector2.new(0.5, 0.5)
FOVCircle.BackgroundColor3 = Color3.new(1, 1, 1)
FOVCircle.BackgroundTransparency = 1
FOVCircle.BorderSizePixel = 0
FOVCircle.Visible = true
FOVCircle.Parent = FOVGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = FOVCircle

local stroke = Instance.new("UIStroke")
stroke.Thickness = 1.5
stroke.Color = Color3.new(1, 1, 1)
stroke.Parent = FOVCircle

-- ============== TRACER ==============
local Tracer = Drawing.new("Line")
Tracer.Thickness = 1.5
Tracer.Color = Color3.fromRGB(255, 0, 0)
Tracer.Transparency = 0.7
Tracer.Visible = false

-- ============== SISTEMA SILENT AIM ==============
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EntityService = require(ReplicatedStorage.Remote.EntityService)
local ClientShootableComponent = require(ReplicatedStorage.Client.CombatController.ClientComponent.ClientShootableComponent)

local function GetEntityPosition(EntityModel)
    local TargetPart = EntityModel:FindFirstChild("HumanoidRootPart") or EntityModel:FindFirstChild("Head")
    if TargetPart and TargetPart:IsA("BasePart") then 
        return TargetPart, TargetPart.Position 
    end
    return nil, nil
end

local function IsInFOV(WorldPosition)
    if not Camera then return false, math.huge end
    local ScreenPos, OnScreen = Camera:WorldToViewportPoint(WorldPosition)
    if not OnScreen then return false, math.huge end
    local CenterPos = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local Distance = (Vector2.new(ScreenPos.X, ScreenPos.Y) - CenterPos).Magnitude
    return Distance <= Settings.FOVRadius, Distance
end

local function GetClosestEnemyInFOV()
    local LocalEntity = EntityService.GetLocalEntity()
    if not LocalEntity or not LocalEntity.World or not LocalEntity.World.EntitiesByTeam then return nil end
    
    local ClosestTarget = nil
    local ClosestDistance = math.huge
    
    for _, TeamDict in pairs(LocalEntity.World.EntitiesByTeam) do
        local Items = TeamDict._items or TeamDict
        for _, Entity in pairs(Items) do
            if not EntityService.IsLocalEntity(Entity) and Entity:IsAlive() then
                local Inst = Entity.Instance
                local Character = (Inst and Inst:IsA("Player")) and Inst.Character or Inst
                if Character then
                    local Humanoid = Character:FindFirstChildOfClass("Humanoid")
                    if Humanoid and Humanoid.Health > 0 then
                        local Part, Position = GetEntityPosition(Character)
                        if Position then
                            local InFOV, Distance = IsInFOV(Position)
                            if InFOV and Distance < ClosestDistance then
                                ClosestTarget = { Part = Part, Position = Position }
                                ClosestDistance = Distance
                            end
                        end
                    end
                end
            end
        end
    end
    
    return ClosestTarget
end

local SilentTarget = nil

local OrigLocalShoot = ClientShootableComponent.LocalShoot
local OrigOriginFn, OrigTargetFn

for i = 1, 20 do
    local success, val = pcall(debug.getupvalue, OrigLocalShoot, i)
    if success and type(val) == "function" then
        local testSuccess, ret1, ret2, ret3 = pcall(val)
        if testSuccess then
            if typeof(ret1) == "CFrame" and typeof(ret3) == "table" then
                OrigOriginFn = val
            elseif typeof(ret1) == "Vector3" and typeof(ret2) == "Instance" then
                OrigTargetFn = val
            end
        end
    end
end

if OrigOriginFn then
    local OldOriginFn
    OldOriginFn = hookfunction(OrigOriginFn, function(...)
        local cf, pos, meta = OldOriginFn(...)
        if SilentTarget and Settings.Enabled then
            return CFrame.lookAt(cf.Position, SilentTarget.Position), pos, meta
        end
        return cf, pos, meta
    end)
end

if OrigTargetFn then
    local OldTargetFn
    OldTargetFn = hookfunction(OrigTargetFn, function(...)
        if SilentTarget and Settings.Enabled then
            return SilentTarget.Position, SilentTarget.Part
        end
        return OldTargetFn(...)
    end)
end

local OldLocalShoot
OldLocalShoot = hookfunction(ClientShootableComponent.LocalShoot, function(Self, ...)
    if Settings.Enabled then
        SilentTarget = GetClosestEnemyInFOV()
    end
    local Result = OldLocalShoot(Self, ...)
    SilentTarget = nil
    return Result
end)

-- ============== ATUALIZAÇÃO DO FOV E TRACER ==============
local hue = 0

RunService.RenderStepped:Connect(function()
    FOVCircle.Visible = Settings.Enabled
    FOVCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
    FOVCircle.Size = UDim2.new(0, Settings.FOVRadius * 2, 0, Settings.FOVRadius * 2)
    
    hue = (hue + 0.005) % 1
    stroke.Color = Color3.fromHSV(hue, 1, 1)
    
    if Settings.Enabled then
        local target = GetClosestEnemyInFOV()
        if target then
            local targetScreenPos, onScreen = Camera:WorldToViewportPoint(target.Position)
            if onScreen then
                Tracer.Visible = true
                local centerScreen = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
                Tracer.From = centerScreen
                Tracer.To = Vector2.new(targetScreenPos.X, targetScreenPos.Y)
            else
                Tracer.Visible = false
            end
        else
            Tracer.Visible = false
        end
    else
        Tracer.Visible = false
    end
end)

-- ============== CONTROLES ==============
print("🔥 Silent Aim carregado!")
print("🎯 FOV centralizado e Tracer ativo!")
print("👁️ ESP Module carregado com sucesso!")
print("\n📌 Comandos do Silent Aim:")
print("   /silent on/off - Ligar/Desligar Silent Aim")
print("   /fov [valor] - Ajustar FOV (20-300)")
print("\n📌 Comandos do ESP:")
print("   ToggleTeamCheck(true/false) - Liga/Desliga cores por time")
print("   DebugTeams() - Mostra informações de debug")
print("   ReassignAllColors() - Reatribui todas as cores")

game:GetService("Players").LocalPlayer.Chatted:Connect(function(msg)
    if msg:lower():match("/silent") then
        if msg:lower():match("on") then
            Settings.Enabled = true
            print("✅ Silent Aim ATIVADO")
        elseif msg:lower():match("off") then
            Settings.Enabled = false
            print("❌ Silent Aim DESATIVADO")
        end
    elseif msg:lower():match("/fov") then
        local value = tonumber(msg:match("/fov%s+(%d+)"))
        if value and value >= 20 and value <= 300 then
            Settings.FOVRadius = value
            print("✅ FOV ajustado para: " .. value)
        else
            print("⚠️ Use: /fov [20-300]")
        end
    end
end)
