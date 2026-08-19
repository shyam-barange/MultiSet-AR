/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License.
For license details, visit www.multiset.ai.

Outline shader for Object Tracking meshes.
Uses RealityKit CustomMaterial geometry modifier + surface shader.
*/

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>

using namespace metal;

float hash2d(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

float noise2d(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash2d(i);
    float b = hash2d(i + float2(1.0, 0.0));
    float c = hash2d(i + float2(0.0, 1.0));
    float d = hash2d(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// MARK: - Outline Geometry Modifier
// Expands vertices along normals to create the outline shell.
// custom_parameter.x = outlineWidth

[[visible]]
void outlineGeometry(realitykit::geometry_parameters params) {
    float outlineWidth = params.uniforms().custom_parameter().x;

    float3 normal = params.geometry().normal();
    float3 offset = normal * outlineWidth;

    params.geometry().set_model_position_offset(offset);
}

// MARK: - Outline Surface Shader
// Animated spark/glow/rim effect for the expanded outline mesh.
// custom_parameter:
//   x = outlineWidth (used by geometry modifier)
//   y = time (elapsed seconds for animation)
//   z = unused
//   w = unused

[[visible]]
void outlineSurface(realitykit::surface_parameters params) {
    float4 customParam = params.uniforms().custom_parameter();
    float time = customParam.y;

    // Shader parameters
    constexpr half3 outlineColor = half3(0.3195h, 0.1014h, 0.5h);  // Purple (#511A80)
    constexpr half outlineAlpha = 0.5882h;                           // ~150/255
    constexpr half glowIntensity = 10.0h;
    constexpr float sparkSpeed = 4.0;
    constexpr float sparkFrequency = 8.0;
    constexpr half sparkIntensity = 4.0h;
    constexpr float rimPower = 2.0;
    constexpr half rimIntensity = 0.7h;

    // Get world-space data
    float3 worldPos = params.geometry().world_position();
    float3 modelPos = params.geometry().model_position();

    // Compute surface normal from screen-space derivatives
    float3 dpdx_val = dfdx(worldPos);
    float3 dpdy_val = dfdy(worldPos);
    float3 worldNormal = normalize(cross(dpdx_val, dpdy_val));

    // Approximate view direction from screen-space derivatives of world position.
    // The camera look direction can be inferred: cross(dpdx, dpdy) gives the
    // fragment-facing direction. We use the world normal as a proxy for the
    // view dot product calculation. For a surface shader without camera_position
    // access, we approximate rim based on the fragment normal vs the camera-facing
    // direction derived from the projection.
    // Simpler approach: use the normalized world position direction as approximate view dir
    float3 viewDir = normalize(-worldPos);

    // --- Rim Lighting ---
    float rim = 1.0 - saturate(dot(worldNormal, viewDir));
    rim = pow(saturate(rim), rimPower) * float(rimIntensity);

    float animTime = time * sparkSpeed;

    // --- Spark Layer 1 ---
    float2 sparkCoord1 = modelPos.xy * sparkFrequency;
    float spark1 = noise2d(sparkCoord1 + animTime * 0.5);
    spark1 = pow(saturate(spark1), 2.0);

    // --- Spark Layer 2 ---
    float2 sparkCoord2 = modelPos.xz * sparkFrequency * 1.7;
    float spark2 = noise2d(sparkCoord2 - animTime * 0.3);
    spark2 = pow(saturate(spark2), 3.0);

    // --- Traveling Wave ---
    float wave = sin(modelPos.y * 10.0 - animTime * 3.0) * 0.5 + 0.5;
    wave = pow(saturate(wave), 2.0);

    // --- Combine Sparks ---
    float sparkHash = hash2d(floor(sparkCoord1));
    float sparkMask = step(0.6, sparkHash);
    float combinedSpark = mix(spark1, spark2, 0.5) * sparkMask;
    combinedSpark = max(combinedSpark, wave * 0.3);

    // --- Pulse ---
    float pulse = sin(animTime * 2.0) * 0.3 + 0.7;
    float animationIntensity = 1.0 + combinedSpark * float(sparkIntensity);
    animationIntensity *= pulse;

    // --- Final Color ---
    half3 finalColor = outlineColor * glowIntensity * half(animationIntensity);
    finalColor *= half(rim * 0.7 + 0.3);

    half finalAlpha = half((rim * 0.6 + 0.4) * saturate(animationIntensity * 0.5)) * outlineAlpha;

    // Output through emissive to bypass RealityKit dimming
    params.surface().set_base_color(half3(0.0h));
    params.surface().set_emissive_color(finalColor);
    params.surface().set_opacity(finalAlpha);
}
