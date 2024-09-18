//
//  AssimpNodeManager.hpp
//  MetalTutorial
//
//  Created by Ronnin Padilla on 8/29/24.
//
#pragma once 
#include <simd/simd.h>

#include <vector>
#include <string>
#include <assimp/scene.h>
#include <map>


struct AssimpNode {
    int id;
    std::string name;
    int parent;
    simd::float4x4 relativeTransform; // may change when animated
    simd::float4x4 ogRelativeTransform;
    simd::float4x4 modelTransform;
    
    simd::float3 getRelativePosition() const {
        return simd::make_float3(relativeTransform.columns[3][0], relativeTransform.columns[3][1], relativeTransform.columns[3][2]);
    }
    
    simd::float3 getModelPosition() const {
        return simd::make_float3(modelTransform.columns[3][0], modelTransform.columns[3][1], modelTransform.columns[3][2]);
    }
    
    std::vector<int> children;
    
};

struct Bone {
    int id;
    int nodeId; // link to the node representing this bone
    std::string name;
    simd::float4x4 offsetMat; // local to bone space
};

struct BoneWeight {
    int boneId;
    float weight;
};

struct MeshUnit {
    int node;
    
    std::vector<simd::float4> positions;
    std::vector<simd::float2> uvs;
    std::vector<simd::float3> normals;
    
    // vid local to this mesh unit
    std::map<int, std::vector<BoneWeight>> vidToBoneWeights;
    
    std::vector<uint32_t> indices;
};


struct AnimVectorKey {
    double time;
    simd::float3 val;
};

struct AnimQuatKey {
    double time;
    simd::quatf val;
};

struct BoneAnimationSet {
    int nodeId;
    int boneId;
    
    std::vector<AnimVectorKey> positionKeys;
    std::vector<AnimQuatKey> rotationKeys;
    std::vector<AnimVectorKey> scalingKeys;
};


struct Animation {
    std::string name;
    double duration;
    double ticksPerSecond;
    
    std::vector<BoneAnimationSet> animationSets;
};



class AssimpNodeManager {
public:
    AssimpNodeManager(const char* fp, float importScale = 1.0f);
    AssimpNodeManager() = default;
    
    // void releaseIntermediateData();
    static simd::float4x4 convertAssimpMatrix(aiMatrix4x4 mat);
    static simd::float3 convertAssimpVector3(aiVector3D v);
    static simd::quatf convertAssimpQuat3(aiQuaternion q);
    
    simd::float4x4 calculateModelTransform(int nodeId) const;
    std::vector<uint32_t> createSingleBufferIndices() const;
    std::vector<simd::float4x4> createNodeModelTransforms() const;
    const std::vector<MeshUnit>& getMeshUnits() const { return meshUnits; }
    const std::vector<AssimpNode>& getNodes() const { return nodes; }
    const std::vector<Bone>& getBones() const { return bones; }
    const std::vector<Animation>& getAnimations() const { return animations; }
    const int getBoneId(std::string name) const;
    const int getNodeId(std::string name) const;
    bool findAnimation(std::string animationName, Animation& outAnimation);
    void setNodeTransform(int nodeId, simd::float4x4 transform);
    void setNodeTransformByBone(int boneId, simd::float4x4 transform);
    
private:
    void init();
    void initAnimations(const aiScene* scene);
    
    void ensureBoneRegistered(const aiBone* bone);
    
    std::map<std::string, int> boneNameToId;
    std::map<std::string, int> nodeNameToId;
    
    std::vector<Bone> bones;
    std::vector<AssimpNode> nodes;
    std::vector<MeshUnit> meshUnits;
    std::vector<Animation> animations;
    
    std::vector<simd::float4x4> localTransforms; // 1 per mesh unit (only applicable to static meshes/scenes)
    
    
    std::string filePath;
    float importScale;
    aiMatrix4x4 axisFixMat;
};
