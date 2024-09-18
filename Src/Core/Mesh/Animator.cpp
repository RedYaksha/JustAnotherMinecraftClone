
//
//  Animator.hpp
//  MetalTutorial
//
//  Created by Ronnin Padilla on 8/30/24.
//
#include "Animator.hpp"
#include <vector>
#import "AAPLMathUtilities.h"
#include <iostream>

using namespace simd;

void Animator::play(std::string animationName, EAnimationLoopType loopType) {
    // register animation if we haven't seen it yet
    if(!animationStates.contains(animationName)) {
        AnimationState animState;
        animState.name = animationName;
        
        bool foundAnimation = nodeManager->findAnimation(animationName, animState.animation);
        if(!foundAnimation) {
            std::cout << "ERROR: Couldn't find animation: " << animationName << std::endl;
            return;
        }
        
        animState.isPlaying = false;
        animState.curTime = 0.0f;
        animState.loopType = loopType;
        
        for(const auto& as : animState.animation.animationSets) {
            animState.nodesBeingAnimated.insert(as.nodeId);
        }
        
        animationStates.insert({animationName, animState});
    }
    
    AnimationState& animState = animationStates[animationName];
    if(!animState.isPlaying) {
        animState.playInvocation = currentPlayInvocation++;
    }
    animState.isPlaying = true;
    animState.loopType = loopType;
    
}

void Animator::pause(std::string animationName) {
    if(!animationStates.contains(animationName)) {
        return;
    }
    animationStates[animationName].isPlaying = false;
}

void Animator::stop(std::string animationName) {
    if(!animationStates.contains(animationName)) {
        return;
    }
    animationStates[animationName].isPlaying = false;
    animationStates[animationName].curTime = 0.0f;
}

