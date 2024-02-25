
//
//  Tessellation Functions
//  Most as or adapted from, and credit to, https://nedmakesgames.medium.com/mastering-tessellation-shaders-and-their-many-uses-in-unity-9caeb760150e
//

// Clip space range
#if defined (SHADER_API_GLCORE)
#define FAR_CLIP_VALUE 0
#else
#define FAR_CLIP_VALUE 1
#endif

// Clip tolerances
#define BACKFACE_CLIP_TOLERANCE -0.05
#define FRUSTUM_CLIP_TOLERANCE   0.5

#define BARYCENTRIC_INTERPOLATE(fieldName) \
		patch[0].fieldName * barycentricCoordinates.x + \
		patch[1].fieldName * barycentricCoordinates.y + \
		patch[2].fieldName * barycentricCoordinates.z

#define TERRAIN_TEX_BLEND_FREQUENCY 0.2
#define TERRAIN_TEX_BLEND_OFFSET    0.4
#define PARALLAX_SHARPENING_FACTOR 0.85

#define HULL_SHADER_ATTRIBUTES                          \
    [domain("tri")]                                     \
    [outputcontrolpoints(3)]                            \
    [outputtopology("triangle_cw")]                     \
    [patchconstantfunc("PatchConstantFunction")]        \
    [partitioning("fractional_odd")]                    

// True if point is outside bounds defined by lower and higher
bool IsOutOfBounds(float3 p, float3 lower, float3 higher)
{
    return p.x < lower.x || p.x > higher.x || p.y < lower.y || p.y > higher.y || p.z < lower.z || p.z > higher.z;
}

// True if vertex is outside of camera frustum
// Inputs a clip space position
bool IsPointOutOfFrustum(float4 pos)
{
    float3 culling = pos.xyz;
    float w = pos.w + FRUSTUM_CLIP_TOLERANCE;
    // UNITY_RAW_FAR_CLIP_VALUE is either 0 or 1, depending on graphics API
    // Most use 0, however OpenGL uses 1
    float3 lowerBounds = float3(-w, -w, -w * FAR_CLIP_VALUE);
    float3 higherBounds = float3(w, w, w);
    return IsOutOfBounds(culling, lowerBounds, higherBounds);
}

// Does the triangle normal face the camera position?
bool ShouldBackFaceCull(float3 nrm1, float3 nrm2, float3 nrm3, float3 w1, float3 w2, float3 w3)
{
    float3 faceNormal = (nrm1 + nrm2 + nrm3) * 0.333f;
    float3 faceWorldPos = (w1 + w2 + w2) * 0.333f;
    return dot(faceNormal, normalize(_WorldSpaceCameraPos - faceWorldPos)) < BACKFACE_CLIP_TOLERANCE;
}

// True if should be clipped by frustum or winding cull
// Inputs are clip space positions, world space normals, world space positions
bool ShouldClipPatch(float4 cp0, float4 cp1, float4 cp2, float3 n0, float3 n1, float3 n2, float3 wp0, float3 wp1, float3 wp2)
{
    bool allOutside = IsPointOutOfFrustum(cp0) && IsPointOutOfFrustum(cp1) && IsPointOutOfFrustum(cp2);
    return allOutside || ShouldBackFaceCull(n0, n1, n2, wp0, wp1, wp2);
}

// Calculate factor from edge length
// Vector inputs are world space
float EdgeTessellationFactor(float scale, float bias, float3 p0World, float4 p0Clip, float3 p1World, float4 p1Clip)
{
    float factor = distance(p0Clip.xyz / p0Clip.w, p1Clip.xyz / p1Clip.w) * (float)_ScreenParams.y / scale;
    return max(1, factor * 0.5 + bias);
}

//
// Smoothing Functions
//

// Calculate Phong projection offset
float3 PhongProjectedPosition(float3 flatPositionWS, float3 cornerPositionWS, float3 normalWS)
{
    return flatPositionWS - dot(flatPositionWS - cornerPositionWS, normalWS) * normalWS;
}

