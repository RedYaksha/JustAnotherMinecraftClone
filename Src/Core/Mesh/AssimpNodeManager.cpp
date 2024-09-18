//
//  AssimpNodeManager.cpp
//  MetalTutorial
//
//  Created by Ronnin Padilla on 8/29/24.
//
#include "AssimpNodeManager.hpp"

#include "assimp/Importer.hpp"
#include <assimp/scene.h>
#include <assimp/postprocess.h>

#include <iostream>
#include <queue>
#include "assert.h"

using namespace simd;

AssimpNodeManager::AssimpNodeManager(const char* fp, float importScale)
: filePath(fp), importScale(importScale)
{
    nodes = std::vector<AssimpNode>();
    bones = std::vector<Bone>();
    
    init();
}

void AssimpNodeManager::init() {
    
    Assimp::Importer importer;
    const aiScene *scene = importer.ReadFile(filePath, aiProcess_Triangulate | aiProcess_FlipUVs);
    
    if(!scene || scene->mFlags & AI_SCENE_FLAGS_INCOMPLETE || !scene->mRootNode)
    {
        std::cout << "ERROR::ASSIMP::" << importer.GetErrorString() << std::endl;
        return;
    }
    
    aiMatrix4x4 fixMat;
    
    if (scene->mMetaData)
    {
        int32_t UpAxis = 1, UpAxisSign = 1, FrontAxis = 2, FrontAxisSign = 1, CoordAxis = 0, CoordAxisSign = 1;
        double UnitScaleFactor = 1.0;
        for (unsigned MetadataIndex = 0; MetadataIndex < scene->mMetaData->mNumProperties; ++MetadataIndex)
        {
            if (strcmp(scene->mMetaData->mKeys[MetadataIndex].C_Str(), "UpAxis") == 0)
            {
                scene->mMetaData->Get<int32_t>(MetadataIndex, UpAxis);
            }
            if (strcmp(scene->mMetaData->mKeys[MetadataIndex].C_Str(), "UpAxisSign") == 0)
            {
                scene->mMetaData->Get<int32_t>(MetadataIndex, UpAxisSign);
            }
            if (strcmp(scene->mMetaData->mKeys[MetadataIndex].C_Str(), "FrontAxis") == 0)
            {
                scene->mMetaData->Get<int32_t>(MetadataIndex, FrontAxis);
            }
            if (strcmp(scene->mMetaData->mKeys[MetadataIndex].C_Str(), "FrontAxisSign") == 0)
            {
                scene->mMetaData->Get<int32_t>(MetadataIndex, FrontAxisSign);
            }
            if (strcmp(scene->mMetaData->mKeys[MetadataIndex].C_Str(), "CoordAxis") == 0)
            {
                scene->mMetaData->Get<int32_t>(MetadataIndex, CoordAxis);
            }
            if (strcmp(scene->mMetaData->mKeys[MetadataIndex].C_Str(), "CoordAxisSign") == 0)
            {
                scene->mMetaData->Get<int32_t>(MetadataIndex, CoordAxisSign);
            }
            if (strcmp(scene->mMetaData->mKeys[MetadataIndex].C_Str(), "UnitScaleFactor") == 0)
            {
                scene->mMetaData->Get<double>(MetadataIndex, UnitScaleFactor);
            }
        }

        aiVector3D upVec, forwardVec, rightVec;

        upVec[UpAxis] = UpAxisSign * (float)UnitScaleFactor;
        forwardVec[FrontAxis] = FrontAxisSign * (float)UnitScaleFactor;
        rightVec[CoordAxis] = CoordAxisSign * (float)UnitScaleFactor;

        aiMatrix4x4 mat(rightVec.x, rightVec.y, rightVec.z, 0.0f,
            upVec.x, upVec.y, upVec.z, 0.0f,
            forwardVec.x, forwardVec.y, forwardVec.z, 0.0f,
            0.0f, 0.0f, 0.0f, 1.0f);

        scene->mRootNode->mTransformation = mat;
        
        axisFixMat = mat;
    }
    
    aiMatrix4x4 mat(importScale, 0, 0, 0.0f,
                    0, importScale, 0, 0.0f,
                    0, 0, importScale, 0.0f,
                    0.0f, 0.0f, 0.0f, 1.0f);
    
    // scene->mRootNode->mTransformation = mat * scene->mRootNode->mTransformation;
    
    
    struct RawQNode {
        RawQNode(int p, aiNode* n) : parent(p), assimpNode(n) {}
        int parent;
        aiNode* assimpNode;
    };
    
    std::vector<aiNode*> rawNodes;
    
    // setup node array structure
    {
        std::queue<RawQNode> nodeQueue;
        nodeQueue.push(RawQNode(-1, scene->mRootNode));
        
        while(!nodeQueue.empty()) {
            const RawQNode curQNode = nodeQueue.front();
            nodeQueue.pop();
            
            AssimpNode newNode;
            newNode.id = (int) nodes.size();
            newNode.name = std::string(curQNode.assimpNode->mName.C_Str());
            newNode.parent = curQNode.parent;
            newNode.relativeTransform = convertAssimpMatrix(curQNode.assimpNode->mTransformation);
            // we can calculate this right now since we start from the root
            newNode.modelTransform = calculateModelTransform(newNode.parent) * newNode.relativeTransform;
            newNode.ogRelativeTransform = newNode.relativeTransform;
            
            
            nodeNameToId[newNode.name] = newNode.id;
            
            nodes.push_back(newNode);
            rawNodes.push_back(curQNode.assimpNode);
            const int lastInsertedIndex = (int) nodes.size() - 1;
            
            if(newNode.parent != -1)
                nodes[newNode.parent].children.push_back(lastInsertedIndex);
            
            for(int i = 0; i < (int) curQNode.assimpNode->mNumChildren; i++) {
                nodeQueue.push(RawQNode(lastInsertedIndex, curQNode.assimpNode->mChildren[i]));
            }
        }
    }
    
    // create mesh units
    for(int ni = 0; ni < (int) rawNodes.size(); ni++) {
        const aiNode* n = rawNodes[ni];
        
        if(n->mNumMeshes <= 0) {
            continue;
        }
        
        for(int mi = 0; mi < n->mNumMeshes; mi++) {
            const aiMesh* mesh = scene->mMeshes[n->mMeshes[mi]];
            
            MeshUnit mu;
            mu.node = ni; // link back to which node this mesh unit is originating from
            
            mu.indices.clear();
            mu.positions.clear();
            mu.normals.clear();
            mu.uvs.clear();
            mu.vidToBoneWeights.clear();
            
            // vertex, normals, uvs
            for(unsigned int vi = 0; vi < mesh->mNumVertices; vi++)
            {
                float4 pos {
                    mesh->mVertices[vi].x,
                    mesh->mVertices[vi].y,
                    mesh->mVertices[vi].z,
                    1.0f
                };
                
                float3 norm {
                    mesh->mNormals[vi].x,
                    mesh->mNormals[vi].y,
                    mesh->mNormals[vi].z
                };
                
                float2 uv {
                    mesh->mTextureCoords[0][vi].x,
                    mesh->mTextureCoords[0][vi].y
                };
                
                mu.positions.push_back(pos);
                mu.normals.push_back(norm);
                mu.uvs.push_back(uv);
                
                // bone weights
                
            }
            
            // indices (local to mesh unit)
            for(unsigned int fi = 0; fi < mesh->mNumFaces; fi++)
            {
                aiFace face = mesh->mFaces[fi];
                for(unsigned int ii = 0; ii < face.mNumIndices; ii++) {
                    mu.indices.push_back(face.mIndices[ii]);
                }
            }
            
            // bone weights
            for(int bi = 0; bi < mesh->mNumBones; bi++) {
                const aiBone* bone = mesh->mBones[bi];
                
                // we init bones here as we encounter them
                ensureBoneRegistered(bone);
                
                const int boneId = getBoneId(bone->mName.C_Str());
                assert(boneId >= 0);
                
                for(int wi = 0; wi < bone->mNumWeights; wi++) {
                    const aiVertexWeight vertexWeight = bone->mWeights[wi];
                    mu.vidToBoneWeights[vertexWeight.mVertexId].push_back({boneId, vertexWeight.mWeight});
                }
            }
            
            meshUnits.push_back(mu);
        }
    }
    
    // link bones to node
    for(const auto& n : nodes) {
        int bid = getBoneId(n.name);
        if(bid == -1) {
            continue;
        }
        
        bones[bid].nodeId = n.id;
    }
    
    initAnimations(scene);
}

