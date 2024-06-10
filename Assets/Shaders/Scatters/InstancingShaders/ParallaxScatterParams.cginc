﻿sampler2D _MainTex;
sampler2D _BumpMap;

// If altnerative specular texture is defined
sampler2D _SpecularTexture;

float2 _MainTex_ST;
float2 _BumpMap_ST;

float _BumpScale;
float3 _PlanetOrigin;
float3 _FresnelColor;
float3 _Color;

// Wind
sampler2D _WindMap;
float _WindScale;
float _WindHeightStart;
float _WindHeightFactor;
float _WindSpeed;

// AlphaCutoff
float _Cutoff;

// Subsurface
float _SubsurfaceNormalInfluence;
float _SubsurfacePower;
float _SubsurfaceIntensity;
float3 _SubsurfaceColor;