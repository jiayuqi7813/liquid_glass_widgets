#include <flutter/runtime_effect.glsl>

precision highp float;

/*
  iOS 26 LIQUID GLASS INDICATOR SHADER
  =====================================
  
  This shader creates the liquid glass refraction effect for interactive
  indicators (like the pill in a segmented control). It samples a captured
  background texture and applies edge distortion to simulate light bending
  through glass.
  
  COORDINATE SYSTEM:
  - All calculations use LOGICAL pixels (not physical/device pixels)
  - uBackgroundOrigin and uBackgroundSize are in logical pixels
  - This avoids DPR scaling issues across different devices
  
  MAIN EFFECTS:
  1. Edge refraction - bends the background image at the pill edges
  2. Chromatic aberration - separates RGB channels at edges for prism effect
  3. Directional lighting - rim highlights based on light angle
  4. Fresnel glow - subtle glow at grazing angles
  5. Synthetic bevel gradient - top-bright / bottom-dim rim falloff that
     simulates the view-angle gradient of a real 3D Impeller bevel
*/

// -----------------------------------------------------------------------------
// UNIFORMS
// -----------------------------------------------------------------------------
// We pack uniforms into vec4s to avoid Metal's 14 constant buffer limit on the iOS Simulator.
uniform vec4 uData0; // 0..3 (size.x, size.y, origin.x, origin.y)
uniform vec4 uData1; // 4..7 (glassColor)
uniform vec4 uData2; // 8..11 (thickness, lightDir.x, lightDir.y, lightIntensity)
uniform vec4 uData3; // 12..15 (ambientStrength, saturation, refractiveIndex, chromaticAberration)
uniform vec4 uData4; // 16..19 (cornerRadius, scale.x, scale.y, glowIntensity)
uniform vec4 uData5; // 20..23 (densityFactor, interactionIntensity, bgOrigin.x, bgOrigin.y)
uniform vec4 uData6; // 24..27 (bgSize.width, bgSize.height, hasBackground, ambientRim)
uniform vec4 uData7; // 28..31 (baseAlphaMultiplier, edgeAlphaMultiplier, rimThickness, rimSmoothing)
uniform vec4 uData8; // 32..35 (compactHeightPinch, compactEdgePull, compactEdgeBlur, compactInnerShadow)

uniform sampler2D uTexture;         // Captured background image

out vec4 fragColor;

