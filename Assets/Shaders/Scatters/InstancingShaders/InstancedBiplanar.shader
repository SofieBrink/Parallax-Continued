﻿//
//  InstancedBiplanar - Basic instancing shader with an albedo and normal
//

Shader "Custom/ParallaxInstancedBiplanar"
{
    Properties
    {
        // Texture params
        [Space(10)]
        [Header(Texture Parameters)]
        [Space(10)]
        _MainTex("Main Tex", 2D) = "white" {}
        _BumpMap("Bump Map", 2D) = "bump" {}
        _Tiling("Tiling", Range(0, 100)) = 0.03

        // Lighting params
        [Space(10)]
        [Header(Lighting Parameters)]
        [Space(10)]
        _Color("Color", COLOR) = (1, 1, 1)
        _BumpScale("Bump Scale", Range(0, 2)) = 1
        [PowerSlider(3.0)] _SpecularPower("Specular Power", Range(0.001, 1000)) = 1
        _SpecularIntensity("Specular Intensity", Range(0.0, 5.0)) = 1
        _FresnelPower("Fresnel Power", Range(0.001, 20)) = 1
        _FresnelColor("Fresnel Color", COLOR) = (0, 0, 0)
        _EnvironmentMapFactor("Environment Map Factor", Range(0.0, 2.0)) = 1
        _Hapke("Hapke", Range(0.001, 2)) = 1

        _PlanetOrigin("po", vector) = (0, 1, 0)
    }
    SubShader
    {
        // We can override the rendertype tag at runtime using Material.SetOverrideTag()
        Tags {"RenderType" = "Opaque"}
        Cull [_CullMode]

        //
        //  Forward Base Pass
        //

        Pass
        {
            Tags { "LightMode" = "ForwardBase" }
            CGPROGRAM

            // Skip these, KSP won't use them
            #pragma skip_variants POINT_COOKIE LIGHTMAP_ON DIRLIGHTMAP_COMBINED DYNAMICLIGHTMAP_ON LIGHTMAP_SHADOW_MIXING VERTEXLIGHT_ON

            // Shader stages
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fwdbase

            // Unity includes
            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "AutoLight.cginc"

            // Parallax includes
            #include "ParallaxScatterStructs.cginc"
            #include "ParallaxScatterParams.cginc"
            #include "../ScatterStructs.cginc"
            #include "../../Includes/ParallaxGlobalFunctions.cginc"
            #include "ParallaxScatterUtils.cginc"
            #include "../../Includes/BiplanarFunctions.cginc"

            // The necessary structs
            DECLARE_INSTANCING_DATA
            PARALLAX_FORWARDBASE_STRUCT_APPDATA
            PARALLAX_FORWARDBASE_STRUCT_V2F
          
            // Extra functions not provided by scatter params by default
            float _Tiling;

            //
            // Vertex Shader 
            //

            v2f vert(appdata i, uint instanceID : SV_InstanceID) 
            {
                v2f o;

                float4x4 objectToWorld = INSTANCE_DATA.objectToWorld;
                DECODE_INSTANCE_DATA(objectToWorld, color)

                o.worldNormal = mul(objectToWorld, float4(i.normal, 0)).xyz;
                o.worldTangent = mul(objectToWorld, float4(i.tangent.xyz, 0));
                o.worldBinormal = cross(o.worldTangent, o.worldNormal) * i.tangent.w;

                float3 worldPos = mul(objectToWorld, i.vertex);
                float3 planetNormal = CalculatePlanetNormal(PLANET_NORMAL_INPUT);
                PROCESS_WIND(i)

                o.worldPos = worldPos;
                o.uv = i.uv;
                o.color = color;

                o.planetNormal = planetNormal;
                o.viewDir = _WorldSpaceCameraPos - worldPos;
                o.pos = UnityWorldToClipPos(worldPos);

                TRANSFER_VERTEX_TO_FRAGMENT(o);

                return o;
            }

            //
            //  Fragment Shader
            //

            fixed4 frag(PIXEL_SHADER_INPUT(v2f)) : SV_Target
            {   
                i.worldNormal = normalize(i.worldNormal);

                // Get terrain distance for texture blending
                float terrainDistance = length(i.viewDir);
                DO_WORLD_UV_CALCULATIONS(terrainDistance * 0.2, i.worldPos)

                // Get biplanar params for texture sampling
                PixelBiplanarParams params;
                GET_PIXEL_BIPLANAR_PARAMS(params, i.worldPos, worldUVsLevel0, worldUVsLevel1, i.worldNormal, texScale0, texScale1);

                float4 mainTex = SampleBiplanarTexture(_MainTex, params, worldUVsLevel0, worldUVsLevel1, i.worldNormal, texLevelBlend);
                
                mainTex.rgb *= _Color;
                mainTex.rgb *= i.color;

                // Get specular from MainTex or, if ALTERNATE_SPECULAR_TEXTURE is defined, use the specular texture
                GET_SPECULAR(mainTex, i.uv * _MainTex_ST);
                
                float3 viewDir = normalize(i.viewDir);
                float3 lightDir = _WorldSpaceLightPos0;
                
                float3 worldNormal = SampleBiplanarNormal(_BumpMap, params, worldUVsLevel0, worldUVsLevel1, i.worldNormal, texLevelBlend);

                // Calculate lighting from core params, plus potential additional params (worldpos required for subsurface scattering)
                float3 result = CalculateLighting(BASIC_LIGHTING_PARAMS ADDITIONAL_LIGHTING_PARAMS );

                return float4(result, mainTex.a);
            }

            ENDCG
        }

        //
        //  Shadow Caster Pass
        //

        Pass
        {
            Tags { "LightMode" = "ShadowCaster" }
            CGPROGRAM

            #pragma skip_variants POINT_COOKIE LIGHTMAP_ON DIRLIGHTMAP_COMBINED DYNAMICLIGHTMAP_ON LIGHTMAP_SHADOW_MIXING VERTEXLIGHT_ON

            #define PARALLAX_SHADOW_CASTER_PASS

            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_shadowcaster
        
            // Unity includes
            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "AutoLight.cginc"
        
            // Includes
            #include "ParallaxScatterStructs.cginc"
            #include "ParallaxScatterParams.cginc"
            #include "../ScatterStructs.cginc"
            #include "../../Includes/ParallaxGlobalFunctions.cginc"
            #include "ParallaxScatterUtils.cginc"
            #include "../../Includes/BiplanarFunctions.cginc"
        
            // Necessary structs
            DECLARE_INSTANCING_DATA
            PARALLAX_SHADOW_CASTER_STRUCT_APPDATA
            PARALLAX_SHADOW_CASTER_STRUCT_V2F
          
            v2f vert(appdata i, uint instanceID : SV_InstanceID)
            {
                v2f o;
        
                float4x4 objectToWorld = INSTANCE_DATA.objectToWorld;
                DECODE_INSTANCE_DATA_SHADOW(objectToWorld)
        
                float3 worldNormal = mul(objectToWorld, float4(i.normal, 0)).xyz;
                
                float3 worldPos = mul(objectToWorld, i.vertex);

                o.uv = i.uv;

                o.pos = UnityWorldToClipPos(worldPos);
                o.pos = UnityApplyLinearShadowBias(o.pos);
        
                return o;
            }
        
            void frag(PIXEL_SHADER_INPUT(v2f))
            {   

            }
        
            ENDCG
        }

        //
        //  ForwardAdd Pass
        //

        Pass
        {
            Tags { "LightMode" = "ForwardAdd" }
            Blend SrcAlpha One
            //BlendOp Add
            CGPROGRAM

            #pragma skip_variants POINT_COOKIE LIGHTMAP_ON DIRLIGHTMAP_COMBINED DYNAMICLIGHTMAP_ON LIGHTMAP_SHADOW_MIXING VERTEXLIGHT_ON

            // Shader stages
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fwdadd_fullshadows

            // Unity includes
            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "AutoLight.cginc"

            // Parallax includes
            #include "ParallaxScatterStructs.cginc"
            #include "ParallaxScatterParams.cginc"
            #include "../ScatterStructs.cginc"
            #include "../../Includes/ParallaxGlobalFunctions.cginc"
            #include "ParallaxScatterUtils.cginc"
            #include "../../Includes/BiplanarFunctions.cginc"

            // The necessary structs
            DECLARE_INSTANCING_DATA
            PARALLAX_FORWARDADD_STRUCT_APPDATA
            PARALLAX_FORWARDADD_STRUCT_V2F
          
            // Extra functions not provided by scatter params by default
            float _Tiling;

            //
            // Vertex Shader 
            //

            v2f vert(appdata i, uint instanceID : SV_InstanceID) 
            {
                v2f o;

                float4x4 objectToWorld = INSTANCE_DATA.objectToWorld;
                DECODE_INSTANCE_DATA(objectToWorld, color)

                o.worldNormal = mul(objectToWorld, float4(i.normal, 0)).xyz;
                o.worldTangent = mul(objectToWorld, float4(i.tangent.xyz, 0));
                o.worldBinormal = cross(o.worldTangent, o.worldNormal) * i.tangent.w;

                float3 worldPos = mul(objectToWorld, i.vertex);
                float3 planetNormal = CalculatePlanetNormal(PLANET_NORMAL_INPUT);

                o.worldPos = worldPos;
                o.uv = i.uv;
                o.color = color;

                o.planetNormal = planetNormal;
                o.viewDir = _WorldSpaceCameraPos - worldPos;
                o.lightDir = _WorldSpaceLightPos0 - worldPos;
                o.pos = UnityWorldToClipPos(worldPos);

                PARALLAX_TRANSFER_VERTEX_TO_FRAGMENT(o);

                return o;
            }

            //
            //  Fragment Shader
            //

            fixed4 frag(PIXEL_SHADER_INPUT(v2f)) : SV_Target
            {   
                i.worldNormal = normalize(i.worldNormal);

                // Get terrain distance for texture blending
                float terrainDistance = length(i.viewDir);
                DO_WORLD_UV_CALCULATIONS(terrainDistance * 0.2, i.worldPos)

                // Get biplanar params for texture sampling
                PixelBiplanarParams params;
                GET_PIXEL_BIPLANAR_PARAMS(params, i.worldPos, worldUVsLevel0, worldUVsLevel1, i.worldNormal, texScale0, texScale1);

                float4 mainTex = SampleBiplanarTexture(_MainTex, params, worldUVsLevel0, worldUVsLevel1, i.worldNormal, texLevelBlend);
                
                mainTex.rgb *= _Color;
                mainTex.rgb *= i.color;

                // Get specular from MainTex or, if ALTERNATE_SPECULAR_TEXTURE is defined, use the specular texture
                GET_SPECULAR(mainTex, i.uv * _MainTex_ST);
                
                float3 viewDir = normalize(i.viewDir);
                float3 lightDir = _WorldSpaceLightPos0;
                
                float3 worldNormal = normalize(SampleBiplanarNormal(_BumpMap, params, worldUVsLevel0, worldUVsLevel1, i.worldNormal, texLevelBlend));

                // Calculate lighting from core params, plus potential additional params (worldpos required for subsurface scattering)
                float atten = LIGHT_ATTENUATION(i);
                float3 result = CalculateLighting(BASIC_LIGHTING_PARAMS ADDITIONAL_LIGHTING_PARAMS );

                // Process any enabled debug options that affect the output color
                return float4(result, atten);
            }

            ENDCG
        }

        //
        //  Deferred Pass
        //

        Pass
        {
            Tags{ "LightMode" = "Deferred" }

            Stencil
			{
			    Ref 32
			    Comp Always
			    Pass Replace
			}

            CGPROGRAM

            #define PARALLAX_DEFERRED_PASS

            #pragma multi_compile _ UNITY_HDR_ON

            #pragma skip_variants POINT_COOKIE LIGHTMAP_ON DIRLIGHTMAP_COMBINED DYNAMICLIGHTMAP_ON LIGHTMAP_SHADOW_MIXING VERTEXLIGHT_ON

            // Shader stages
            #pragma vertex vert
            #pragma fragment frag

            // Unity includes
            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "AutoLight.cginc"
            #include "UnityPBSLighting.cginc"

            // Parallax includes
            #include "ParallaxScatterStructs.cginc"
            #include "ParallaxScatterParams.cginc"
            #include "../ScatterStructs.cginc"
            #include "../../Includes/ParallaxGlobalFunctions.cginc"
            #include "ParallaxScatterUtils.cginc"
            #include "../../Includes/BiplanarFunctions.cginc"

            // The necessary structs
            DECLARE_INSTANCING_DATA
            PARALLAX_FORWARDBASE_STRUCT_APPDATA
            PARALLAX_FORWARDBASE_STRUCT_V2F
          
            // Extra functions not provided by scatter params by default
            float _Tiling;

            //
            // Vertex Shader 
            //

            v2f vert(appdata i, uint instanceID : SV_InstanceID) 
            {
                v2f o;

                float4x4 objectToWorld = INSTANCE_DATA.objectToWorld;
                DECODE_INSTANCE_DATA(objectToWorld, color)

                o.worldNormal = mul(objectToWorld, float4(i.normal, 0)).xyz;
                o.worldTangent = mul(objectToWorld, float4(i.tangent.xyz, 0));
                o.worldBinormal = cross(o.worldTangent, o.worldNormal) * i.tangent.w;

                float3 worldPos = mul(objectToWorld, i.vertex);
                float3 planetNormal = CalculatePlanetNormal(PLANET_NORMAL_INPUT);

                o.worldPos = worldPos;
                o.uv = i.uv;
                o.color = color;

                o.planetNormal = planetNormal;
                o.viewDir = _WorldSpaceCameraPos - worldPos;
                o.pos = UnityWorldToClipPos(worldPos);

                TRANSFER_VERTEX_TO_FRAGMENT(o);

                return o;
            }

            //
            //  Fragment Shader
            //

            void frag(PIXEL_SHADER_INPUT(v2f), PARALLAX_DEFERRED_OUTPUT_BUFFERS)
            {   
                i.worldNormal = normalize(i.worldNormal);

                // Get terrain distance for texture blending
                float terrainDistance = length(i.viewDir);
                DO_WORLD_UV_CALCULATIONS(terrainDistance * 0.2, i.worldPos)

                // Get biplanar params for texture sampling
                PixelBiplanarParams params;
                GET_PIXEL_BIPLANAR_PARAMS(params, i.worldPos, worldUVsLevel0, worldUVsLevel1, i.worldNormal, texScale0, texScale1);

                float4 mainTex = SampleBiplanarTexture(_MainTex, params, worldUVsLevel0, worldUVsLevel1, i.worldNormal, texLevelBlend);
                
                mainTex.rgb *= _Color;
                mainTex.rgb *= i.color;

                // Get specular from MainTex or, if ALTERNATE_SPECULAR_TEXTURE is defined, use the specular texture
                GET_SPECULAR(mainTex, i.uv * _MainTex_ST);
                
                float3 viewDir = normalize(i.viewDir);
                float3 lightDir = _WorldSpaceLightPos0;
                
                float3 worldNormal = normalize(SampleBiplanarNormal(_BumpMap, params, worldUVsLevel0, worldUVsLevel1, i.worldNormal, texLevelBlend));
                float3 result = 0;
                
                // Deferred functions
                SurfaceOutputStandardSpecular surfaceInput = GetPBRStruct(mainTex, result, worldNormal.xyz, i.worldPos);
                UnityGI gi = GetUnityGI();
                UnityGIInput giInput = GetGIInput(i.worldPos, viewDir);
                LightingStandardSpecular_GI(surfaceInput, giInput, gi);
                
                OUTPUT_GBUFFERS(surfaceInput, gi)
                SET_OUT_SHADOWMASK(i)
            }

            ENDCG
        }
    }
}