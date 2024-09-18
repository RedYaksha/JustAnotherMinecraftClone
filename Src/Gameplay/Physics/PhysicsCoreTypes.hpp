#pragma once
#include <simd/geometry.h>
#include <simd/quaternion.h>
#include <simd/simd.h>
#include "Core/CoreTypes.hpp"
#include <array>
#include <limits>
#include "assert.h"
#include <algorithm>
#include <iostream>

// TODO: physics name space

enum ECollisionEntityType {
    AABBType,
    RectType,
    LineType,
    Invalid
};

struct CollisionEntity {
public:
    ECollisionEntityType getType() const { return type; }
    void setId(int inId) { id = inId; }
    int getId() const { return id; }
    
protected:
    CollisionEntity(ECollisionEntityType type)
    : type(type)
    {}
    
    ECollisionEntityType type;
    int id;
};

struct CollisionLine : public CollisionEntity {
    CollisionLine() 
    : CollisionEntity(ECollisionEntityType::LineType) {
        
    }

    CollisionLine(simd::float3 posA, simd::float3 posB)
    : CollisionEntity(ECollisionEntityType::LineType), posA(posA), posB(posB) 
    {}

    simd::float3 getDirection() const {
	return simd::normalize(posB - posA);
    }

    simd::float3 posA;
    simd::float3 posB;

};

struct AABB : public CollisionEntity {
    AABB()
    : CollisionEntity(ECollisionEntityType::AABBType) {
        
    }
    
    AABB(simd::float3 extent)
    : CollisionEntity(ECollisionEntityType::AABBType)
    {
        minPos = simd::float3 {-extent.x, -extent.y, -extent.z};
        maxPos = simd::float3 { extent.x,  extent.y,  extent.z};
    }
    
    void setPositionWS(simd::float3 pos) {
        minPosWS = minPos + pos;
        maxPosWS = maxPos + pos;
    }
    
    simd::float3 getCenterWS() const {
        return (minPosWS + maxPosWS) / 2.0f;
    }
    
    simd::float3 minPos;
    simd::float3 maxPos;
    
    simd::float3 minPosWS;
    simd::float3 maxPosWS;
};

struct CollisionRect : public CollisionEntity {
    CollisionRect()
    : CollisionEntity(ECollisionEntityType::RectType) {
        
    }
    
    CollisionRect(std::array<simd::float3, 4> posWS, simd::float3 normalWS)
    : CollisionEntity(ECollisionEntityType::RectType), normalWS(normalWS) {
        minPos.x = std::numeric_limits<float>::max();
        maxPos.x = std::numeric_limits<float>::lowest();
        minPos.y = std::numeric_limits<float>::max();
        maxPos.y = std::numeric_limits<float>::lowest();
        
        minPosWS.x = std::numeric_limits<float>::max();
        maxPosWS.x = std::numeric_limits<float>::lowest();
        minPosWS.y = std::numeric_limits<float>::max();
        maxPosWS.y = std::numeric_limits<float>::lowest();
        minPosWS.z = std::numeric_limits<float>::max();
        maxPosWS.z = std::numeric_limits<float>::lowest();
        
        // find normal (the component that never changes)
        bool allSameX = true;
        bool allSameY = true;
        bool allSameZ = true;
        
        float xVal = posWS[0].x;
        float yVal = posWS[0].y;
        float zVal = posWS[0].z;
        
        
        for(int i = 1; i < posWS.size(); i++) {
            const simd::float3& p = posWS[i];
            allSameX &= p.x == xVal;
            allSameY &= p.y == yVal;
            allSameZ &= p.z == zVal;
        }
        
        // ensure only 1 component is all zero
        assert((allSameX + allSameY + allSameZ) == 1);
        
        if(allSameX) {
            normal = EAxis::X;
            normalOffset = xVal;
        }
        else if(allSameY) {
            normal = EAxis::Y;
            normalOffset = yVal;
        }
        else if(allSameZ) {
            normal = EAxis::Z;
            normalOffset = zVal;
        }
        
        for(const simd::float3& p : posWS) {
            minPosWS.x = std::min(p.x, minPosWS.x);
            maxPosWS.x = std::max(p.x, maxPosWS.x);
            minPosWS.y = std::min(p.y, minPosWS.y);
            maxPosWS.y = std::max(p.y, maxPosWS.y);
            minPosWS.z = std::min(p.z, minPosWS.z);
            maxPosWS.z = std::max(p.z, maxPosWS.z);
            
            // z,y
            if(normal == EAxis::X) {
                minPos.x = std::min(p.z, minPos.x);
                maxPos.x = std::max(p.z, maxPos.x);
                minPos.y = std::min(p.y, minPos.y);
                maxPos.y = std::max(p.y, maxPos.y);
            }
            // x,z
            else if(normal == EAxis::Y) {
                minPos.x = std::min(p.x, minPos.x);
                maxPos.x = std::max(p.x, maxPos.x);
                minPos.y = std::min(p.z, minPos.y);
                maxPos.y = std::max(p.z, maxPos.y);
            }
            // x,y
            else if(normal == EAxis::Z) {
                minPos.x = std::min(p.x, minPos.x);
                maxPos.x = std::max(p.x, maxPos.x);
                minPos.y = std::min(p.y, minPos.y);
                maxPos.y = std::max(p.y, maxPos.y);
            }
        }
    }
    