// Apply Phong smoothing
float3 CalculatePhongPosition(float3 bary, float3 p0PositionWS, float3 p0NormalWS, float3 p1PositionWS, float3 p1NormalWS, float3 p2PositionWS, float3 p2NormalWS)
{
    float3 flatPositionWS = bary.x * p0PositionWS + bary.y * p1PositionWS + bary.z * p2PositionWS;
    float3 smoothedPositionWS =
        bary.x * PhongProjectedPosition(flatPositionWS, p0PositionWS, p0NormalWS) +
        bary.y * PhongProjectedPosition(flatPositionWS, p1PositionWS, p1NormalWS) +
        bary.z * PhongProjectedPosition(flatPositionWS, p2PositionWS, p2NormalWS);
    return lerp(flatPositionWS, smoothedPositionWS, 0.333);
}

#define CALCULATE_VERTEX_DISPLACEMENT                                                                                                                         \
    float4 displacement = SampleBiplanarTextureLOD(_DisplacementMap, params, worldUVsLevel0, worldUVsLevel1, o.worldNormal, texLevelBlend);     \
    float3 displacedWorldPos = o.worldPos + displacement.g * o.worldNormal * _DisplacementScale;

//
//  Biplanar Mapping Functions
//

struct VertexBiplanarParams
{
    float3 absWorldNormal;
    int3 ma;
    int3 mi;
    int3 me;
    float blend;
};

struct PixelBiplanarParams
{
    float3 absWorldNormal;
    float3 dpdx0;
    float3 dpdy0;
    float3 dpdx1;
    float3 dpdy1;
    int3 ma;
    int3 mi;
    int3 me;
    float blend;
};

float3 SampleNormal(sampler2D tex, float2 uv)
{
    return tex2D(tex, uv) * 2 - 1;
}

float3 ToNormal(float4 tex)
{
    return tex.rgb * 2.0f - 1.0f;
}

float3 CombineNormals(float3 n1, float3 n2)
{
    return normalize(float3(n1.xy + n2.xy, n1.z * n2.z));
}

#define BIPLANAR_BLEND_FACTOR 4.0f

#define GET_VERTEX_BIPLANAR_PARAMS(params, worldPos, normal)                            \
    params.absWorldNormal = abs(normal);                                                \
    params.ma = (params.absWorldNormal.x > params.absWorldNormal.y && params.absWorldNormal.x > params.absWorldNormal.z) ? int3(0, 1, 2) : (params.absWorldNormal.y > params.absWorldNormal.z) ? int3(1, 2, 0) : int3(2, 0, 1);   \
    params.mi = (params.absWorldNormal.x < params.absWorldNormal.y && params.absWorldNormal.x < params.absWorldNormal.z) ? int3(0, 1, 2) : (params.absWorldNormal.y < params.absWorldNormal.z) ? int3(1, 2, 0) : int3(2, 0, 1);   \
    params.me = 3 - params.mi - params.ma;                                              \
    params.blend = BIPLANAR_BLEND_FACTOR;

// We can't calculate ddx and ddy for worldUVsLevel0 and worldUVsLevel1 because it results in a 1 pixel band around the texture transition
// So we instead calculate ddx and ddy for the original world coords and transform them the same way we do with the world coords themselves
// Which visually is slightly inaccurate but i'll take a little blurring over artifacting

// (ddx(worldPos0) / distFromTerrain) * (_Tiling / scale0) * distFromTerrain

// Get pixel shader biplanar params, and transform partial derivs by the world coord transform
#define GET_PIXEL_BIPLANAR_PARAMS(params, worldPos0, worldPos1, normal, scale0, scale1, distFromTerrain)                                 \
    params.absWorldNormal = abs(normal);                                                                    \
    params.dpdx0 = (ddx(worldPos0) / distFromTerrain) * (_Tiling / scale0) * distFromTerrain;                                                      \
    params.dpdy0 = (ddy(worldPos0) / distFromTerrain) * (_Tiling / scale0) * distFromTerrain;                                                      \
    params.dpdx1 = (ddx(worldPos0) / distFromTerrain) * (_Tiling / scale1) * distFromTerrain;                                                      \
    params.dpdy1 = (ddy(worldPos0) / distFromTerrain) * (_Tiling / scale1) * distFromTerrain;                                                      \
    params.ma = (params.absWorldNormal.x > params.absWorldNormal.y && params.absWorldNormal.x > params.absWorldNormal.z) ? int3(0, 1, 2) : (params.absWorldNormal.y > params.absWorldNormal.z) ? int3(1, 2, 0) : int3(2, 0, 1);   \
    params.mi = (params.absWorldNormal.x < params.absWorldNormal.y && params.absWorldNormal.x < params.absWorldNormal.z) ? int3(0, 1, 2) : (params.absWorldNormal.y < params.absWorldNormal.z) ? int3(1, 2, 0) : int3(2, 0, 1);   \
    params.me = 3 - params.mi - params.ma;                                                                  \
    params.blend = BIPLANAR_BLEND_FACTOR;

