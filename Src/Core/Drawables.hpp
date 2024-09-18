#pragma once
#include "EngineInterface.hpp"
#import "AAPLMathUtilities.h"
#include <simd/simd.h>
#include <array>
#include <iostream>
#include "Gameplay/Physics/PhysicsCoreTypes.hpp"

struct Line {
    Line(simd::float3 start, simd::float3 end)
    : start(start), end(end) {}
    simd::float3 start;
    simd::float3 end;
};

class DebugBox {
public:
    static constexpr std::array<simd::float3, 8> baseVertices = {
        simd::float3{-1, -1, -1}, simd::float3{1, -1, -1}, simd::float3{1, -1, 1}, simd::float3{-1, -1, 1}, // bottom
        simd::float3{-1, 1, -1}, simd::float3{1, 1, -1}, simd::float3{1, 1, 1}, simd::float3{-1, 1, 1} // top
    };
    
    static constexpr std::array<int, 32> baseIndices = {
        // bottom face
        0, 1,
        1, 2,
        2, 3,
        3, 0,
        
        // top face
        4, 5,
        5, 6,
        6, 7,
        7, 4,
        
        // sides
        0, 4,
        1, 5,
        2, 6,
        3, 7,
        
        // diagonals
        0, 5,
        1, 6,
        2, 7,
        3, 4
    };
    
    DebugBox(IEngine* engine, const AABB& aabb, simd::float3 color)
    : engine(engine), color(color) {
        simd::float3 aabbCenter = (aabb.minPos + aabb.maxPos) / 2.0f;
        
        extent.x = aabb.maxPos.x - aabbCenter.x;
        extent.y = aabb.maxPos.y - aabbCenter.y;
        extent.z = aabb.maxPos.z - aabbCenter.z;
        
        posOffset = aabbCenter;
        
        initLines();
    }
    
    DebugBox(IEngine* engine, simd::float3 extent, simd::float3 color)
    : engine(engine), extent(extent), color(color), posOffset(simd::float3 {0,0,0}) {
        
        initLines();
       
    }
    
    void draw(simd::float4x4 modelMat) {
        simd::float4x4 extentScale = matrix4x4_scale(extent);
        simd::float4x4 boxOffset = matrix4x4_translation(posOffset);
        
        // update lines
        for(int i = 0; i < baseIndices.size(); i+=2) {
            simd::float3 baseStartPos = baseVertices[baseIndices[i]];
            simd::float3 baseEndPos = baseVertices[baseIndices[i + 1]];
            simd::float4 startPos = modelMat * boxOffset * extentScale * simd::make_float4(baseStartPos.x, baseStartPos.y, baseStartPos.z, 1.0f);
            simd::float4 endPos = modelMat * boxOffset * extentScale * simd::make_float4(baseEndPos.x, baseEndPos.y, baseEndPos.z, 1.0f);;
            
            engine->setLineTransform(lineIds[i/2], startPos.xyz, endPos.xyz, 0.025);
            engine->setLineVisibility(lineIds[i/2], true);
        }
    }
    
    void draw(const AABB aabb) {
        simd::float3 aabbCenter = (aabb.minPosWS + aabb.maxPosWS) / 2.0f;
        
        extent.x = aabb.maxPosWS.x - aabbCenter.x;
        extent.y = aabb.maxPosWS.y - aabbCenter.y;
        extent.z = aabb.maxPosWS.z - aabbCenter.z;
        
        posOffset = aabbCenter;
        
        draw(matrix4x4_identity());
    }
    
    void setVisibility(bool val) {
        for(int i = 0; i < baseIndices.size(); i+=2) {
            engine->setLineVisibility(lineIds[i/2], val);
        }
    }
    
private:
    
    void initLines() {
        for(int i = 0; i < baseIndices.size(); i+=2) {
            
            lineIds[i / 2] = engine->addLine(
                                         baseVertices[baseIndices[i]],
                                         baseVertices[baseIndices[i + 1]],
                                         0.025,
                                         color
                                         );
        }
    }
    
    IEngine* engine;
    simd::float3 extent;
    simd::float3 color;
    simd::float3 posOffset;
    std::array<int, 16> lineIds;
};

class DebugRect {
public:
    static constexpr std::array<simd::float3, 4> baseVertices = {
        simd::float3{-1, -1, 0}, simd::float3{1, -1, 0}, simd::float3{1, 1, 0}, simd::float3{-1, 1, 0}, // bottom
    };
    
    static constexpr std::array<int, 10> baseIndices = {
        // face
        0, 1,
        1, 2,
        2, 3,
        3, 0,
        
        // diagonal
        3, 1
    };

    DebugRect(IEngine* engine, simd::float3 color) 
    : engine(engine), color(color) 
    {
	normal = EAxis::X;
	extent = simd::float2 {1,1};
	posOffset = simd::float3 {0,0,0};
	initLines();
    }
    