    CollisionRect(simd::float2 extent)
    : CollisionEntity(ECollisionEntityType::RectType)
    {
        minPos = simd::float2 {-extent.x, -extent.y};
        maxPos = simd::float2 { extent.x,  extent.y};
    }

    simd::float3 getCenterWS() const {
        return (minPosWS + maxPosWS) / 2.0f;
    }
    
    simd::float2 minPos;
    simd::float2 maxPos;
    float normalOffset; // how far along the normal direction is this rect
    EAxis normal;
    
    simd::float3 normalWS;
    
    simd::float3 minPosWS;
    simd::float3 maxPosWS;
};



class CollisionChecker {
public:
    /*
     *
     *
     * 
Box
Shadertoy example
// axis aligned box centered at the origin, with size boxSize
vec2 boxIntersection( in vec3 ro, in vec3 rd, vec3 boxSize, out vec3 outNormal ) 
{
    vec3 m = 1.0/rd; // can precompute if traversing a set of aligned boxes
    vec3 n = m*ro;   // can precompute if traversing a set of aligned boxes
    vec3 k = abs(m)*boxSize;
    vec3 t1 = -n - k;
    vec3 t2 = -n + k;
    float tN = max( max( t1.x, t1.y ), t1.z );
    float tF = min( min( t2.x, t2.y ), t2.z );
    if( tN>tF || tF<0.0) return vec2(-1.0); // no intersection
    outNormal = (tN>0.0) ? step(vec3(tN),t1)) : // ro ouside the box
                           step(t2,vec3(tF)));  // ro inside the box
    outNormal *= -sign(rd);
    return vec2( tN, tF );
}
     */

    // https://iquilezles.org/articles/intersectors/
    // boxIntersection()
    static bool lineRectIntersection(const CollisionLine& a, const CollisionRect& b, float& dist) {
	simd::float3 rectCenterWS = b.getCenterWS();


	simd::float3 boxSize = simd::abs(rectCenterWS - b.maxPosWS);

	// inigo's function assumes the box is at the origin
	simd::float3 rayOrigin = a.posA - rectCenterWS;
	simd::float3 rayDir = simd::normalize(a.posB - a.posA);

	simd::float3 m = 1.0f / rayDir;
	/*
	simd::float3 n = m * rayOrigin;
	simd::float3 k = simd::abs(m) * boxSize; 
	simd::float3 t1 = -n - k;
	simd::float3 t2 = -n + k;
	*/

	// more robust
	simd::float3 k = simd::float3 {rayDir.x>=0.0?boxSize.x:-boxSize.x, rayDir.y>=0.0?boxSize.y:-boxSize.y, rayDir.z>=0.0?boxSize.z:-boxSize.z};
	simd::float3 t1 = (-rayOrigin - k)*m;
	simd::float3 t2 = (-rayOrigin + k)*m;

	float tN = std::max( std::max( t1.x, t1.y ), t1.z );
	float tF = std::min( std::min( t2.x, t2.y ), t2.z );

	if( tN > tF || tF < 0.0f ) {
	    return false;
	}

	// return simd::float2( tN, tF ) <-- represents distance of intersection?
	float lineDist = simd::distance(a.posA, a.posB);
	
	if(tN > 0.0f && tN <= lineDist) {
	    dist = tN;
	    return true;
	}

	if(tN <= 0.0f && tF <= lineDist) {
	    // dist = tF;
	    // return true;

	}

	return false;
    }

    static bool doesCollide(const AABB& a, const AABB& b) {
        return false;
    }
    
    static bool doesCollide(const CollisionRect& a, const CollisionRect& b) {   
        return false;
    }
    