#define TEX2D_GRAD_COORDS_LEVEL0(axis, params, coords) float2(coords[axis.y], coords[axis.z]), float2(params.dpdx0[axis.y], params.dpdx0[axis.z]), float2(params.dpdy0[axis.y], params.dpdy0[axis.z])
#define TEX2D_GRAD_COORDS_LEVEL1(axis, params, coords) float2(coords[axis.y], coords[axis.z]), float2(params.dpdx1[axis.y], params.dpdx1[axis.z]), float2(params.dpdy1[axis.y], params.dpdy1[axis.z])

#define TEX2D_LOD_COORDS(axis, coords, level) float4(coords[axis.y], coords[axis.z], 0, level)

// Get the transformed world space coords for texture levels 0 and 1
// that define the zoom levels for the terrain to reduce tiling

// exponent * 0.5 is the same as pow(2, floorLogDistance - 1) to select the previous zoom level. It just avoids the use of pow twice
#define DO_WORLD_UV_CALCULATIONS(terrainDistance, worldPos)                                                                             \
    float logDistance = log2(terrainDistance * TERRAIN_TEX_BLEND_FREQUENCY + TERRAIN_TEX_BLEND_OFFSET);                                 \
    float floorLogDistance = floor(logDistance);                                                                                        \
    float exponent = pow(2, floorLogDistance);                                                                                          \
    float texScale0 = exponent * 0.5;                                                                                                   \
    float texScale1 = exponent;                                                                                                         \
    float3 worldUVsLevel0 = (worldPos - _TerrainShaderOffset) * _Tiling / texScale0;                                                    \
    float3 worldUVsLevel1 = (worldPos - _TerrainShaderOffset) * _Tiling / texScale1;                                                    \
    float texLevelBlend = saturate((logDistance - floorLogDistance) * 1);

float GetMipLevel(float3 texCoord, float3 dpdx, float3 dpdy)
{
    float md = max(dot(dpdx, dpdx), dot(dpdy, dpdy));
    return 0.5f * log2(md);
}

float4 SampleBiplanarTexture(sampler2D tex, PixelBiplanarParams params, float3 worldPos0, float3 worldPos1, float3 worldNormal, float blend)
{
    // Sample zoom level 0
    float4 x0 = tex2Dgrad(tex, TEX2D_GRAD_COORDS_LEVEL0(params.ma, params, worldPos0));
    float4 y0 = tex2Dgrad(tex, TEX2D_GRAD_COORDS_LEVEL0(params.me, params, worldPos0));
    
    // Sample zoom level 1
    float4 x1 = tex2Dgrad(tex, TEX2D_GRAD_COORDS_LEVEL1(params.ma, params, worldPos1));
    float4 y1 = tex2Dgrad(tex, TEX2D_GRAD_COORDS_LEVEL1(params.me, params, worldPos1));
    
    // Blend zoom levels
    float4 x = lerp(x0, x1, blend);
    float4 y = lerp(y0, y1, blend);
    
    // Compute blend weights
    float2 w = float2(params.absWorldNormal[params.ma.x], params.absWorldNormal[params.me.x]);
    
    // Blend
    w = saturate(w * 2.365744f - 1.365744f);
    w = pow(w, params.blend * 0.125f);
    
    // Blend
    return (x * w.x + y * w.y) / (w.x + w.y);
}

float4 SampleBiplanarTextureLOD(sampler2D tex, VertexBiplanarParams params, float3 worldPos0, float3 worldPos1, float3 worldNormal, float blend)
{
    // Project and fetch
    float4 x0 = tex2Dlod(tex, TEX2D_LOD_COORDS(params.ma, worldPos0, 0));
    float4 y0 = tex2Dlod(tex, TEX2D_LOD_COORDS(params.me, worldPos0, 0));
    
    float4 x1 = tex2Dlod(tex, TEX2D_LOD_COORDS(params.ma, worldPos1, 0));
    float4 y1 = tex2Dlod(tex, TEX2D_LOD_COORDS(params.me, worldPos1, 0));
    
    float4 x = lerp(x0, x1, blend);
    float4 y = lerp(y0, y1, blend);
    
    // Compute blend weights
    float2 w = float2(params.absWorldNormal[params.ma.x], params.absWorldNormal[params.me.x]);
    
    // Blend
    w = saturate(w * 2.365744f - 1.365744f);
    w = pow(w, params.blend * 0.125f);
    
    // Blend
    return (x * w.x + y * w.y) / (w.x + w.y);
}