    DebugRect(IEngine* engine, const CollisionRect& rect, simd::float3 color)
    : engine(engine), color(color), normal(rect.normal) {
        simd::float2 center = (rect.minPos + rect.maxPos) / 2.0f;
        
        extent.x = rect.maxPos.x - center.x;
        extent.y = rect.maxPos.y - center.y;

        if(normal == EAxis::X) {
            posOffset.x = rect.normalOffset;
            posOffset.z = center.x;
            posOffset.y = center.y;
        }
        else if(normal == EAxis::Y) {
            posOffset.x = center.x;
            posOffset.y = rect.normalOffset;
            posOffset.z = center.y;
        }
        else if(normal == EAxis::Z) {
            posOffset.x = center.x;
            posOffset.y = center.y;
            posOffset.z = rect.normalOffset;
        }
        /*
        
        std::cout << "Adding Debug Rect: " << std::endl;
        std::cout << "    MaxPos: " << rect.maxPos.x << ", " << rect.maxPos.y << std::endl;
        std::cout << "    MinPos: " << rect.minPos.x << ", " << rect.minPos.y << std::endl;
        std::cout << "    Center: " << center.x << ", " << center.y << std::endl;
        std::cout << "    Extent: " << extent.x << ", " << extent.y << std::endl;
        std::cout << "    Normal: " << normal << std::endl;
        */
        
        initLines();
    }
    
    DebugRect(IEngine* engine, simd::float2 extent, EAxis normal, simd::float3 color)
    : engine(engine), extent(extent), normal(normal), color(color), posOffset(simd::float3 {0,0,0}) {
    
        initLines();
        
    }
    
    void setColor(simd::float3 color) {
        for(const int& id : lineIds) {
            engine->setLineColor(id, color);
        }
    }
    
    void draw(simd::float4x4 modelMat) {
        simd::float4x4 extentScale = matrix4x4_scale(extent.x, extent.y, 1.0f);
        simd::float4x4 boxOffset = matrix4x4_translation(posOffset);
        simd::float4x4 rot = matrix4x4_identity();
        
        simd::float3 unitX = simd::float3 {1,0,0};
        simd::float3 unitY = simd::float3 {0,1,0};
        simd::float3 unitZ = simd::float3 {0,0,1};
        
        if(normal == EAxis::X) {
            rot = matrix4x4_rotation(M_PI / 2, unitY);
        }
        else if(normal == EAxis::Y) {
            rot = matrix4x4_rotation(M_PI / 2, unitX);
        }
        else if(normal == EAxis::Z) {
            rot = matrix4x4_identity(); // vertices are defined with normal as +Z
        }
        
        // update lines
        for(int i = 0; i < baseIndices.size(); i+=2) {
            simd::float3 baseStartPos = baseVertices[baseIndices[i]];
            simd::float3 baseEndPos = baseVertices[baseIndices[i + 1]];
            simd::float4 startPos = modelMat * boxOffset * rot * extentScale * simd::make_float4(baseStartPos.x, baseStartPos.y, baseStartPos.z, 1.0f);
            simd::float4 endPos = modelMat * boxOffset * rot * extentScale * simd::make_float4(baseEndPos.x, baseEndPos.y, baseEndPos.z, 1.0f);;
            
            engine->setLineTransform(lineIds[i/2], startPos.xyz, endPos.xyz, 0.025);
            engine->setLineVisibility(lineIds[i/2], true);
        }
    }
    
    void draw(const CollisionRect& rect) {
	normal = rect.normal;

        simd::float2 center = (rect.minPos + rect.maxPos) / 2.0f;
        
        extent.x = rect.maxPos.x - center.x;
        extent.y = rect.maxPos.y - center.y;

        if(normal == EAxis::X) {
            posOffset.x = rect.normalOffset;
            posOffset.z = center.x;
            posOffset.y = center.y;
        }
        else if(normal == EAxis::Y) {
            posOffset.x = center.x;
            posOffset.y = rect.normalOffset;
            posOffset.z = center.y;
        }
        else if(normal == EAxis::Z) {
            posOffset.x = center.x;
            posOffset.y = center.y;
            posOffset.z = rect.normalOffset;
        }

	draw(matrix4x4_identity());
    }
    
    void setVisibility(bool val) {
        for(int i = 0; i < baseIndices.size(); i+=2) {
            engine->setLineVisibility(lineIds[i/2], val);
        }
    }
    
private:
    
    void initLines() {
        simd::float4x4 extentScale = matrix4x4_scale(extent.x, extent.y, 1.0f);
        simd::float4x4 boxOffset = matrix4x4_translation(posOffset);
        
        simd::float4x4 rot = matrix4x4_identity();
        
        simd::float3 unitX = simd::float3 {1,0,0};
        simd::float3 unitY = simd::float3 {0,1,0};
        simd::float3 unitZ = simd::float3 {0,0,1};
        
        if(normal == EAxis::X) {
            rot = matrix4x4_rotation(M_PI / 2, unitY);
        }
        else if(normal == EAxis::Y) {
            rot = matrix4x4_rotation(M_PI / 2, unitX);
        }
        else if(normal == EAxis::Z) {
            rot = matrix4x4_identity(); // vertices are defined with normal as +Z
        }
        
        for(int i = 0; i < baseIndices.size(); i+=2) {
            simd::float3 baseStartPos = baseVertices[baseIndices[i]];
            simd::float3 baseEndPos = baseVertices[baseIndices[i + 1]];
            simd::float4 startPos = boxOffset * rot * extentScale * simd::make_float4(baseStartPos.x, baseStartPos.y, baseStartPos.z, 1.0f);
            simd::float4 endPos = boxOffset * rot * extentScale * simd::make_float4(baseEndPos.x, baseEndPos.y, baseEndPos.z, 1.0f);;
            
            lineIds[i / 2] = engine->addLine(
                                         startPos.xyz,
                                         endPos.xyz,
                                         0.025,
                                         color
                                         );
        }
        
    }
    
    IEngine* engine;
    EAxis normal; // the normal of this plane
    simd::float3 color;
    simd::float2 extent;
    simd::float3 posOffset;
    std::array<int, 5> lineIds;
};