void AssimpNodeManager::initAnimations(const aiScene *scene) {
    for(int i = 0; i < scene->mNumAnimations; i++) {
        const aiAnimation* anim = scene->mAnimations[i];
        
        Animation newAnim;
        newAnim.name = std::string(anim->mName.C_Str());
        newAnim.duration = anim->mDuration;
        newAnim.ticksPerSecond = anim->mTicksPerSecond;
        
        for(int c = 0; c < anim->mNumChannels; c++) {
            const aiNodeAnim* nodeAnim = anim->mChannels[c];
            
            BoneAnimationSet animSet;
            animSet.boneId = getBoneId(std::string(nodeAnim->mNodeName.C_Str()));
            animSet.nodeId = getNodeId(std::string(nodeAnim->mNodeName.C_Str()));
            
            for(int k=0; k < nodeAnim->mNumPositionKeys; k++) {
                const aiVectorKey key = nodeAnim->mPositionKeys[k];
                animSet.positionKeys.push_back({key.mTime, convertAssimpVector3(key.mValue)});
            }
            for(int k=0; k < nodeAnim->mNumRotationKeys; k++) {
                const aiQuatKey key = nodeAnim->mRotationKeys[k];
                animSet.rotationKeys.push_back({key.mTime, convertAssimpQuat3(key.mValue)});
            }
            for(int k=0; k < nodeAnim->mNumScalingKeys; k++) {
                const aiVectorKey key = nodeAnim->mScalingKeys[k];
                animSet.scalingKeys.push_back({key.mTime, convertAssimpVector3(key.mValue)});
            }
            
            newAnim.animationSets.push_back(animSet);
        }
        
        
        animations.push_back(newAnim);
    }
}