void Animator::tick(float deltaTime) {
    perTickAnimatedNodes.clear();
    
    const auto& nodes = nodeManager->getNodes();
    const auto& bones = nodeManager->getBones();
    
    // tend to the original bind pose - will be replace by any subsequent animations
    // This is a workaround for Blender simplifying any "pose" type animations
    // (i.e all keyframes that don't change in value are omitted)...
    //      => this will still be an issue when we introduce more static "poses" (e.g. sitting)
    //          - the only foreseeable solution is to support export of all blender actions
    //            with all of their keyframes. But with that, blending won't be as easy as it works right now
    //            and all actions would need to somehow denote the "important" bones used in the animation
    //
    // Perhaps, any action with "Pose_" in the name will keep all of its keyframes, otherwise we
    // will omit unchanging keyframes
    for(int bid = 0; bid < (int) bones.size(); bid++) {
        int nid = bones[bid].nodeId;
        
        AnimatedNodeInfo info;
        info.nodeId = nid;
        info.animationName = "BindPose";
        info.finalTransform = nodes[nid].ogRelativeTransform;
        info.playInvocation = -1;
        
        perTickAnimatedNodes[nid].push_back(info);
    }
    
    
    for(const auto& key : animationOrder) {
        if(animationStates.contains(key)) {
            tickAnimationState(deltaTime, animationStates.at(key));
        }
        else {
            // std::cout << "animation not found: " << key << std::endl;
        }
    }
    
    
    for(int nid = 0; nid < (int) nodes.size(); nid++) {
        // if this node hasn't been affected, skip
        if(!perTickAnimatedNodes.contains(nid)) {
            continue;
        }

	if(nodeTransformOverrides.contains(nid)) {
	    nodeManager->setNodeTransform(nid, nodeTransformOverrides[nid]);
	    continue;
	}
        
        const std::vector<AnimatedNodeInfo>& animatedNodeInfos = perTickAnimatedNodes.at(nid);
        
        
        // by default our blend mode is "replace" => just use the last set bone transform
        const AnimatedNodeInfo& anim = animatedNodeInfos[animatedNodeInfos.size() - 1];
        nodeManager->setNodeTransform(anim.nodeId, anim.finalTransform);
        
        /*
        
        if(animatedNodeInfos.size() > 2) {
            std::cout << "WARNING: more than 2 nodes are affected by animation blending. " << nodes[nid].name << std::endl;
            continue;
        }
        
        if(animatedNodeInfos.size() == 1) {
            nodeManager->setNodeTransform(animatedNodeInfos[0].nodeId, animatedNodeInfos[0].finalTransform);
        }
        
        else if(animatedNodeInfos.size() == 2) {
            std::string AnimationWalkId = "Armature|Walk";
            std::string AnimationCrouchId = "Armature|Crouch";
            std::string AnimationHitId = "Armature|Hit";
            std::string AnimationDefaultId = "Armature|Default";

            
            const AnimatedNodeInfo& anim1 = animatedNodeInfos[0];
            const AnimatedNodeInfo& anim2 = animatedNodeInfos[1];
            
            /*
            static std::map<std::string, AnimationBlendData> blendData {
                {
                    AnimationWalkId + AnimationHitId,
                    AnimationBlendData(AnimationWalkId, AnimationHitId, 0.0f, 1.0f)
                },
                {
                    AnimationCrouchId + AnimationHitId,
                    AnimationBlendData(AnimationWalkId, AnimationHitId, 0.0f, 1.0f)
                },
            };
            
            
            
            float weight1 = 0.5f;
            float weight2 = 0.5f;
            
            quatf rot = anim1.rotation;
            
            if(anim1.animationName == AnimationHitId) {
                weight1 = 1.0f;
                weight2 = 0.0f;
                rot = anim1.rotation;
            }
            if(anim2.animationName == AnimationHitId) {
                weight1 = 0.0f;
                weight2 = 1.0f;
                rot = anim2.rotation;
            }
            
            float4x4 weightedFinalTransform;
            
            float3 combinedTranslate = weight1 * anim1.translate + weight2 * anim2.translate;
            quatf combinedRot = (weight1 * anim1.rotation) * (weight2 * anim2.rotation);
            float3 combinedScale = make_float3(1,1,1);
            
            combinedRot = rot;
            
            float4x4 rotMat = matrix4x4_identity();
            if(!simd_equal(combinedRot.vector.xyz, make_float3(0.f) )) {
                rotMat = matrix4x4_rotation(combinedRot.angle(), combinedRot.axis());
            }
            
            float4x4 combinedTransform = matrix4x4_translation(combinedTranslate) * rotMat * matrix4x4_scale(combinedScale);
            
            /*
            if(anim1.playInvocation < anim2.playInvocation) {
                weightedFinalTransform = (0.5 * anim2.finalTransform) * (0.5 * anim1.finalTransform);
            }
            else {
                weightedFinalTransform = (0.5 * anim1.finalTransform) * (0.5 * anim2.finalTransform) ;
            }
            
            
            nodeManager->setNodeTransform(nid, combinedTransform);
        }
        */
    }
    
    /*
    if(!isPlaying) {
        return;
    }
    
    // how many animation "ticks" have passed
    curTick += curAnimation.ticksPerSecond * deltaTime;
    if(curTick >= curAnimation.duration) {
        if(curBehavior == EAnimationLoopType::Loop) {
            curTick = fmodf(curTick, curAnimation.duration);
        }
        else if(curBehavior == EAnimationLoopType::OnceAndStay) {
            curTick = curAnimation.duration;
        }
    }
    
    // update all node transforms that correlate to bones
    for(const auto& animSet : curAnimation.animationSets) {
        //if(animSet.boneId != 2) {
        //    continue;
        //}
        // for each key:
        //      - find the 2 keys we're interpolating between
        //      - linearly interp between their values give their times and the curTime
        float3 curPos = getPositionAtTime(animSet, curTick);
        quatf curRot = getRotationAtTime(animSet, curTick);
        float3 curScale = getScaleAtTime(animSet, curTick);
        
        // if quat is identity, then constructing its axis will be undefined
        //      - so we only calculate it if it's not the identity quaternion
        float4x4 rotMat = matrix4x4_identity();
        if(!simd_equal(curRot.vector.xyz, make_float3(0.f) )) {
            rotMat = matrix4x4_rotation(curRot.angle(), curRot.axis());
        }
        float4x4 curBoneTransform = matrix4x4_translation(curPos) * rotMat * matrix4x4_scale(curScale);
        
        nodeManager->setNodeTransform(animSet.nodeId, curBoneTransform);
    }
    */
    // at this point, all bone-nodes are ready to update the transformation buffer
}

