-- src/shared/oceanConfig.module.lua
local OceanConfig = {}

-- Visual
OceanConfig.BaseColor = Color3.fromRGB(6,18,40)
OceanConfig.SurfaceTint = Color3.fromRGB(170,190,220)
OceanConfig.Transparency = 0.15
OceanConfig.SpecularIntensity = 0.35
OceanConfig.ReflectionIntensity = 0.6
OceanConfig.ReflectionBlur = 0.45
OceanConfig.Glossiness = 0.45
OceanConfig.FresnelColor = Color3.fromRGB(40,60,100)
OceanConfig.Emissive = 0.02

-- Wave / motion
OceanConfig.NormalMapScale = 0.8
OceanConfig.NormalMapTiling = Vector2.new(3,3)
OceanConfig.WaveAmplitude = 0.4
OceanConfig.WaveLength = 30
OceanConfig.WaveSpeed = 0.6
OceanConfig.Choppiness = 0.25
OceanConfig.SecondaryWaves = {
    amplitude = 0.08,
    length = 8,
    speed = 1.4
}
OceanConfig.DirectionalBias = Vector2.new(0.6,0.4)

-- Shore / foam
OceanConfig.FoamIntensity = 0.6
OceanConfig.FoamThreshold = 0.35
OceanConfig.FoamTextureScale = 2.5
OceanConfig.FoamFadeDistance = 12
OceanConfig.ShoreBlend = 0.85
OceanConfig.FoamColor = Color3.fromRGB(220,230,240)

-- Caustics & underwater
OceanConfig.CausticsIntensity = 0.08
OceanConfig.CausticsSpeed = 0.8
OceanConfig.CausticsScale = 6.0
OceanConfig.UnderwaterTint = Color3.fromRGB(8,22,44)
OceanConfig.UnderwaterFogDensity = 0.04
OceanConfig.SubmergeTransitionTime = 0.6

-- Lighting / moon
OceanConfig.MoonReflectionStrength = 0.9
OceanConfig.MoonSpecularBoost = 1.2
-- MoonDirection should be updated at runtime by client script reading moon model
OceanConfig.MoonDirection = Vector3.new(0,1,0)

-- Audio
OceanConfig.AmbientLoopId = "rbxassetid://123456789"
OceanConfig.UnderwaterLoopId = "rbxassetid://234567890"
OceanConfig.SfxVolumeGlobal = 0.6
OceanConfig.SfxVolumeWaves = 0.45

-- Performance / LOD
OceanConfig.LOD = {
    distance0 = 150,
    distance1 = 400,
    distance2 = 800
}
OceanConfig.ReflectionUpdateRate = 0.5
OceanConfig.MaxParticles = 200
OceanConfig.DisableEffectsOnLowEnd = true

-- Gameplay
OceanConfig.SwimSpeedMultiplier = 0.85
OceanConfig.DrownTime = 120
OceanConfig.BuoyancyForce = 18
OceanConfig.BoatWaveImpactScale = 0.7

return OceanConfig
