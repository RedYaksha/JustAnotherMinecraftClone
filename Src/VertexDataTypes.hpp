#pragma once
#include <simd/simd.h>

// geometry pass
// TODO: rename to voxel VertexData
struct VertexData {
    simd::float4 position;
    simd::float2 textureCoordinates;
    simd::float3 normal;
    int atlasIndex;
    simd::float3 colorScale;
};

struct MeshVertexData {
    simd::float4 position;
    simd::float3 normal;
    simd::float2 uv;
    int transformationIndex;
};

struct VertexBoneWeight {
    int boneIndex;
    float weight;
};

struct SkeletalMeshVertexData {
    simd::float4 position;
    simd::float3 normal;
    simd::float2 uv;
    
    simd::float3 debugColor;
    
    VertexBoneWeight boneWeights[4];
    
    int transformationIndex;
};

struct PositionVertexData {
    simd::float4 position;
};

// data that the instanced-rendered light spheres will use
struct LightVolumeData {
    simd::float4x4 localToWorld; // embeds radius & positions here
    simd::float4 color;
};

struct SkyBoxCubeVertexData {
    simd::float4 position;
    simd::float4 normal;
};

// a struct just enough to render a simple quad
struct LightingPassVertexData {
    simd::float4 position;
    simd::float2 uv;
};

struct SimpleVertexData {
    simd::float4 position;
    simd::float2 uv;
};

// 
struct ShadowPassVertexData {
    simd::float4 position;
};

struct TransformationData {
    simd::float4x4 model;
    simd::float4x4 view;
    simd::float4x4 perspective;
    simd::float4x4 normalMat; // (view^-1)^T
};

struct Wrapper {
    simd::float4x4 r;
};


struct LineVertexData {
    simd::float4 position;
};

struct LineData {
    simd::float4x4 transform;
    simd::float3 color;
    simd::float3 axis;
    bool visible;
};

struct CameraData {
    simd::float4 position; // WS
    simd::float4 zPlaneRange;
    
    simd::float4x4 view;
    simd::float4x4 projection;
    simd::float4x4 normalMat;
    
    simd::float4x4 invProjection;
    simd::float4x4 invView;
};

struct ObjectData {
    simd::float4x4 model; // local to ws
    simd::float4x4 modelRotationOnly; // use for normals
};

struct MeshTransform {
    simd::float4x4 mat; // local to mesh
    simd::float4x4 matRotOnly; // for normals
};

struct RenderState {
    bool useSSAO;
    bool useShadowMap;
};

struct GaussianBlurState {
    bool horizontal;
};