float4x4 AssimpNodeManager::convertAssimpMatrix(aiMatrix4x4 m) {
    
    /*
    float4x4 to = (matrix_float4x4) {{
        {m.a1, m.a2, m.a3, m.a4},
        {m.b1, m.b2, m.b3, m.b4},
        {m.c1, m.c2, m.c3, m.c4},
        {m.d1, m.d2, m.d3, m.d4}
    }};
    */
    
    float4x4 to = (matrix_float4x4) {{
        {m.a1, m.b1, m.c1, m.d1},
        {m.a2, m.b2, m.c2, m.d2},
        {m.a3, m.b3, m.c3, m.d3},
        {m.a4, m.b4, m.c4, m.d4}
    }};
    
    /*
    float4x4 to = (matrix_float4x4) {{
        {m.a1, m.c1, m.b1, m.d1},
        {m.a2, m.c2, m.b2, m.d2},
        {m.a3, m.c3, m.b3, m.d3},
        {m.a4, m.c4, m.b4, m.d4}
    }};
    */
    
    
    /*
    float4x4 to = (matrix_float4x4) {{
        {1, 0, 0, 0},
        {0, 1, 0, 0},
        {0, 0, 1, 0},
        {m.a4, m.b4, m.c4, 1}
    }};
    */
    
    
    return to;
}

float3 AssimpNodeManager::convertAssimpVector3(aiVector3D v) {
    return make_float3(v.x, v.y, v.z);
}

quatf AssimpNodeManager::convertAssimpQuat3(aiQuaternion q) {
    return quatf(q.x, q.y, q.z, q.w); // TODO order?
}


float4x4 AssimpNodeManager::calculateModelTransform(int nodeId) const {
    if(nodeId == -1) {
        return float4x4(1.0f);
    }
    
    const AssimpNode curNode = nodes[nodeId];
    
    return calculateModelTransform(curNode.parent) * curNode.relativeTransform;
}

std::vector<uint32_t> AssimpNodeManager::createSingleBufferIndices() const {
    std::vector<uint32_t> outIndices;
    int indexOffset = 0;
    for(int i = 0; i < (int) meshUnits.size(); i++) {
        
        for(const auto ind : meshUnits[i].indices) {
            outIndices.push_back(indexOffset + ind);
        }
        
        indexOffset += (int) meshUnits[i].positions.size();
    }
    return outIndices;
}

std::vector<float4x4> AssimpNodeManager::createNodeModelTransforms() const {
    std::vector<float4x4> outT;
    for(int i = 0; i < (int) nodes.size(); i++) {
        outT.push_back(nodes[i].modelTransform);
    }
    return outT;
}

void AssimpNodeManager::ensureBoneRegistered(const aiBone *bone) {
    std::string boneName = bone->mName.C_Str();
    
    if(boneNameToId.contains(boneName)) {
        return;
    }
    
    Bone newBone;
    newBone.name = boneName;
    newBone.id = (int) bones.size();
    newBone.offsetMat = convertAssimpMatrix(axisFixMat * bone->mOffsetMatrix);
    
    boneNameToId[boneName] = newBone.id;
    bones.push_back(newBone);
}

const int AssimpNodeManager::getBoneId(std::string name) const {
    if(!boneNameToId.contains(name)) {
        return -1;
    }
    return boneNameToId.at(name);
}

const int AssimpNodeManager::getNodeId(std::string name) const {
    if(!nodeNameToId.contains(name)) {
        return -1;
    }
    return nodeNameToId.at(name);
}

bool AssimpNodeManager::findAnimation(std::string animationName, Animation& outAnimation) {
    for(const auto& a : animations) {
        if(a.name == animationName) {
            outAnimation = a;
            return true;
        }
    }
    
    return false;
}

void AssimpNodeManager::setNodeTransform(int nodeId, float4x4 transform) {
    nodes[nodeId].relativeTransform = transform;
}

void AssimpNodeManager::setNodeTransformByBone(int boneId, float4x4 transform) {
    setNodeTransform(bones[boneId].nodeId, transform);
}