float3 Animator::getPositionAtTime(const BoneAnimationSet& animSet, float time) {
    int posInd = -1;
    for(int i = 0; i < animSet.positionKeys.size(); i++) {
        if(animSet.positionKeys[i].time >= time) {
            posInd = i;
            break;
        }
    }
    
    float3 outPos(0);
    
    if(posInd != 0 && posInd != -1) {
        AnimVectorKey kA = animSet.positionKeys[posInd - 1];
        AnimVectorKey kB = animSet.positionKeys[posInd];
        
        float alpha = (time - kA.time) / (kB.time - kA.time);
        
        outPos = simd_mix(kA.val, kB.val, alpha);
    }
    
    return outPos;
}

quatf Animator::getRotationAtTime(const BoneAnimationSet& animSet, float time) {
    int ind = -1;
    for(int i = 0; i < animSet.rotationKeys.size(); i++) {
        if(animSet.rotationKeys[i].time >= time) {
            ind = i;
            break;
        }
    }
    
    quatf outQuat = quaternion_identity();
    
    if(ind != 0 && ind != -1) {
        AnimQuatKey kA = animSet.rotationKeys[ind - 1];
        AnimQuatKey kB = animSet.rotationKeys[ind];
        
        float alpha = (time - kA.time) / (kB.time - kA.time);
        
        outQuat = slerp(kA.val, kB.val, alpha);
    }
    
    return outQuat;
    
}

float3 Animator::getScaleAtTime(const BoneAnimationSet& animSet, float time) {
    int ind = -1;
    for(int i = 0; i < animSet.scalingKeys.size(); i++) {
        if(animSet.scalingKeys[i].time >= time) {
            ind = i;
            break;
        }
    }
    
    float3 outScale(1);
    
    if(ind != 0 && ind != -1) {
        AnimVectorKey kA = animSet.scalingKeys[ind - 1];
        AnimVectorKey kB = animSet.scalingKeys[ind];
        
        float alpha = (time - kA.time) / (kB.time - kA.time);
        
        outScale = simd_mix(kA.val, kB.val, alpha);
    }
    
    return outScale;
}

void Animator::setNodeTransformOverride(int nid, simd::float4x4 transform) {
    nodeTransformOverrides[nid] = transform;
}

void Animator::tickAnimationState(float deltaTime, AnimationState& anim) {
    if(!anim.isPlaying) {
        return;
    }
    
    anim.curTime += anim.animation.ticksPerSecond * deltaTime;
    
    if(anim.curTime >= anim.animation.duration) {
        if(anim.loopType == EAnimationLoopType::Loop) {
            anim.curTime = fmodf(anim.curTime, anim.animation.duration);
        }
        else if(anim.loopType == EAnimationLoopType::OnceAndStay) {
            anim.curTime = anim.animation.duration;
        }
    }
    
    for(const auto& animSet : anim.animation.animationSets) {
        // for each key:
        //      - find the 2 keys we're interpolating between
        //      - linearly interp between their values give their times and the curTime
        float3 curPos = getPositionAtTime(animSet, anim.curTime);
        quatf curRot = getRotationAtTime(animSet, anim.curTime);
        float3 curScale = getScaleAtTime(animSet, anim.curTime);
        
        // if quat is identity, then constructing its axis will be undefined
        //      - so we only calculate it if it's not the identity quaternion
        float4x4 rotMat = matrix4x4_identity();
        if(!simd_equal(curRot.vector.xyz, make_float3(0.f) )) {
            rotMat = matrix4x4_rotation(curRot.angle(), curRot.axis());
        }
        float4x4 curBoneTransform = matrix4x4_translation(curPos) * rotMat * matrix4x4_scale(curScale);
        
        AnimatedNodeInfo info;
        info.nodeId = animSet.nodeId;
        info.animationName = anim.name;
        info.finalTransform = curBoneTransform;
        info.playInvocation = anim.playInvocation;
        info.translate = curPos;
        info.rotation = curRot;
        info.scale = curScale;
        
        perTickAnimatedNodes[animSet.nodeId].push_back(info);
    }
    
}
