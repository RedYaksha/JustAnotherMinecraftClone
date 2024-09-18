//
//  Player.h
//  MetalTutorial
//
//  Created by Ronnin Padilla on 8/31/24.
//
#include "Player.hpp"
#import "AAPLMathUtilities.h"
#include <iostream>
#include "EngineInterface.hpp"

using namespace simd;

Player::Player(IEngine* engine, MTL::Device* device)
: engine(engine) {
    nodeManager = AssimpNodeManager("assets/Meshes/Steve/Steve.fbx", 1.0f);
    animator = Animator(&nodeManager);
    animator.setAnimationOrder({
        "Armature|Walk",
        "Armature|Crouch",
        "Armature|Hit",
    });
    
    const std::vector<MeshUnit>& meshUnits = nodeManager.getMeshUnits();
    const std::vector<AssimpNode>& nodes = nodeManager.getNodes();
    const std::vector<Bone>& bones = nodeManager.getBones();
    
    int muInd = -1;
    for(const auto& mu : meshUnits) {
        muInd++;
        
        assert(mu.positions.size() == mu.normals.size());
        assert(mu.positions.size() == mu.uvs.size());
        
        for(int i = 0; i < (int) mu.positions.size(); i++) {

            SkeletalMeshVertexData v;
            v.position = mu.positions[i];
            v.normal = mu.normals[i];
            v.uv = mu.uvs[i];
            v.transformationIndex = mu.node;
            v.debugColor = make_float3(0);
            int boneWeightsAdded = 0;
            
            // vidToBoneWeights is local wrt the MeshUnit
            if(mu.vidToBoneWeights.contains(i)) {
                auto boneWeights = mu.vidToBoneWeights.at(i);
                for(; boneWeightsAdded < (int) boneWeights.size(); boneWeightsAdded++) {
                    if(boneWeightsAdded >= 4) { // max bone weights per vertex // todo: should be a const... or actually shader defines this
                        break;
                    }
                    
                    const int bwIndex = boneWeightsAdded;
                    assert(bwIndex >= 0 && bwIndex < 4);
                    v.boneWeights[bwIndex].weight = boneWeights[bwIndex].weight;
                    v.boneWeights[bwIndex].boneIndex = boneWeights[bwIndex].boneId;
                    assert(v.boneWeights[bwIndex].boneIndex < bones.size());
                    
                }
            }
            
            // initialize weight to zero for the slots not needed
            for(; boneWeightsAdded < 4; boneWeightsAdded++) {
                v.boneWeights[boneWeightsAdded].weight = 0.0f;
                v.boneWeights[boneWeightsAdded].boneIndex = -1;
            }
            
            vertices.push_back(v);
        }
    }
    
    indices = nodeManager.createSingleBufferIndices();
    meshTransforms = nodeManager.createNodeModelTransforms();
    
    boneTransforms.resize(bones.size());
    
    for(int i = 0; i < nodes.size(); i++) {
        auto node = nodes[i];
        float4x4 mt = nodeManager.calculateModelTransform(i);
        
        int boneId = nodeManager.getBoneId(node.name);
        
        if(boneId >= 0) {
            //boneTransforms[boneId] = mt * bones[boneId].offsetMat;
            boneTransforms[boneId] = matrix4x4_identity();
        }
    }
    
    // load mesh data into buffers
    meshVB = device->newBuffer(vertices.data(), vertices.size() * sizeof(SkeletalMeshVertexData), MTL::ResourceStorageModeShared);
    meshIB = device->newBuffer(indices.data(), indices.size() * sizeof(uint32_t), MTL::ResourceStorageModeShared);
    meshTexture = new Texture("assets/Meshes/Steve/diffuse.png", device, STBI_rgb);
    meshTransformsUB = device->newBuffer(meshTransforms.data(), meshTransforms.size() * sizeof(float4x4), MTL::ResourceStorageModeShared);
    boneTransformsUB = device->newBuffer(boneTransforms.data(), boneTransforms.size() * sizeof(float4x4), MTL::ResourceStorageModeShared);
    
    ObjectData od { matrix4x4_identity() };
    objectDataUB = device->newBuffer(&od, sizeof(od), MTL::ResourceStorageModeShared);
    
    // only keep track of the keys we're interested in
    
    position = make_float3(8,24,8);
    rotation = quatf(0, make_float3(0,1,0));
    moveSpeed = 6.f;
    moveSpeedFactor = 1.0f;
    velocity = make_float3(0,0,0);
    force = make_float3(0,0,0);
    prevMovementVel = simd::float3{0,0,0};
                  
    //engine->addLine({0,0,0}, {10,10,10}, 0.25, {1,0,1});
    
    float unitScale = 1.f;
    float4x4 scaleMat = matrix4x4_scale(unitScale, unitScale, unitScale);
    
    for(const auto& b : bones) {
        const auto& node = nodes[b.nodeId];
        
        if(node.children.size() >= 1) {
            const auto& child = nodes[node.children[0]];
            
            float4 zeroVec {0,0,0,1};
            float4 nodeStart = scaleMat * node.modelTransform * zeroVec;
            float4 childStart = scaleMat * child.modelTransform * zeroVec;
            
            int lineId = engine->addLine(nodeStart.xyz, childStart.xyz, 0.05, {1,0,0});
            assert(lineId != -1);
            
            nodeToLineId.insert({node.id, lineId});
        }
    }
    
    initAABB();
}

