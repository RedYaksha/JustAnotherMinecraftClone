//
//  DeferredMesh.metal
//  MetalTutorial
//
//  Created by Ronnin Padilla on 8/29/24.
//
#include <metal_stdlib>
using namespace metal;
#include "VertexDataTypes.hpp"

struct VertexOut {
    // The [[position]] attribute of this member indicates that this value
    // is the clip space position of the vertex when this structure is
    // returned from the vertex function.
    float4 position [[position]];
    float2 uv;
    
    float3 normal;
    
    
    float4 positionWS;
    float4 posNDC;
    
    float3 debugColor;
};

struct GeometryFragmentOut {
    float4 positionWS [[color(0)]];
    float4 normalWS [[color(1)]];
    float4 albedoSpec [[color(2)]];
    float4 emission [[color(3)]];
};

vertex VertexOut meshPassVS(uint vertexID [[vertex_id]],
                            constant MeshVertexData* vertexData [[buffer(0)]],
                            constant float4x4* localTransforms [[buffer(1)]],
                            constant CameraData* cd [[buffer(2)]]
                            )
{
    auto meshVertex = vertexData[vertexID];
    VertexOut out;
    out.position = cd->projection * cd->view * localTransforms[meshVertex.transformationIndex] * meshVertex.position;
    out.uv = meshVertex.uv;
    out.normal = meshVertex.normal;
    out.positionWS = meshVertex.position;
    out.posNDC = out.position;

    return out;
}

float4x4 extractRotationFromMatrix(float4x4 mat) {
    // https://math.stackexchange.com/questions/237369/given-this-transformation-matrix-how-do-i-decompose-it-into-translation-rotati
    const auto m = mat.columns;
    float sx = length(float3(m[0][0], m[0][1], m[0][2]));
    float sy = length(float3(m[1][0], m[1][1], m[1][2]));
    float sz = length(float3(m[2][0], m[2][1], m[2][2]));
    
    return float4x4(
                    m[0][0] / sx, m[0][1] / sx, m[0][2] / sx, 0,
                    m[1][0] / sy, m[1][1] / sy, m[1][2] / sy, 0,
                    m[2][0] / sz, m[2][1] / sz, m[2][2] / sz, 0,
                    0           , 0           , 0           , 1
                );
}

vertex VertexOut skeletalMeshPassVS(uint vertexID [[vertex_id]],
                            constant SkeletalMeshVertexData* vertexData [[buffer(0)]],
                            constant float4x4* boneTransforms [[buffer(1)]],
                            constant float4x4* modelTransforms [[buffer(2)]],
                            constant ObjectData* objectData [[buffer(3)]],
                            constant CameraData* cd [[buffer(4)]]
                            )
{
    auto meshVertex = vertexData[vertexID];
    
    float4x4 modelTransform = modelTransforms[meshVertex.transformationIndex];
    float4x4 modelTransformRotOnly = extractRotationFromMatrix(modelTransform);
    
    // meshVertex.position.w is the only place where it should be one,
    // as we transform it with various matrices, the translation will
    // not work as expected if we modify the w-component
    float4 modelPos = modelTransform * meshVertex.position;
    float4 modelNorm = modelTransformRotOnly * float4(meshVertex.normal, 0.0f);
    
    // Note: w-component must start as ZERO!!!
    float4 pos = float4(0);
    float4 norm = float4(0,0,0,0);
    
    bool movedByBone = false;
    for(int i = 0; i < 4; i++) {
        const VertexBoneWeight bw = meshVertex.boneWeights[i];
        if(bw.boneIndex == -1) {
            continue;
        }
        float4 localPos = boneTransforms[bw.boneIndex] * modelPos;
        float4 localNorm = boneTransforms[bw.boneIndex] * modelNorm;
        
        pos += bw.weight * localPos;
        norm += bw.weight * localNorm;
        
        movedByBone = true;
    }
    
    if(!movedByBone) {
        pos = modelPos;
        norm = modelNorm;
    }
    
    
    // WHY
    pos = pos / pos.w;
    
    float4 posWS = objectData->model * pos;
    float4 normalWS = objectData->modelRotationOnly * norm;
    
    VertexOut out;
    out.position = cd->projection * cd->view * posWS;
    out.uv = meshVertex.uv;
    out.normal = normalWS.xyz;
    
    // bugged with specific vertices affected by bone. Renders correctly, but throws off light computations drastically.
    // This value is no longer being used as a workaround, rather it's being calculated from
    // the fragment's depth value in the light pass.
    out.positionWS = posWS;
    
    out.posNDC = out.position;
    out.debugColor = meshVertex.debugColor;

    return out;
}

fragment GeometryFragmentOut meshPassFS(VertexOut in [[stage_in]],
                                        texture2d<float> colorTexture [[texture(0)]])
{
    constexpr sampler textureSampler(mag_filter::linear, mag_filter::linear);
    
    float4 colorSample = colorTexture.sample(textureSampler, in.uv);
    
    GeometryFragmentOut out;

    out.albedoSpec = float4(colorSample.xyz, 1.0f);
    out.emission = float4(0.0, 0.0f, 0.0f, 1.0f);
    out.positionWS = in.positionWS; // in.position;
    
    // store linear depth into w-component
    float3 projCoords = in.posNDC.xyz / in.posNDC.w;
    //projCoords = projCoords * 0.5 + float3(0.5, 0.5, 0.5);
    out.positionWS.w = projCoords.z;
    
    out.normalWS = float4(in.normal, 0.0f);
    
    return out;
}
