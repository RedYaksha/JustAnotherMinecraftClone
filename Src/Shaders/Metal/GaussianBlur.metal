//
//  Skybox.metal
//  MetalTutorial
//
//  Created by Ronnin Padilla on 8/25/24.
//

#include <metal_stdlib>
using namespace metal;
#include "VertexDataTypes.hpp"

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut gaussianBlurVS(uint vertexID [[vertex_id]],
                                constant SimpleVertexData* vertexData [[buffer(0)]]) {
    VertexOut out { vertexData[vertexID].position, vertexData[vertexID].uv };
    return out;
}

fragment float4 gaussianBlurHorizontalFS(VertexOut in [[stage_in]],
                               texture2d<float> srcRT [[texture(0)]],
                               constant GaussianBlurState* blurState [[buffer(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, mag_filter::linear);
    float2 texelSize = 1.0 / float2(srcRT.get_width(), srcRT.get_height());
    
    constexpr float weight[5] = { 0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216 };

    float3 result = srcRT.sample(textureSampler, in.uv).rgb * weight[0]; // current fragment's contribution
    
    for(int i = 1; i < 5; ++i)
    {
        result += srcRT.sample(textureSampler, in.uv + float2(texelSize.x * i, 0.0)).rgb * weight[i];
        result += srcRT.sample(textureSampler, in.uv - float2(texelSize.x * i, 0.0)).rgb * weight[i];
    }

    
    return float4(result, 1);
}

fragment float4 gaussianBlurVerticalFS(VertexOut in [[stage_in]],
                               texture2d<float> srcRT [[texture(0)]],
                               constant GaussianBlurState* blurState [[buffer(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, mag_filter::linear);
    float2 texelSize = 1.0 / float2(srcRT.get_width(), srcRT.get_height());
    
    constexpr float weight[5] = { 0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216 };

    float3 result = srcRT.sample(textureSampler, in.uv).rgb * weight[0]; // current fragment's contribution
    

    for(int i = 1; i < 5; ++i)
    {
        result += srcRT.sample(textureSampler, in.uv + float2(0.0, texelSize.y * i)).rgb * weight[i];
        result += srcRT.sample(textureSampler, in.uv - float2(0.0, texelSize.y * i)).rgb * weight[i];
    }
    
    
    return float4(result, 1);
}
