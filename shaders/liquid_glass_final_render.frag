// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Final rendering pass for liquid glass with pre-computed geometry.
// Reads surface normal data from the geometry texture (V1 encoding) and applies
// the liquid glass effect: refraction, chromatic aberration, tint, and edge lighting.
//
// Geometry texture layout (displacement_encoding.glsl):
//   R: normal.x  [-1, 1] → [0, 1]
//   G: normal.y  [-1, 1] → [0, 1]
//   B: height    normalized to thickness
//   A: foreground alpha (SDF AA)

#version 460 core
precision highp float; // mediump causes colour banding (10-bit mantissa on mobile)

#define DEBUG_GEOMETRY 0

#include <flutter/runtime_effect.glsl>
#include "displacement_encoding.glsl"
#include "render.glsl"

// Slot 0-1:  uSize           — physical-pixel size of the backdrop capture
// Slots 2-3: uGeometryOffset — top-left of geometry matte in physical pixels
// Slots 4-5: uGeometrySize   — size of geometry matte in physical pixels
// Slots 6-9: uGlassColor
// Slots 10-12: uOpticalProps (refractiveIndex, chromaticAberration, thickness)
// Slots 13-15: uLightConfig  (lightIntensity, ambientStrength, saturation)
// Slots 16-17: uLightDirection
// Slot 18: uRefractionScale
// Slot 19: uVerticalRefractionScale
// Slot 20: uSideFisheyeScale
// Slot 21: uCompactLensHeightPinch
// Slot 22: uCompactLensEdgePull
// Slot 23: uCompactLensEdgeBlur
// Slot 24: uCompactLensInnerShadow
uniform vec2 uSize;          // physical-pixel size of the backdrop capture
uniform vec2 uGeometryOffset;
uniform vec2 uGeometrySize;

uniform vec4 uGlassColor;
uniform vec3 uOpticalProps;
uniform vec3 uLightConfig;
uniform vec2 uLightDirection;
uniform float uRefractionScale;
uniform float uVerticalRefractionScale;
uniform float uSideFisheyeScale;
uniform float uCompactLensHeightPinch;
uniform float uCompactLensEdgePull;
uniform float uCompactLensEdgeBlur;
uniform float uCompactLensInnerShadow;

uniform sampler2D uBackgroundTexture;
uniform sampler2D uGeometryTexture;

layout(location = 0) out vec4 fragColor;