    static bool doesCollide(const AABB& a, const CollisionRect& b, simd::float3 tol = simd::float3{0,0,0}) {
        tol.y = b.normal == EAxis::Y? 0.0f : tol.y;
        tol.x = b.normal == EAxis::X? 0.0f : tol.x;
        tol.z = b.normal == EAxis::Z? 0.0f : tol.z;
        
        return (
            (a.minPosWS.x <= b.maxPosWS.x - tol.x && a.maxPosWS.x >= b.minPosWS.x + tol.x) &&
            (a.minPosWS.y <= b.maxPosWS.y - tol.y && a.maxPosWS.y >= b.minPosWS.y + tol.y) &&
            (a.minPosWS.z <= b.maxPosWS.z - tol.z && a.maxPosWS.z >= b.minPosWS.z + tol.z)
        );
    }
    
    static bool pullOut(AABB& a, const CollisionRect& b, simd::float3& vel) {
        float velDot = simd::dot(simd::normalize(vel), b.normalWS);
        simd::float3 tolerance = simd::float3 {0.1,0.1,0.1};
        if(abs(velDot) < 0.2) {
            tolerance = simd::float3 {0.3, 0.3, 0.3};
        }
        
        if(!doesCollide(a, b, tolerance)) {
            return false;
        }
        
        if(b.normal != EAxis::Y && velDot >= 0) {
            return false;
        }
        
        if(b.normal != EAxis::Y && simd::isnan(velDot)) {
            return false;
        }
        
        
        
        if(b.normal == EAxis::Y && vel.y > 0) {
            return false;
        }
        
        simd::float3 v = -simd::normalize(vel);
        
        float d = simd::dot(v, b.normalWS);
        
        if(d <= 0.5 && d < 1) {
           //return false;
        }
        
        //std::cout << "dot: " << simd::dot(v, b.normalWS) << std::endl;
        
        if(simd::isnan(d)) {
           // return false;
        }
        
        
        // remove velocity in the oppositve direction of b.normalWS
        // vel -= simd::dot(vel, b.normalWS) * simd::normalize(b.normalWS);
        
        // only pull out according to hit normal
        // normal = cross(vel, rect tangent);
        float offset = 0.0f;
        float tol = 0.0f;
        float cutoff = 0.45;
    
        // can only push in the direction of the normal
        
        if(b.normal == EAxis::X && a.minPosWS.x <= b.maxPosWS.x - tol && a.maxPosWS.x >= b.minPosWS.x + tol) {
            
            vel.x = 0;
            
            if(b.normalWS.x > 0) {
                if(abs(a.minPosWS.x - b.maxPosWS.x) > cutoff) {
                    return false;
                }
                float oldVal = a.minPosWS.x;
                a.minPosWS.x = b.maxPosWS.x + offset;
                a.maxPosWS.x += a.minPosWS.x - oldVal;
            }
            else {
                if(abs(a.maxPosWS.x - b.minPosWS.x) > cutoff) {
                    return false;
                }
                float oldVal = a.maxPosWS.x;
                a.maxPosWS.x = b.minPosWS.x - offset;
                a.minPosWS.x += a.maxPosWS.x - oldVal;
            }
            
            return true;
        }
        
        if(b.normal == EAxis::Y && a.minPosWS.y <= b.maxPosWS.y && a.maxPosWS.y >= b.minPosWS.y) {
            vel.y = 0;
            offset = 0.0;
            
            if(b.normalWS.y > 0) {
                if(abs(a.minPosWS.y - b.maxPosWS.y) > cutoff) {
                    return false;
                }
                float oldVal = a.minPosWS.y;
                a.minPosWS.y = b.maxPosWS.y + offset;
                a.maxPosWS.y += a.minPosWS.y - oldVal;
            }
            else {
                float oldVal = a.maxPosWS.y;
                if(abs(a.maxPosWS.y - b.minPosWS.y) > cutoff) {
                    return false;
                }
                a.maxPosWS.y = b.minPosWS.y - offset;
                a.minPosWS.y += a.maxPosWS.x - oldVal;
            }
            
            
            return true;
        }
        
        
        if(b.normal == EAxis::Z && a.minPosWS.z - tol <= b.maxPosWS.z && a.maxPosWS.z >= b.minPosWS.z + tol) {
            vel.z = 0;
            
            if(b.normalWS.z > 0) {
                if(abs(a.minPosWS.z - b.maxPosWS.z) > cutoff) {
                    return false;
                }
                float oldVal = a.minPosWS.z;
                a.minPosWS.z = b.maxPosWS.z + offset;
                a.maxPosWS.z += a.minPosWS.z - oldVal;
            }
            else {
                if(abs(a.maxPosWS.z - b.minPosWS.z) > cutoff) {
                    return false;
                }
                float oldVal = a.maxPosWS.z;
                a.maxPosWS.z = b.minPosWS.z - offset;
                a.minPosWS.z += a.maxPosWS.z - oldVal;
            }
            
            return true;
        }
        
        return false;
    }
};

