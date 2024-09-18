#pragma once
//
//  Animator.hpp
//  MetalTutorial
//
//  Created by Ronnin Padilla on 8/30/24.
//
#include "AssimpNodeManager.hpp"
#include <string>
#include <set>
#include <map>

enum EAnimationLoopType {
    Loop,
    OnceAndStay
};

struct AnimationState {
    std::string name;
    Animation animation;
    EAnimationLoopType loopType;
    
    std::set<int> nodesBeingAnimated;
    bool isPlaying;
    float curTime;
    
    int playInvocation;
};
/*
struct AnimationBlendData {
    AnimationBlendData(std::string name1, std::string name2, float weight1, float weight2)
    : animName1(name1), animName2(name2), weight1(weight1), weight2(weight2)
    {
        
    }
    
    static std::map<std::string, AnimationBlendData> entries;
    
    static bool findEntry(std::string name1, std::string name2, AnimationBlendData& outData) {
        if(entries.contains(name1 + name2)) {
            outData = entries[name1 + name2];
        }
        else if(entries.contains(name2 + name1)) {
            outData = entries[name2 + name1];
        }
        return false;
    }
    
    std::string animName1;
    std::string animName2;
    float weight1;
    float weight2;
};
*/


class Animator {
public:
    Animator(AssimpNodeManager* nodeManager)
    : nodeManager(nodeManager), currentPlayInvocation(0)
    {
        
    }
    
    Animator() = default;
    
    void setAnimationOrder(std::vector<std::string> order) { animationOrder = order; }
    void play(std::string animationName, EAnimationLoopType behavior);
    void pause(std::string animationName);
    void stop(std::string animationName);
    
    void tick(float deltaTime);
    
    simd::float3 getPositionAtTime(const BoneAnimationSet& animSet, float time);
    simd::quatf getRotationAtTime(const BoneAnimationSet& animSet, float time);
    simd::float3 getScaleAtTime(const BoneAnimationSet& animSet, float time);

    void setNodeTransformOverride(int nid, simd::float4x4 transform);
    void clearNodeTransformOverride(int nid) {
	if(nodeTransformOverrides.find(nid) != nodeTransformOverrides.end()) {
	    nodeTransformOverrides.erase(nid);
	}
    }


    
    AssimpNodeManager* nodeManager;
    
    std::set<int> nodesBeingAnimated;
    
    std::map<std::string, AnimationState> animationStates;
    std::vector<std::string> animationOrder;
    
    
    struct AnimatedNodeInfo {
        int nodeId;
        std::string animationName;
        simd::float4x4 finalTransform;
        int playInvocation;
        
        simd::float3 translate;
        simd::quatf rotation;
        simd::float3 scale;
    };
    
    std::map<int, std::vector<AnimatedNodeInfo>> perTickAnimatedNodes;
    std::map<int, simd::float4x4> nodeTransformOverrides;
    
    int currentPlayInvocation;
private:
    
    void tickAnimationState(float deltaTime, AnimationState& anim);
    
   // bool isPlaying;
   // float curTick;
};
