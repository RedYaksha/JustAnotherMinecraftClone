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
    float4 normal;
    float4 uvw;
};

vertex VertexOut skyboxVS(uint vertexID [[vertex_id]],
                          constant SkyBoxCubeVertexData* vertexData [[buffer(0)]],
                          constant TransformationData* td [[buffer(1)]]) {
    SkyBoxCubeVertexData vd = vertexData[vertexID];
    return {
        td->perspective * td->view * td->model * vd.position,
        vd.normal,
        vd.position
    };
}

fragment float4 skyboxFS(VertexOut in [[stage_in]],
                         texturecube<float> skyboxTx[[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    float3 texCoords = float3(in.uvw.x, -in.uvw.y, in.uvw.z);
    return skyboxTx.sample(textureSampler, texCoords);
    // return float4(1,0,0,1);
}