void main() {
    // Unpacked here rather than at global scope: global non-constant initialisers
    // (e.g. float x = uniform.y) are valid in desktop GLSL 4.6 but rejected by
    // SkSL / glslang on Windows (SPIR-V path). Same fix as 0.7.10 geometry shader.
    float uRefractiveIndex     = uOpticalProps.x;
    float uChromaticAberration = uOpticalProps.y;
    float uThickness           = uOpticalProps.z;
    float uLightIntensity      = uLightConfig.x;
    float uAmbientStrength     = uLightConfig.y;
    float uSaturation          = uLightConfig.z;

    vec2 fragCoord = FlutterFragCoord().xy;

    // Use the explicit uSize uniform for UV derivation. textureSize() was tried
    // but can return (0,0) on the first frame before GPU texture upload completes
    // in Impeller's BackdropFilterLayer context, causing 1/0 = Infinity UVs and
    // an invisible first-frame render. uSize (physical pixels of the backdrop
    // capture, equal to desiredMatteSize * devicePixelRatio) is always valid.
    vec2 invTexSize = 1.0 / uSize;
    vec2 screenUV = fragCoord * invTexSize;

    #ifdef IMPELLER_TARGET_OPENGLES
        screenUV.y = 1.0 - screenUV.y;
    #endif

    vec2 geometryUV = (fragCoord - uGeometryOffset) / uGeometrySize;
    #ifdef IMPELLER_TARGET_OPENGLES
        geometryUV.y = 1.0 - geometryUV.y;
    #endif

    // Any fragment whose geometryUV falls outside [0,1] is outside the glass
    // pill boundary entirely.  Without this early-out the sampler clamps to the
    // edge pixel (UV.x=0 → left boundary pixel, alpha ≈ 0.5 from SDF AA), which
    // renders a faint glass stripe in the _clipExpansion zone (20 px on each
    // side). That stripe is visible at the pill's vertical midpoint as a short
    // line protruding left and right from the pill edges.
    if (any(lessThan(geometryUV, vec2(0.0))) || any(greaterThan(geometryUV, vec2(1.0)))) {
        fragColor = vec4(0.0);
        return;
    }

    vec4 geometryData = texture(uGeometryTexture, geometryUV);

    #if DEBUG_GEOMETRY
        fragColor = geometryData;
        return;
    #endif

    if (geometryData.a < 0.01) {
        fragColor = vec4(0);
        return;
    }

    // --- V1: Decode true surface normal from geometry texture ---
    //
    // The geometry pass stores the SDF-gradient-derived normal in RG.
    // Before V1 this stored displacement XY, and the render pass called
    // normalize(displacement) as a proxy for the normal — which diverges
    // from the true normal in blend-group neck zones (smooth-union joins).
    // The true normal is now decoded and used for both refraction and lighting.
    vec2 normalXY = decodeNormalXY(geometryData);
    float normalZSq = max(0.0, 1.0 - dot(normalXY, normalXY));
    float normalZ   = sqrt(normalZSq);
    vec3  normal    = vec3(normalXY, normalZ);   // unit-length surface normal

    // Recompute refraction displacement from the true normal.
    // This is the same refract() call used in the geometry pass — exact, not
    // approximated.  Height is still read from the B channel.
    float height = decodeHeight(geometryData, uThickness);
    float baseHeight = uThickness * 8.0;
    vec3  incident   = vec3(0.0, 0.0, -1.0);
    float invN       = 1.0 / max(uRefractiveIndex, 0.001);
    vec3  baseRefract = refract(incident, normal, invN);
    float refractLen  = (height + baseHeight) / max(0.001, abs(baseRefract.z));
    vec2  displacement = baseRefract.xy * refractLen;

    // On OpenGL ES, screenUV.y is already flipped to (1.0 - y) to compensate
    // for the bottom-left texture-origin convention.  The displacement is
    // computed in Flutter's native Y-down space (outward normal at the bottom
    // edge has +Y), but adding a positive Y delta to the flipped UV moves the
    // sample TOWARD the centre rather than away — inverting the refraction.
    // Negating displacement.y re-aligns it with the Y-up UV sampling space.
    #ifdef IMPELLER_TARGET_OPENGLES
        displacement.y = -displacement.y;
    #endif
    displacement *= clamp(uRefractionScale, 0.0, 1.0);
    displacement.y *= clamp(uVerticalRefractionScale, 0.0, 1.0);

    // Segmented-control compact lens. The covered track is optically pinched
    // inside the bubble, while text refraction is layered separately so it is
    // not clamped to the rail transition mask.
    float compactLens = 1.0 - clamp(uRefractionScale, 0.0, 1.0);
    float compactGate = clamp(uSideFisheyeScale, 0.0, 1.0) *
                        smoothstep(0.05, 0.35, compactLens);
    float compactBlurMask = 0.0;
    float compactEdgeBlurMask = 0.0;
    float compactDispersionMask = 0.0;
    float compactInnerShadowMask = 0.0;
    float compactSampleMask = 0.0;
    float compactSideSign = 0.0;
    float compactCenterY = 0.0;
    float compactRimMask = 0.0;
    if (compactGate > 0.001) {
        vec2 local01 = clamp(geometryUV, vec2(0.0), vec2(1.0));
        float sideSign = sign(local01.x - 0.5);
        float edgeX = abs(local01.x - 0.5) * 2.0;
        float centerY = local01.y - 0.5;
        float yAbs = abs(centerY);
        float verticalBroad = 1.0 - smoothstep(0.42, 0.58, yAbs);
        float hNorm = clamp(geometryData.b, 0.0, 0.999);
        float edgeDistancePx = uThickness *
                               (1.0 - sqrt(max(0.0, 1.0 - hNorm * hNorm)));
        float shoulderMask = smoothstep(0.74, 0.94, edgeX) *
                             (1.0 - smoothstep(0.992, 1.0, edgeX));
        float outerMask = smoothstep(0.88, 0.999, edgeX);
        float sideProfile = pow(smoothstep(0.66, 0.992, edgeX), 0.82);
        float glyphBand = 1.0 - smoothstep(0.20, 0.36, yAbs);
        float glyphEdgeMask = max(shoulderMask * 0.55, outerMask);
        float lineBand = 1.0 - smoothstep(0.36, 0.50, yAbs);
        float lineShoulderMask = smoothstep(0.955, 0.992, edgeX) *
                                 (1.0 - smoothstep(0.998, 1.0, edgeX));
        float lineOuterMask = smoothstep(0.972, 0.999, edgeX);
        float lineEdgeMask = max(lineShoulderMask * 0.78, lineOuterMask) *
                             lineBand;

        float heightPinch = clamp(uCompactLensHeightPinch, 0.0, 1.0);
        float edgePull = clamp(uCompactLensEdgePull, 0.0, 1.0);
        float rimHoldPx = max(0.8, uGeometrySize.y * 0.020);
        float rimWidthPx = max(3.0, uGeometrySize.y * mix(0.12, 0.22, heightPinch));
        compactRimMask = (1.0 - smoothstep(rimHoldPx, rimWidthPx, edgeDistancePx)) *
                         compactGate;
        float bodyMask = smoothstep(rimHoldPx, rimWidthPx, edgeDistancePx) *
                         compactGate;
        float pinchYMask = mix(0.18, 1.0, smoothstep(0.14, 0.42, yAbs));
        vec2 bodyDisplacement = vec2(
            0.0,
            centerY * uGeometrySize.y * heightPinch * bodyMask * pinchYMask
        );

        vec2 edgeDisplacement = displacement;
        displacement = mix(bodyDisplacement, edgeDisplacement, compactRimMask);

        float glyphWarpMask = max(glyphEdgeMask * glyphBand, lineEdgeMask) *
                              compactGate;
        vec2 glyphWarpDisplacement = vec2(0.0);
        glyphWarpDisplacement.x -= sideSign * uGeometrySize.x *
                                   (0.010 + 0.022 * edgePull) *
                                   sideProfile * glyphBand * compactGate;
        glyphWarpDisplacement.x += sideSign * centerY * uGeometrySize.y * 0.10 *
                                   outerMask * glyphBand * edgePull *
                                   compactGate;
        glyphWarpDisplacement.y -= centerY * uGeometrySize.y * 0.96 *
                                   glyphEdgeMask * glyphBand * edgePull *
                                   compactGate;
        glyphWarpDisplacement.y -= centerY * uGeometrySize.y * 0.42 *
                                   lineEdgeMask * edgePull * compactGate;
        displacement += glyphWarpDisplacement;

        compactSideSign = sideSign;
        compactCenterY = centerY;
        compactSampleMask = max(max(compactRimMask,
                                    heightPinch * bodyMask * pinchYMask),
                                glyphWarpMask);
        compactDispersionMask = max(outerMask, shoulderMask * 0.72) *
                                glyphBand * compactGate *
                                (0.35 + 0.65 * edgePull);
        compactBlurMask = clamp(uCompactLensEdgeBlur, 0.0, 1.0) *
                          max(outerMask, shoulderMask * 0.55) *
                          glyphBand * compactGate *
                          (0.35 + 0.65 * edgePull);
        compactEdgeBlurMask = clamp(uCompactLensEdgeBlur, 0.0, 1.0) *
                              pow(compactRimMask, 0.72);
        compactSampleMask = max(compactSampleMask, compactEdgeBlurMask);
        float innerY = smoothstep(0.32, 0.49, yAbs);
        float sideInner = smoothstep(0.58, 0.96, edgeX) * verticalBroad;
        compactInnerShadowMask = clamp(uCompactLensInnerShadow, 0.0, 1.0) *
                                 max(innerY * bodyMask * 0.72,
                                     sideInner * compactRimMask * 0.62);
    }

    // Apply refraction — with optional chromatic aberration.
    // PP1 optimisation: when the surface normal is flat (pointing straight up,
    // i.e. normalXY ≈ 0), refract() always produces displacement = vec2(0) and
    // the refracted UV is identical to screenUV.  Skip refract() entirely and
    // take a single background sample.  This covers the majority of pixels on
    // large surfaces (GlassAppBar, GlassPanel), where the edge zone is a small
    // fraction of the total area.
    //
    // Threshold chosen conservatively: 1e-4 in squared magnitude corresponds to
    // a normal tilted < 0.6° from vertical — visually indistinguishable from a
    // zero-displacement sample at any display resolution.
    vec4 refractColor;
    if (dot(normalXY, normalXY) < 1e-4 && compactSampleMask < 0.001) {
        // Flat interior — surface is pointing straight at the camera.
        // Displacement is mathematically zero; sample the background directly.
        refractColor = texture(uBackgroundTexture, screenUV);
    } else if (uChromaticAberration < 0.01) {
        vec2 refractedUV = screenUV + displacement * invTexSize;
        refractColor = texture(uBackgroundTexture, refractedUV);
    } else {
        float dispersionStrength = uChromaticAberration * 0.45;
        vec2 redOffset  = displacement * (1.0 + dispersionStrength);
        vec2 blueOffset = displacement * (1.0 - dispersionStrength);
        if (compactDispersionMask > 0.001) {
            vec2 chromaAxis = normalize(vec2(
                compactSideSign,
                compactCenterY * 1.8 + 0.001
            ));
            vec2 compactChromaOffset = chromaAxis * uGeometrySize.y *
                                       uChromaticAberration *
                                       compactDispersionMask * 0.20;
            redOffset += compactChromaOffset;
            blueOffset -= compactChromaOffset;
        }

        vec2 redUV   = screenUV + redOffset   * invTexSize;
        vec2 greenUV = screenUV + displacement * invTexSize;
        vec2 blueUV  = screenUV + blueOffset  * invTexSize;

        float red         = texture(uBackgroundTexture, redUV).r;
        vec4  greenSample = texture(uBackgroundTexture, greenUV);
        float blue        = texture(uBackgroundTexture, blueUV).b;

        refractColor = vec4(red, greenSample.g, blue, greenSample.a);
    }

    float compactBlurAmount = max(compactBlurMask, compactEdgeBlurMask);
    if (compactBlurAmount > 0.001) {
        vec2 blurUV = screenUV + displacement * invTexSize;
        float blurPx = uGeometrySize.y *
                       (0.004 + 0.040 * compactEdgeBlurMask +
                        0.018 * compactBlurMask);
        vec2 blurDx = vec2(blurPx * invTexSize.x, 0.0);
        vec2 blurDy = vec2(0.0, blurPx * invTexSize.y);
        vec4 blurred = texture(uBackgroundTexture, blurUV) * 0.25;
        blurred += (
            texture(uBackgroundTexture, blurUV + blurDx) +
            texture(uBackgroundTexture, blurUV - blurDx) +
            texture(uBackgroundTexture, blurUV + blurDy) +
            texture(uBackgroundTexture, blurUV - blurDy)
        ) * 0.125;
        blurred += (
            texture(uBackgroundTexture, blurUV + blurDx + blurDy) +
            texture(uBackgroundTexture, blurUV + blurDx - blurDy) +
            texture(uBackgroundTexture, blurUV - blurDx + blurDy) +
            texture(uBackgroundTexture, blurUV - blurDx - blurDy)
        ) * 0.0625;
        float blurMix = clamp(compactBlurMask + compactEdgeBlurMask * 0.55,
                              0.0, 0.82);
        refractColor = mix(refractColor, blurred, blurMix);
    }

    vec4 finalColor = applyGlassColor(refractColor, uGlassColor);

    // VQ4: Content-adaptive glass strength.
    //
    // iOS 26 glass dynamically adjusts its material intensity based on the
    // luminance of the content beneath it.  Dark backdrops produce richer,
    // more vivid glass; bright or uniform backdrops produce a subtler material
    // to avoid overwhelming the UI.
    //
    // Implementation: dot-product backdrop luminance from refractColor —
    // the already-sampled background at the refracted UV.  Zero extra texture
    // reads; the sample is already in the register file.
    //
    // LUMA_WEIGHTS = vec3(0.299, 0.587, 0.114) (BT.601, defined in render.glsl)
    //
    // adaptiveStrength range [0.8, 1.2]:
    //   • backdropLuma = 0.0 (black)  → strength 1.2 (richer glass)
    //   • backdropLuma = 1.0 (white)  → strength 0.8 (subtler glass)
    //
    // Cost: 1 dot product + 1 mix() + 1 extra mix() for tint = 3 MADs.
    // Effectively free on modern GPUs.
    float backdropLuma     = dot(refractColor.rgb, LUMA_WEIGHTS);
    float adaptiveStrength = mix(1.2, 0.8, backdropLuma);

    float adaptiveSaturation = 1.0 + (uSaturation - 1.0) * adaptiveStrength;
    finalColor.rgb = applySaturation(finalColor.rgb, adaptiveSaturation);

    // Modulate glass tint blend weight by adaptiveStrength.
    // On dark backgrounds the tint reads heavier (+20%); on bright backgrounds
    // it reads lighter (-20%).  The delta is small (max ±20% of the 12% base
    // weight = ±2.4%) — within a single JND step, noticeable as a property
    // not a glitch.  Uses mix() to re-blend toward uGlassColor.rgb over the
    // already-tinted finalColor, scaled by the adaptive delta only.
    finalColor.rgb = mix(finalColor.rgb,
                         uGlassColor.rgb,
                         uGlassColor.a * 0.12 * (adaptiveStrength - 1.0));

    if (compactInnerShadowMask > 0.001) {
        finalColor.rgb *= 1.0 - compactInnerShadowMask * 0.18;
    }

    // Edge lighting — uses the true normal.xy (V1; was normalize(displacement))
    float normalizedHeight = geometryData.b;
    float thicknessScale   = clamp(40.0 / max(uThickness, 1.0), 1.0, 4.0);
    float edgeThreshold    = mix(0.8, 0.5, 1.0 / thicknessScale);
    float edgeFactor       = uThickness < 0.01 ? 0.0 : 1.0 - smoothstep(0.0, edgeThreshold, normalizedHeight);


    if (edgeFactor > 0.01) {
        // VQ1: Anisotropic specular — stretch the highlight lobe 20% along the
        // surface tangent, producing an oval iOS 26 highlight instead of a dot.
        //
        // Pre-baked constant: normalXY from the geometry texture is unit-length
        // by construction (stored as a unit normal in the geometry pass).
        // The tangent vec2(-n.y, n.x) is therefore perp and also unit-length.
        // length(normalXY + tangent * 0.20) = sqrt(1.0 + 0.04) = 1.0198039
        // 1.0 / 1.0198039 = 0.9805806
        // This eliminates max(length(normalXY), 0.01), division, and normalize().
        // The edgeFactor > 0.01 gate above already guards the near-zero interior.
        vec2  anisoN  = normalXY; // True non-chiral normal for symmetric highlights

        float mainLight     = max(0.0, dot(anisoN, uLightDirection));
        float oppositeLight = max(0.0, dot(anisoN, -uLightDirection));
        float totalInfluence = mainLight + oppositeLight * 0.8;

        // PP2 follow-up: pow(x, 1.5) = x·√x. sqrt() is a single hardware SFU
        // instruction on all Metal/Vulkan/OpenGLES targets — not a transcendental.
        // This replaces the last pow() in the Impeller path with zero exp/log ops.
        float directional = totalInfluence * sqrt(totalInfluence) * uLightIntensity * 3.0;
        float ambient     = uAmbientStrength * 0.5;

        // Soft-clamp brightness with x/(1+x) to prevent mix() extrapolating
        // beyond highlightColor. The original * 3.0 drove the corner brightness
        // to ~9.6, causing a blinding "leading dot". The soft clamp maps all
        // values to [0, 1) so corners and edges converge gracefully.
        float brightnessRaw = (directional + ambient) * edgeFactor * thicknessScale * 0.8;
        float brightness    = brightnessRaw / (1.0 + brightnessRaw);

        vec3 highlightColor = getHighlightColor(refractColor.rgb, 1.0);
        finalColor.rgb = mix(finalColor.rgb, highlightColor, brightness);
    }

    // VQ2: Fresnel edge luminosity ramp.
    //
    // iOS 26 glass is subtly brighter at grazing angles (the rim) even when
    // no directional specular highlight lands there.  This is the Fresnel term:
    // at near-normal incidence (flat interior) reflected light is minimal;
    // at grazing incidence (edges) it increases.
    //
    // normalZ → 0 at the rim (surface nearly perpendicular to view ray),
    // normalZ → 1 at flat interior (surface facing the camera directly).
    // So (1.0 - normalZ) gives a smooth 0→1 ramp from interior to rim.
    //
    // Gated by edgeFactor so the effect is naturally confined to the rim zone
    // and doesn't accumulate on interior pixels where edgeFactor ≈ 0.
    //
    // Strength 0.10 produces a gentle brightening calibrated against Apple
    // reference screenshots.  Fully branchless — no extra GPU divergence.
    float fresnel = (1.0 - normalZ) * edgeFactor * 0.10;
    finalColor.rgb = clamp(finalColor.rgb + vec3(fresnel), 0.0, 1.0);

    float alpha  = geometryData.a;
    fragColor    = vec4(finalColor.rgb * alpha, alpha);
}
