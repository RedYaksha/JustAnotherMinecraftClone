#pragma once
#include <simd/simd.h>

#include "Core/Mesh/AssimpNodeManager.hpp"
#include "Core/Mesh/Animator.hpp"
#include "VertexDataTypes.hpp"
#include "Core/Texture.hpp"
#include "Core/CoreTypes.hpp"
#include <map>
#include <array>
#include "Physics/PhysicsCoreTypes.hpp"
#include "Core/Drawables.hpp"

class IEngine;

class Player {
public:
    Player(IEngine* engine, MTL::Device* device);
    
    void tick(float deltaTime, const std::array<bool, 104>& keyDownArr);
    void syncHeadTilt();
    
    // need to bind these during rendering
    MTL::Buffer* getVertexBuffer() const { return meshVB; }
    MTL::Buffer* getIndexBuffer() const { return meshIB; }
    int getIndexBufferSize() const { return (int) indices.size(); }
    MTL::Texture* getMeshTexture() const { return meshTexture->texture; }
    MTL::Buffer* getMeshTransformsUB() const { return meshTransformsUB; }
    MTL::Buffer* getBoneTransformsUB() const { return boneTransformsUB; }
    MTL::Buffer* getObjectDataUB() const { return objectDataUB; }
    
    void setPosition(simd::float3 inPos) {
        position = inPos;
    }
    void setRotation(simd::quatf inRot) { rotation = inRot; }
    void setVelocity(simd::float3 inVel) {
        if(!(isnan(inVel.x) || isnan(inVel.y) || isnan(inVel.z))) {
            velocity = inVel;
            
            if(velocity.y < -50)
                velocity.y = -50;
        }
    }
    void setForce(simd::float3 inVel) {
        if(!(isnan(inVel.x) || isnan(inVel.y) || isnan(inVel.z))) {
            force = inVel;
        }
    }
    void setLookForward(simd::float3 inForward) { lookForward = inForward; }
    void setLookPitch(float inPitch) { lookPitch = std::max(std::min(inPitch, 80.0f), -60.0f); }
    
    simd::float3 getForwardVector() const { return forward; }
    simd::float3 getRightVector() const { return right; }
    simd::float3 getUpVector() const { return up; }
    simd::float3 getPosition() const { return position; }
    simd::quatf getRotation() const { return rotation; }
    simd::float3 getHeadPosition() const;
    const AABB& getCollision() const { return collisionBounds; }
    AABB& getCollisionRef() { return collisionBounds; }
    simd::float3 getVelocity() const { return velocity; }
    simd::float3 getPrevMovementVel() const { return prevMovementVel; }
    simd::float3 getForce() const { return force; }
    float getLookPitchDeg() const { return lookPitch; }
    float getLookPitchRad() const { return radians_from_degrees(lookPitch); }
    
private:
    void initAABB();
    void drawCollision();
    
    simd::float3 position;
    simd::quatf rotation;
    
    simd::float3 velocity;
    simd::float3 force;
    
    simd::float3 lookForward;
    float lookPitch;

    simd::float3 forward;
    simd::float3 right;
    simd::float3 up;
    
    bool isHitting;
    bool isCrouching;
    
    simd::float3 curMoveDir;
    float moveSpeed;
    float moveSpeedFactor;
    simd::float3 prevMovementVel;
    
    AssimpNodeManager nodeManager;
    Animator animator;
    
    std::vector<SkeletalMeshVertexData> vertices;
    std::vector<uint32_t> indices;
    std::vector<simd::float4x4> meshTransforms;
    std::vector<simd::float4x4> boneTransforms;
    
    MTL::Buffer* meshVB;
    MTL::Buffer* meshIB;
    Texture* meshTexture;
    
    MTL::Buffer* meshTransformsUB;
    MTL::Buffer* boneTransformsUB;
    MTL::Buffer* objectDataUB;
    
    std::map<EKey, bool> keyDownMap;
    
    std::map<int, int> nodeToLineId;
    
    simd::float4x4 modelTransform;
    
    AABB collisionBounds;
    DebugBox* collisionBoxDraw;
    DebugRect* testRectDraw;
    
    IEngine* engine;
};