void Player::tick(float deltaTime, const std::array<bool, 104>& keyDownArr) {
    // tick animation
    animator.tick(deltaTime);
    
    // update uniforms
    const auto& nodes = nodeManager.getNodes();
    const auto& bones = nodeManager.getBones();
    
    for(int i = 0; i < nodes.size(); i++) {
        auto node = nodes[i];
        float4x4 mt = nodeManager.calculateModelTransform(i);
        
        int boneId = nodeManager.getBoneId(node.name);

        if(boneId >= 0) {
            boneTransforms[boneId] = mt * bones[boneId].offsetMat;
            // boneTransforms[boneId] = bones[boneId].offsetMat;
        }
    }
    
    if(boneTransformsUB) {
       memcpy(boneTransformsUB->contents(), boneTransforms.data(), boneTransforms.size() * sizeof(float4x4));
    }
    
    auto isKeyPressed = [&](EKey k)->bool { return keyDownArr.at(k); };
    
    // update rotation
    
    // update forward/right/up
    forward = quaternion_rotate_vector(rotation.vector, make_float3(1,0,0));
    right = normalize(cross(forward, make_float3(0,1,0)));
    up = normalize(cross(right, forward));
    
    // tick movement
    float3 moveDir(0.0f);
    
    if(isKeyPressed(EKey::W)) {
        moveDir = normalize(moveDir + forward);
    }
    if(isKeyPressed(EKey::A)) {
        moveDir = normalize(moveDir - right);
    }
    if(isKeyPressed(EKey::S)) {
        moveDir = normalize(moveDir - forward);
    }
    if(isKeyPressed(EKey::D)) {
        moveDir = normalize(moveDir + right);
    }
    
    // temp 
    if(isKeyPressed(EKey::E)) {
        //moveDir = normalize(moveDir + up);
        if(velocity.y == 0.f) {
            velocity.y = 4.8f;
        }
    }
    
    if(isKeyPressed(EKey::Q)) {
        moveDir = normalize(moveDir - up);
    }
    
    if(isKeyPressed(EKey::J)) {
        rotation *= quatf(0.15, make_float3(0,1,0));
    }
    
    if(isKeyPressed(EKey::Space)) {
        isHitting = true;
    }
    else {
        isHitting = false;
    }
    
    if(isKeyPressed(EKey::LeftShift)) {
        isCrouching = true;
        moveSpeedFactor = 0.25f;
    }
    else {
        isCrouching = false;
        moveSpeedFactor = 1.0f;
    }
    
    // animator.play("Armature|Default", EAnimationLoopType::OnceAndStay);
    
    velocity.x = 0;
    velocity.z = 0;
    
    force = simd::float3 {0,0,0};
    
    bool didMove = !simd_equal(moveDir, make_float3(0,0,0));
    if(didMove) {
        animator.play("Armature|Walk", EAnimationLoopType::Loop);
        
        if(!(isnan(moveDir.x) || isnan(moveDir.y) || isnan(moveDir.z))) {
            //position += moveDir * (moveSpeedFactor * moveSpeed) * deltaTime;
            
            simd::float3 playerMovementVel = moveDir * moveSpeedFactor * moveSpeed;
            prevMovementVel = playerMovementVel;
            velocity += playerMovementVel;
            //force += playerMovementVel;
        }
    }
    else {
        animator.stop("Armature|Walk");
        prevMovementVel = simd::float3 {0,0,0};
    }
    
    if(isCrouching) {
        animator.play("Armature|Crouch", EAnimationLoopType::OnceAndStay);
    }
    else {
        animator.stop("Armature|Crouch");
    }
    
    if(isHitting) {
        animator.play("Armature|Hit", EAnimationLoopType::Loop);
    }
    else {
        animator.stop("Armature|Hit");
    }
    
    
    /*
    else {
        //animator.play("Armature|Armature|Armature|Stance_Heroic", EAnimationLoopType::OnceAndStay);
        animator.pause("Armature|Walk");
        animator.pause("Armature|Hit");
        animator.pause("Armature|Crouch");
    }
    */
    
    
    
    // update model matrix
    float unitScale = 1.f; // note: this is technically an "import scale", since we don't intend attached objects to be scaled by this number...
    float4x4 scaleMat = matrix4x4_scale(unitScale, unitScale, unitScale);
    float4x4 translationMat = matrix4x4_translation(position.x, position.y, position.z);
    float4x4 rotMat = (simd_equal(rotation.vector.xyz, make_float3(0,0,0))) ?
                                matrix4x4_identity() :
                                matrix4x4_rotation(rotation.angle(), rotation.axis());
    
    modelTransform = translationMat * rotMat * scaleMat;
    
    ObjectData od { modelTransform, rotMat };
    memcpy(objectDataUB->contents(), &od, sizeof(od));
    
    for(const auto& [nodeId, lineId] : nodeToLineId) {
        const auto& node = nodes[nodeId];
        if(node.children.size() >= 1) {
            float4x4 nt = nodeManager.calculateModelTransform(node.id);
            float4x4 ct = nodeManager.calculateModelTransform(node.children[0]);
            float4 zeroVec {0,0,0,1};
            float4 nodeStart = modelTransform * nt * zeroVec;
            float4 childStart = modelTransform * ct * zeroVec;
            
            engine->setLineTransform(lineId, nodeStart.xyz, childStart.xyz, 0.05);
        }
    }
    
    drawCollision();
    
    // update aabb world-space
    collisionBounds.setPositionWS(getPosition() + float3{0, -0.75, 0});

    syncHeadTilt();
}