void main() {
  vec2 uSize = uData0.xy;
  vec2 uOrigin = uData0.zw;
  vec4 uGlassColor = uData1;
  float uThickness = uData2.x;
  vec2 uLightDirection = uData2.yz;
  float uLightIntensity = uData2.w;
  float uAmbientStrength = uData3.x;
  float uSaturation = uData3.y;
  float uRefractiveIndex = uData3.z;
  float uChromaticAberration = uData3.w;
  float uCornerRadius = uData4.x;
  vec2 uScale = uData4.yz;
  float uGlowIntensity = uData4.w;
  float uDensityFactor = uData5.x;
  float uInteractionIntensity = uData5.y;
  vec2 uBackgroundOrigin = uData5.zw;
  vec2 uBackgroundSize = uData6.xy;
  float uHasBackground = uData6.z;
  float uAmbientRim = uData6.w;
  float uBaseAlphaMultiplier = uData7.x;
  float uEdgeAlphaMultiplier = uData7.y;
  float uRimThickness = uData7.z;
  float uRimSmoothing = uData7.w;
  float uCompactLensHeightPinch = uData8.x;
  float uCompactLensEdgePull = uData8.y;
  float uCompactLensEdgeBlur = uData8.z;
  float uCompactLensInnerShadow = uData8.w;

  // ==========================================================================
  // COORDINATE SETUP
  // ==========================================================================
  // FlutterFragCoord gives pixel position within the current drawing layer.
  // Since we're inside a RepaintBoundary layer, this starts at (0,0).
  
  vec2 fragPx = FlutterFragCoord().xy;
  
  // Convert to local logical position (0 to uSize)
  // Note: uOrigin is (0,0) and uScale is (1,1) due to layer boundaries
  vec2 localLogical = (fragPx - uOrigin) / uScale;
  vec2 center = uSize * 0.5;
  vec2 normalizedP = (localLogical - center) / center;
  float radialDist = length(normalizedP);  // 0 at center, 1 at edge
  
  // ==========================================================================
  // SDF PILL SHAPE
  // ==========================================================================
  // Using a standard high-fidelity Rounded Rectangle SDF for lighting stability.
  
  vec2 halfSize = uSize * 0.5;
  vec2 q = abs(localLogical - halfSize) - halfSize + uCornerRadius;
  float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - uCornerRadius;

  // Anti-aliasing: smooth transition at edge
  float smoothing = 1.0 / uScale.x;
  float mask = 1.0 - smoothstep(-smoothing, smoothing, dist);
  
  // Early exit if outside the shape
  if (mask <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  
  // ==========================================================================
  // SURFACE NORMAL
  // ==========================================================================
  vec2 innerHalfSize = halfSize - uCornerRadius;
  vec2 p = localLogical - halfSize;
  vec2 closestOnSkeleton = clamp(p, -innerHalfSize, innerHalfSize);
  vec2 toEdge = p - closestOnSkeleton;
  float edgeLen = length(toEdge);
  // Reuse edgeLen for the division — normalize(toEdge) would recompute length()
  // internally. Dividing by the already-computed scalar saves one length() call
  // per fragment in the surface normal path.
  vec2 surfaceNormal = (edgeLen > 0.001) ? (toEdge / edgeLen) : vec2(0.0);
  
  // ==========================================================================
  // BACKGROUND REFRACTION (THE MAIN EFFECT)
  // ==========================================================================
  // Sample the background texture with UV coordinates.
  // All values are in LOGICAL pixels for consistency.
  
  vec2 posInBg = uBackgroundOrigin + localLogical;
  vec2 uvBase = posInBg / uBackgroundSize;
  
  // --------------------------------------------------------------------------
  // EDGE DISTORTION
  // --------------------------------------------------------------------------
  // Creates the "liquid lens" effect at the pill edges by bending the
  // sampled background position inward along the surface normal.
  
  float distFromEdge = abs(dist);
  // Low-alpha lenses are used by segmented controls above real text. Keep
  // their base refraction horizontal so the top/bottom rim does not duplicate glyphs.
  float compactHeightPinch = clamp(uCompactLensHeightPinch, 0.0, 1.0);
  float compactLensEnabled = max(
    max(step(0.001, compactHeightPinch), step(0.001, uCompactLensEdgePull)),
    max(step(0.001, uCompactLensEdgeBlur), step(0.001, uCompactLensInnerShadow))
  );
  float translucentLens = max(
    max(step(uBaseAlphaMultiplier, 0.119), step(uEdgeAlphaMultiplier, 0.399)),
    compactLensEnabled
  );
  
  // TWEAK: edgeZone - How far from the edge the distortion extends (logical px)
  //   Smaller = sharper transition, concentrated at very edge
  //   Larger = softer, more gradual effect spreading inward
  float edgeZone = mix(
    14.0,
    max(3.0, uSize.y * mix(0.12, 0.22, compactHeightPinch)),
    translucentLens
  );
  float edgeHold = mix(0.0, max(0.8, uSize.y * 0.020), translucentLens);
  
  // Calculate influence: 1.0 at edge, 0.0 at edgeZone pixels inward
  float edgeInfluence = 1.0 - smoothstep(edgeHold, edgeZone, distFromEdge);
  
  // TWEAK: Quadratic falloff makes the bend gentler (less abrupt)
  //   Use edgeInfluence directly for sharper edge effect
  //   Use edgeInfluence * edgeInfluence for gentler, more natural curve
  //   Use pow(edgeInfluence, 3.0) for even gentler effect
  edgeInfluence = edgeInfluence * edgeInfluence;
  
  // TWEAK: bendStrength - Overall refraction intensity
  //   Base (0.9): stronger edge lens distortion, closer to Impeller volumetric warp
  //   Range: 0.45 (rest) → 1.17 (fully pressed)
  float bendStrength = 0.9 * (0.5 + uInteractionIntensity * 0.7);
  
  // TWEAK: The final multiplier (uSize.y * 0.35) scales by widget height
  //   0.35 means max offset is 35% of widget height
  //   Increase for more dramatic effect, decrease for subtler
  vec2 edgeOffsetLogical = surfaceNormal * edgeInfluence * bendStrength * uSize.y * 0.35;
  edgeOffsetLogical *= mix(1.0, 0.22, translucentLens);
  edgeOffsetLogical.y *= mix(1.0, 0.0, translucentLens);
  float sideX = abs(normalizedP.x);
  float sideSign = sign(normalizedP.x);
  float compactBlurMask = 0.0;
  float compactEdgeBlurMask = 0.0;
  float compactInnerShadowMask = 0.0;
  float compactDispersionMask = 0.0;
  float bodyInfluence = 0.0;
  if (translucentLens > 0.5) {
    float yAbs = abs(normalizedP.y);
    float verticalBroad = 1.0 - smoothstep(0.72, 1.04, yAbs);
    float shoulderMask = smoothstep(0.74, 0.94, sideX) *
                         (1.0 - smoothstep(0.992, 1.0, sideX));
    float outerMask = smoothstep(0.88, 0.999, sideX);
    float sideProfile = pow(smoothstep(0.66, 0.992, sideX), 0.82);
    float glyphBand = 1.0 - smoothstep(0.40, 0.72, yAbs);
    float glyphEdgeMask = max(shoulderMask * 0.55, outerMask);
    float lineBand = 1.0 - smoothstep(0.72, 1.0, yAbs);
    float lineShoulderMask = smoothstep(0.955, 0.992, sideX) *
                             (1.0 - smoothstep(0.998, 1.0, sideX));
    float lineOuterMask = smoothstep(0.972, 0.999, sideX);
    float lineEdgeMask = max(lineShoulderMask * 0.78, lineOuterMask) *
                         lineBand;

    float edgePull = clamp(uCompactLensEdgePull, 0.0, 1.0);
    bodyInfluence = smoothstep(edgeHold, edgeZone, distFromEdge);
    float pinchYMask = mix(0.18, 1.0, smoothstep(0.28, 0.84, yAbs));

    edgeOffsetLogical.y -= normalizedP.y * uSize.y *
                           compactHeightPinch * bodyInfluence * pinchYMask;
    float glyphWarpMask = max(glyphEdgeMask * glyphBand, lineEdgeMask) *
                          translucentLens;
    edgeOffsetLogical.x -= sideSign * uSize.x *
                           (0.010 + 0.022 * edgePull) *
                           sideProfile * glyphBand * translucentLens;
    edgeOffsetLogical.x += sideSign * normalizedP.y * uSize.y * 0.10 *
                           outerMask * glyphBand * edgePull * translucentLens;
    edgeOffsetLogical.y += normalizedP.y * uSize.y * 0.92 *
                           glyphEdgeMask * glyphBand * edgePull *
                           translucentLens;
    edgeOffsetLogical.y += normalizedP.y * uSize.y * 0.40 *
                           lineEdgeMask * edgePull * translucentLens;

    compactDispersionMask = max(outerMask, shoulderMask * 0.72) *
                            glyphBand * translucentLens *
                            (0.35 + 0.65 * edgePull);
    compactBlurMask = clamp(uCompactLensEdgeBlur, 0.0, 1.0) *
                      max(outerMask, shoulderMask * 0.55) *
                      glyphBand * translucentLens *
                      (0.35 + 0.65 * edgePull);
    compactEdgeBlurMask = clamp(uCompactLensEdgeBlur, 0.0, 1.0) *
                          max(pow(edgeInfluence, 0.36), glyphWarpMask * 0.55);
    float innerY = smoothstep(0.64, 0.98, yAbs);
    float sideInner = smoothstep(0.58, 0.96, sideX) * verticalBroad;
    compactInnerShadowMask = clamp(uCompactLensInnerShadow, 0.0, 1.0) *
                             max(innerY * bodyInfluence * 0.72,
                                 sideInner * edgeInfluence * 0.62);
  }
  
  // Apply refraction offset along the surface normal.
  // On OpenGL ES the background texture is stored with a bottom-left Y origin,
  // so edgeOffsetLogical.y (computed in Flutter's Y-down space) must be
  // negated to sample in the correct outward direction in the Y-up UV space.
  #ifdef IMPELLER_TARGET_OPENGLES
    vec2 localRefracted = posInBg + vec2(edgeOffsetLogical.x, -edgeOffsetLogical.y);
  #else
    vec2 localRefracted = posInBg - edgeOffsetLogical;
  #endif
  
  // --------------------------------------------------------------------------
  // CHROMATIC ABERRATION
  // --------------------------------------------------------------------------
  // Separates RGB channels slightly at edges, creating a subtle prism effect.
  // Red shifts one way, blue shifts the opposite, green stays centered.
  
  // TWEAK: (0.12) - subtle chromatic shift for "Apple style" refraction
  vec2 distort = surfaceNormal * edgeInfluence * uChromaticAberration;
  vec2 chromaticShift = distort * 0.12;
  if (compactDispersionMask > 0.001) {
    vec2 chromaAxis = normalize(vec2(sideSign, normalizedP.y * 1.35 + 0.001));
    chromaticShift += chromaAxis * uSize.y * uChromaticAberration *
                      compactDispersionMask * 0.18;
  }
  
  vec3 bg;
  if (uHasBackground > 0.5) {
    if (uChromaticAberration < 0.001) {
      // No chromatic aberration — single texture fetch (2/3 fewer samples vs
      // the 3-channel path). This is the common default configuration.
      bg = texture(uTexture, localRefracted / uBackgroundSize).rgb;
    } else {
      // REAL REFRACTION with chromatic aberration: separate RGB channels
      vec3 colR = texture(uTexture, (localRefracted + chromaticShift) / uBackgroundSize).rgb;
      vec3 colG = texture(uTexture, localRefracted / uBackgroundSize).rgb;
      vec3 colB = texture(uTexture, (localRefracted - chromaticShift) / uBackgroundSize).rgb;
      bg = vec3(colR.r, colG.g, colB.b);
    }
  } else {
    // SYNTHETIC LIQUID: Bright clear base with subtle tint
    // We use a high base color (0.9) to ensure it looks like pure glass
    bg = vec3(0.9);
  }

  float compactBlurAmount = max(compactBlurMask, compactEdgeBlurMask);
  if (uHasBackground > 0.5 && compactBlurAmount > 0.001) {
    vec2 blurUV = localRefracted / uBackgroundSize;
    float blurPx = uSize.y *
                   (0.004 + 0.038 * compactEdgeBlurMask +
                    0.018 * compactBlurMask);
    vec2 blurDx = vec2(blurPx / uBackgroundSize.x, 0.0);
    vec2 blurDy = vec2(0.0, blurPx / uBackgroundSize.y);
    vec3 blurred = texture(uTexture, blurUV).rgb * 0.25;
    blurred += (
      texture(uTexture, blurUV + blurDx).rgb +
      texture(uTexture, blurUV - blurDx).rgb +
      texture(uTexture, blurUV + blurDy).rgb +
      texture(uTexture, blurUV - blurDy).rgb
    ) * 0.125;
    blurred += (
      texture(uTexture, blurUV + blurDx + blurDy).rgb +
      texture(uTexture, blurUV + blurDx - blurDy).rgb +
      texture(uTexture, blurUV - blurDx + blurDy).rgb +
      texture(uTexture, blurUV - blurDx - blurDy).rgb
    ) * 0.0625;
    float blurMix = clamp(compactBlurMask + compactEdgeBlurMask * 0.55,
                          0.0, 0.82);
    bg = mix(bg, blurred, blurMix);
  }
  
  // uLightDirection is passed from Dart as [cos(angle), -sin(angle)]
  float edgeLightCatch = dot(surfaceNormal, uLightDirection);
  
  // Key light: bright highlight on edges facing the light
  // TWEAK: pow exponent (8.0) controls sharpness - higher = tighter highlight
  // NOTE: Using * 0.5 (same scale as kickHighlight) to avoid an over-bright "dot"
  // at the pill corner where the light direction perfectly aligns with the corner normal.
  float keyHighlight = pow(max(edgeLightCatch, 0.0), 8.0) * uLightIntensity * 0.5;
  
  // Kick light: subtle highlight on opposite edge (back-reflection)
  // TWEAK: pow exponent (12.0) is higher for tighter back-reflection
  float kickHighlight = pow(max(-edgeLightCatch, 0.0), 12.0) * uLightIntensity * 0.5;
  
  // TWEAK: ambientRim - minimum rim brightness regardless of light direction
  float rimBrightness = uAmbientRim + keyHighlight + kickHighlight;
  
  // ==========================================================================
  // FRESNEL GLOW
  // ==========================================================================
  // Subtle glow at grazing angles (edges appear slightly brighter)
  
  // TWEAK: multiplier (0.25) controls fresnel intensity
  float fresnel = pow(radialDist, 2.0) * 0.25;
  
  // ==========================================================================
  // HAIRLINE RIM
  // ==========================================================================
  // Thin bright line at the very edge of the pill
  
  // Configurable hairline rim
  float borderMask = 1.0 - smoothstep(0.0, smoothing * uRimSmoothing, distFromEdge - uRimThickness);

  // --------------------------------------------------------------------------
  // SYNTHETIC BEVEL GRADIENT
  // --------------------------------------------------------------------------
  // The Impeller 3D bevel naturally brightens at the top because the top-face
  // normals angle toward the viewer, catching more ambient light. On a flat 2D
  // ring every point gets the same brightness, which reads as "fake".
  //
  // We simulate this by blending rim brightness with a vertical gradient derived
  // from the Y component of the surface normal:
  //   surfaceNormal.y < 0  → top of pill  → brighter (add bevelBoost)
  //   surfaceNormal.y > 0  → bottom       → dimmer   (subtract bevelDip)
  //
  // This is pure ALU — no texture samples, no uniforms required.
  // kBevelStrength: calibrated so the gradient reads clearly on large pills
  // (tab bar ~50px) without being aggressive on small elements (switch thumb ~22px).
  const float kBevelStrength = 0.18;
  // normalY range: -1 (top edge) to +1 (bottom edge) in Flutter's Y-down space
  float bevelGradient = -surfaceNormal.y * kBevelStrength;
  // Blend the gradient in only where the border mask is visible to avoid
  // affecting the body of the pill.
  // Clamp to 0.0: gradient dims the bottom rim to neutral, never to negative
  // (negative values subtract from finalColor and cause dark jagged artefacts).
  float modifiedRimBrightness = max(0.0, rimBrightness + bevelGradient * borderMask);

  // Scale rim brightness with ambientRim parameter
  vec3 rimColor = vec3(1.0) * modifiedRimBrightness * (uAmbientRim * 10.0);
  
  // ==========================================================================
  // COMPOSITE FINAL COLOR
  // ==========================================================================
  
  // Start with background — glass transmits and adds luminosity, not darkness.
  // uSaturation doubles as bgBoost for Standard (how much the captured bg is brightened).
  // uSaturation also sets the synthetic bright base when no background is captured.
  // Default: saturation=1.08 → bgBoost=1.08 (compensates for backdrop being slightly darker).
  // Synthetic base = uSaturation * 1.11 → 1.08 * 1.11 ≈ 1.2 (same as before).
  float bgBoost = uSaturation;         // TUNE via LiquidGlassSettings.saturation
  float synthBase = uSaturation * 1.11; // TUNE: synthetic bright base (no-bg path)
  vec3 finalColor = (uHasBackground > 0.5) ? (bg * bgBoost) : vec3(synthBase);
  
  // Add rim highlight (only if rimColor is non-zero)
  finalColor += rimColor * borderMask;
  // Secondary rim pass: extra bevel definition at the edge
  finalColor += rimColor * borderMask * 0.5;

  // Add fresnel glow — uGlowIntensity controls how visible the glass-edge luminosity is.
  // Default: glowIntensity=0.75 matches previous hardcoded value.
  finalColor += vec3(1.0) * fresnel * uGlowIntensity; // TUNE via LiquidGlassSettings.glowIntensity
  
  // Interior light lift — matches Premium Impeller's internal SDF specular glow.
  // uAmbientStrength directly controls this lift value.
  // Ambient strength is already normalized (0.25x) in the Dart layout pass.
  finalColor += vec3(uAmbientStrength); // TUNE via LiquidGlassSettings.ambientStrength
  
  // Apply glass tint color
  finalColor = mix(finalColor, finalColor + uGlassColor.rgb * 0.2, uGlassColor.a);
  
  // Clamp to prevent over-bright pixels
  finalColor = min(finalColor, vec3(1.2));
  if (compactInnerShadowMask > 0.001) {
    finalColor *= 1.0 - compactInnerShadowMask * 0.18;
  }
  
  // ==========================================================================
  // ALPHA / TRANSPARENCY
  // ==========================================================================
  
  // TWEAK: baseAlpha - center transparency (lower = more see-through)
  // Standard mode: Provide a solid glassy body even at rest (Intensity 0), 
  // boosting it slightly when pressed.
  float standardBaseAlpha = uBaseAlphaMultiplier * mix(0.6, 1.0, uInteractionIntensity);
  // Restore original 0.70 when background is enabled — clear glass is translucent, not frosted.
  float baseAlpha = (uHasBackground > 0.5) ? 0.70 : standardBaseAlpha;
  
  // TWEAK: edgeAlpha - edge opacity (higher = more solid edges)
  // Standard mode: Keep a strong structural rim at rest to match 3D bevel.
  float standardEdgeAlpha = uEdgeAlphaMultiplier * mix(0.6, 1.0, uInteractionIntensity);
  float edgeAlpha = (uHasBackground > 0.5) ? 0.95 : standardEdgeAlpha;
  
  // Blend from center to edge
  float glassAlpha = mix(baseAlpha, edgeAlpha, edgeInfluence);
  float ringOpacity = borderMask * 0.9 * clamp(uAmbientRim * 10.0, 0.0, 1.0);
  ringOpacity *= mix(1.0, 0.12, translucentLens);
  glassAlpha = max(glassAlpha, ringOpacity);
  glassAlpha *= mix(1.0, 0.38, (1.0 - uHasBackground) * translucentLens);



  
  float alpha = glassAlpha * mask;
  
  // Premultiplied alpha output
  fragColor = vec4(finalColor * alpha, alpha);
}
