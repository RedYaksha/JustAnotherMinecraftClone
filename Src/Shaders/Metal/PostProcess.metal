//
//  PostProcess.metal
//  MetalTutorial
//
//  Created by Ronnin Padilla on 8/28/24.
//
#include <metal_stdlib>
using namespace metal;
#include "VertexDataTypes.hpp"

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut postProcessVS(uint vertexID [[vertex_id]],
                                constant SimpleVertexData* vertexData [[buffer(0)]]) {
    VertexOut out { vertexData[vertexID].position, vertexData[vertexID].uv };
    return out;
}

fragment float4 postProcessFS(VertexOut in [[stage_in]],
                               texture2d<float> lightPassRT [[texture(0)]],
                               texture2d<float> bloomRT [[texture(1)]],
                               texture2d<float> unlitRT [[texture(2)]],
                               depth2d<float> geometryDepth [[texture(3)]],
                               depth2d<float> lineDepth [[texture(4)]]
                               ) {

    constexpr sampler textureSampler(mag_filter::linear, mag_filter::linear);
    float3 color = lightPassRT.sample(textureSampler, in.uv).xyz;
    float3 bloom = bloomRT.sample(textureSampler, in.uv).xyz;
    float3 unlit = unlitRT.sample(textureSampler, in.uv).xyz;
    float gd = geometryDepth.sample(textureSampler, in.uv);
    float ld = lineDepth.sample(textureSampler, in.uv);

    float colorScale = 1.0f;
    float lineScale = 0.0f;
    
    if(unlit.x != 0.0f || unlit.y != 0.0f || unlit.z != 0.0f) {
        colorScale = 100 * -(gd - ld);
        lineScale = 1 - colorScale;
        
        if(gd < ld) {
            colorScale = 0.8;
            lineScale = 0.2f;
        }
    }
    return float4(colorScale * (color +  2 * bloom) + lineScale * unlit, 1.0f);
}

