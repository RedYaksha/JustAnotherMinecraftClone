//
//  SSAO.metal
//  MetalTutorial
//
//  Created by Ronnin Padilla on 8/23/24.
//

#include <metal_stdlib>
using namespace metal;
#include "VertexDataTypes.hpp"

struct SimpleVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex SimpleVertexOut ssaoBlurPassVS(uint vertexID [[vertex_id]],
                                      constant SimpleVertexData* vertexData [[buffer(0)]]) {
    SimpleVertexOut out  = {
        vertexData[vertexID].position,
        vertexData[vertexID].uv
    };
    
    return out;
}

fragment float ssaoBlurPassFS(SimpleVertexOut in [[stage_in]],
                          texture2d<float> ssaoTex [[texture(0)]]) {
    float blurSize = 6;
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float2 texelSize = 1.0 / float2(ssaoTex.get_width(), ssaoTex.get_height());
    
    float result = 0.0;
    for (int x = -blurSize/2; x < blurSize/2; ++x)
    {
        for (int y = -blurSize/2; y < blurSize/2; ++y)
        {
            float2 offset = float2(float(x), float(y)) * texelSize;
            result += ssaoTex.sample(textureSampler, in.uv + offset).r;
        }
    }
     
    float res = result / (blurSize * blurSize);
    
    //float4 c = ssaoTex.sample(textureSampler, in.uv);
    //return c;
    return res;
    //return float4(res, res, res, 1.0f);
}



vertex SimpleVertexOut ssaoPassVS(uint vertexID [[vertex_id]],
                                            constant SimpleVertexData* vertexData [[buffer(0)]]) {
    SimpleVertexOut out  = {
        vertexData[vertexID].position,
        vertexData[vertexID].uv
    };
    
    return out;
}

static float3x3 alignABRotationMatrix_3x3(float3 a, float3 b) {
    float3x3 rot;
    
    // Direct implementation of:
    //      https://math.stackexchange.com/a/476311
    // This creates a rotation matrix that aligns vector A onto B
    simd::float3 v = cross(a,b);
    float s = length(v);
    float c = dot(a,b);
    
    float3x3 vx = float3x3(
                            0,      v[2],  -v[1],
                            -v[2],   0,    v[0],
                            v[1] ,    -v[0], 0
                );
    
    float3x3 I = float3x3(
                            1,0,0,
                            0,1,0,
                            0,0,1
                        );
    
    float3x3 r = I + vx + vx * vx * ((1 - c) / (s * s));
    
    rot = r;
    
    if(distance(a,b) < 0.0001) {
        rot = I;
    }
    
    return rot;
}

fragment float ssaoPassFS(SimpleVertexOut in [[stage_in]],
                          
                          texture2d<float> gPosition [[texture(0)]],
                          texture2d<float> gNormal [[texture(1)]],
                          texture2d<float> gAlbedo [[texture(2)]],
                          texture2d<float> ssaoNoise [[texture(3)]],
                          
                          constant float3* ssaoKernel [[buffer(0)]],
                          constant CameraData* cd [[buffer(1)]]
                          ) {
    
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    constexpr sampler txSamplerRandVec(address::repeat);
    
    // tile noise texture over screen, based on screen dimensions divided by noise size
    float noiseWidth = 4;
    float noiseHeight = 4;
    const float2 noiseScale = float2((float) gPosition.get_width()/noiseWidth, (float) gPosition.get_height()/noiseHeight); // screen = 800x600
    
    float4 posWSRaw = gPosition.sample(textureSampler, in.uv);
    
    // conversion from depth:
    // https://stackoverflow.com/questions/32227283/getting-world-position-from-depth-buffer-value
    float4 rawClip = float4(in.uv.x * 2 - 1, -(in.uv.y * 2 - 1), posWSRaw.w, 1.0f);
    float4 rawView = cd->invProjection * rawClip;
    rawView /= rawView.w;
    
    float4 posWS = posWSRaw;
    
    float4 normalWS = gNormal.sample(textureSampler, in.uv);

    float3 pos = (cd->view * float4(posWS.xyz, 1.0f)).xyz;
    
    // NOTE: we have to multiply this normal by inverse transpose of view matrix
    // instead of the view matrix itself
    //
    // see https://www.cs.upc.edu/~robert/teaching/idi/normalsOpenGL.pdf
    float3 normal = normalize((cd->normalMat * normalWS).xyz);
    float3 randVec = normalize(ssaoNoise.sample(txSamplerRandVec, in.uv * noiseScale).xyz);
    
    float3 tangent = normalize(randVec - normal * dot(randVec, normal));
    float3 bitangent = cross(normal, tangent);
    /*
    float3x3 TBN = float3x3(
                            tangent.x, bitangent.x, normal.x,
                            tangent.y, bitangent.y, normal.y,
                            tangent.z, bitangent.z, normal.z
                            );
    */
    float3x3 TBN = float3x3(tangent, bitangent, normal);
    
    //float3x3 align1 = alignABRotationMatrix_3x3({0,0,1}, normal - dot(randVec, normal) * randVec);
    //float3x3 align2 = alignABRotationMatrix_3x3({1,0,0}, randVec);
    //float3x3 align = align1;
    
    float occlusion = 0.0f;
    int kernelSize = 16;
    float radius = 2.5f;
    float bias = 0.0025f;
    
    float3 dc = float3(0);
    // this ssao may be slow when things are close to the camera due to cache misses
    // see https://www.intel.com/content/www/us/en/developer/articles/technical/adaptive-screen-space-ambient-occlusion.html
    for(int i = 0; i < kernelSize; ++i)
    {
        // get sample position
        float3 samplePosKernel = TBN * ssaoKernel[i]; // from tangent to view-space
        float3 samplePos = pos + samplePosKernel * radius;

        float4 offset = float4(samplePos, 1.0);
        
        float4 offsetNDC = cd->projection * offset;    // from view to clip-space
        offsetNDC.y *= -1;
        offsetNDC.xyz /= offsetNDC.w;               // perspective divide
        offsetNDC.xyz = offsetNDC.xyz * 0.5 + float3(0.5); // transform to range 0.0 - 1.0
        
        float4 closestSample_WS = gPosition.sample(textureSampler, offsetNDC.xy);
        //float4 closestSample_WS = gPosition.read((ushort2) offsetNDC.xy);
        bool isFar = closestSample_WS.w >= 1.0f;
        closestSample_WS.w = 1.0f;
        
        float4 closestSample_V = cd->view * closestSample_WS;
        float sourceDepth = isFar? 1000000000 : -closestSample_V.z;
        float sampleDepth = -samplePos.z;
    
        //float sampleDepth = gPosition.sample(textureSampler, offsetNDC.xy).w; // 0-1
        float rangeCheck = abs(sourceDepth - sampleDepth) < radius ? 1.0 : 0.0;
        occlusion += (sourceDepth < sampleDepth + bias ? 1.0 : 0.0) * rangeCheck;
    }
    
    occlusion = 1.f - (occlusion / kernelSize);
    
    //float3 out = float3(occlusion);
    return occlusion;
    //return float4(out, 1);
}