float3 SampleBiplanarNormal(sampler2D tex, PixelBiplanarParams params, float3 worldPos0, float3 worldPos1, float3 worldNormal, float blend)
{
    // Sample zoom level 0
    float3 x0 = UnpackNormal(tex2Dgrad(tex, TEX2D_GRAD_COORDS_LEVEL0(params.ma, params, worldPos0)));
    float3 y0 = UnpackNormal(tex2Dgrad(tex, TEX2D_GRAD_COORDS_LEVEL1(params.me, params, worldPos0)));
    
    // Sample zoom level 1 
    float3 x1 = UnpackNormal(tex2Dgrad(tex, TEX2D_GRAD_COORDS_LEVEL0(params.ma, params, worldPos1)));
    float3 y1 = UnpackNormal(tex2Dgrad(tex, TEX2D_GRAD_COORDS_LEVEL1(params.me, params, worldPos1)));
    
    // Blend zoom levels
    float3 x = lerp(x0, x1, blend) * 2;
    float3 y = lerp(y0, y1, blend) * 2;
    
    // Don't include this in the final build!
    x.g *= -1;
    y.g *= -1;
    
    // Swizzle axes depending on plane
    x = normalize(float3(x.y + worldNormal[params.ma.z], x.x + worldNormal[params.ma.y], worldNormal[params.ma.x]));
    y = normalize(float3(y.y + worldNormal[params.me.z], y.x + worldNormal[params.me.y], worldNormal[params.me.x]));
    
    // Swizzle back to world space
    x = float3(x[params.ma.z], x[params.ma.y], x[params.ma.x]);
    y = float3(y[params.me.z], y[params.me.y], y[params.me.x]);
    
    // Compute blend weights
    float2 w = float2(params.absWorldNormal[params.ma.x], params.absWorldNormal[params.me.x]);
    
    // Blend
    w = saturate(w * 2.365744f - 1.365744f);
    w = pow(w, params.blend * 0.125f);
    
    float3 result = (x * w.x + y * w.y) / (w.x + w.y);
    
    return result;
}

//
//  Ingame Calcs
//

// Get Blend Factors
//float GetBlendFactor()

//
//  Lighting Functions
//

#define GET_SHADOW LIGHT_ATTENUATION(i)

float FresnelEffect(float3 worldNormal, float3 viewDir, float power)
{
    return pow((1.0 - saturate(dot(worldNormal, viewDir))), power);
}

float3 CalculateLighting(float4 col, float3 worldNormal, float3 viewDir, float shadow)
{
	// Main light
    float NdotL = max(0, dot(worldNormal, _WorldSpaceLightPos0));
    float3 H = normalize(_WorldSpaceLightPos0 + viewDir);
    float NdotH = saturate(dot(worldNormal, H));

	// Fresnel reflections
    float3 reflDir = reflect(-viewDir, worldNormal);
    float4 reflSkyData = UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, reflDir);
    float3 reflColor = DecodeHDR(reflSkyData, unity_SpecCube0_HDR);
    float fresnel = FresnelEffect(worldNormal, viewDir, _FresnelPower);

	// Fresnel refraction - Unused
    float3 refrDir = refract(-viewDir, worldNormal, eta);
    float4 refrSkyData = UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, refrDir);
    float3 refrColor = DecodeHDR(refrSkyData, unity_SpecCube0_HDR);

    float spec = pow(NdotH, _SpecularPower) * _LightColor0.rgb * _SpecularIntensity * col.a;

    float3 ambient = UNITY_LIGHTMODEL_AMBIENT.rgb * col.rgb;
    float3 diffuse = _LightColor0.rgb * col.rgb * NdotL;
    float3 specular = spec * _LightColor0.rgb;
    float3 reflection = fresnel * reflColor * col.a * _EnvironmentMapFactor + (1 - fresnel) * refrColor * _RefractionIntensity; // For refraction

    return ambient + diffuse + specular + reflection;
}