void Player::syncHeadTilt() {
    const std::string headBoneName = "Bone.002";
    int nid = nodeManager.getNodeId(headBoneName);
    
    assert(nid != -1);
    
    float4x4 meshModelMat = nodeManager.calculateModelTransform(nid);

    
    float unitScale = 1.f;
    float4x4 scaleMat = matrix4x4_scale(unitScale, unitScale, unitScale);
    float4x4 translationMat = matrix4x4_translation(position.x, position.y, position.z);
    float4x4 rotMat = (simd_equal(rotation.vector.xyz, make_float3(0,0,0))) ?
                                matrix4x4_identity() :
                                matrix4x4_rotation(rotation.angle(), rotation.axis());
    
    float4x4 modelMat = translationMat * rotMat * scaleMat;
    
    float4 headPosWS = modelMat * meshModelMat * make_float4(0.125,0,0,1);

    float4x4 headRotMat = matrix4x4_rotation(radians_from_degrees(lookPitch), simd::float3{0,0,1});

    const AssimpNode& node = nodeManager.getNodes()[nid];


    animator.setNodeTransformOverride(nid, node.ogRelativeTransform * headRotMat);
}

float3 Player::getHeadPosition() const {
    const std::string headBoneName = "Bone.002";
    int nid = nodeManager.getNodeId(headBoneName);
    
    assert(nid != -1);
    
    float4x4 meshModelMat = nodeManager.calculateModelTransform(nid);
    
    float unitScale = 1.f;
    float4x4 scaleMat = matrix4x4_scale(unitScale, unitScale, unitScale);
    float4x4 translationMat = matrix4x4_translation(position.x, position.y, position.z);
    float4x4 rotMat = (simd_equal(rotation.vector.xyz, make_float3(0,0,0))) ?
                                matrix4x4_identity() :
                                matrix4x4_rotation(rotation.angle(), rotation.axis());
    
    float4x4 modelMat = translationMat * rotMat * scaleMat;
    
    float4 headPosWS = modelMat * meshModelMat * make_float4(0.125,0,0,1);
    
    return headPosWS.xyz;
}

void Player::initAABB() {
    collisionBounds = AABB(simd::float3 {0.5f, 1.f, 0.5f});
    collisionBoxDraw = new DebugBox(engine, collisionBounds, make_float3(1,0,0));
    //testRectDraw = new DebugRect(engine, simd::float2{1,1}, EAxis::Z, simd::float3 {0,1,0} );
}

void Player::drawCollision() {
    //float3 collisionOffset = float3{0, -0.5, 0};
    //float4x4 collisionMat = matrix4x4_translation(getPosition() + collisionOffset);
    // collisionBoxDraw->draw(collisionBounds);
    
    //float4x4 t = matrix4x4_translation(getPosition());
    //testRectDraw->draw(t);
}
