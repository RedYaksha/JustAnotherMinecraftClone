
//
//  math.hpp
//  MetalTutorial
//
//  Created by Ronnin Padilla on 8/22/24.
//

// TODO: use a more generic math lib
#include <simd/simd.h>
using namespace simd;

class CmnMath {
public:
    // https://www.gamedev.net/forums/topic/393309-calculating-the-view-frustums-vertices/3605595/
    static float3 ndcToWorld(const float4x4& invMat, float4 ndc) {
        float4 worldVec = invMat * ndc;
        float invW = 1.f/worldVec.w;
        
        worldVec *= invW;
        worldVec.w = 1.0f;
        
        return make_float3(worldVec.x, worldVec.y, worldVec.z);
    }
    
    static float3 projectPointToPlane(const float3 origin, float3 norm, float3 p) {
        float3 v = p - origin;
        float3 planeNormal = norm;
        float dist = dot(v, planeNormal);
        float3 planePoint = p + -planeNormal * dist;
        return planePoint;
    }
    
    static float distancePointToPlane(const float3 origin, float3 norm, float3 p) {
        float3 v = p - origin;
        float3 planeNormal = norm;
        float dist = dot(v, planeNormal);
        return dist;
    }
    
    // https://gamedev.stackexchange.com/questions/72528/how-can-i-project-a-3d-point-onto-a-3d-line
    static float3 projectPointToLine(const float3 A, const float3 B, float3 p) {
        float3 AP = p - A;
        float3 AB = B - A;
        return A + dot(AP, AB) / dot(AB, AB) * AB;
    }
    
    enum IntersectionType {
        None,
        BehindP0,
        InFrontP1,
        AlongSegment
    };
    
    // https://stackoverflow.com/a/18543221
    static IntersectionType linePlaneIntersection(float3& outPoint, float3 line0, float3 line1, float3 planeP, float3 planeN, float epsilon=0.0001) {
        float3 u = line1 - line0;
        float d = dot(planeN, u);
        // The factor of the point between p0 -> p1 (0 - 1)
        // if 'fac' is between (0 - 1) the point intersects with the segment.
        // Otherwise:
        //  < 0.0: behind p0.
        //  > 1.0: infront of p1.
        if(abs(d) > epsilon) {
            float3 w = line0 - planeP;
            float fac = -dot(planeN, w) / d;
            u = u * fac;
            outPoint = line0 + u;
            return fac < 0.0f? IntersectionType::BehindP0 : fac > 1.0f? IntersectionType::InFrontP1 : IntersectionType::AlongSegment;
        }
        
        return IntersectionType::None;
    }
    
    static float3x3 alignABRotationMatrix_3x3(float3 a, float3 b) {
        float3x3 rot;
        
        // Direct implementation of:
        //      https://math.stackexchange.com/a/476311
        // This creates a rotation matrix that aligns vector A onto B
        simd::float3 v = cross(a,b);
        float s = length(v);
        float c = dot(a,b);
        
        float3x3 vx = matrix_make_rows(
                                       0, -v[2], v[1],
                                       v[2], 0, -v[0],
                                       -v[1], v[0], 0
                                    );
        
        float3x3 I = matrix_make_rows(
                                      1,0,0,
                                      0,1,0,
                                      0,0,1
                                      );
        
        float3x3 r = I + vx + vx * vx * ((1 - c) / (s * s));
        
        rot = r;
        
        if(simd_equal(a,b)) {
            rot = I;
        }
        
        return rot;
    }
    
    static float4x4 alignABRotationMatrix(float3 a, float3 b) {
        float4x4 rot;
        
        // Direct implementation of:
        //      https://math.stackexchange.com/a/476311
        // This creates a rotation matrix that aligns vector A onto B
        simd::float3 v = cross(a,b);
        float s = length(v);
        float c = dot(a,b);
        
        float4x4 vx = matrix_make_rows(
                                       0, -v[2], v[1], 0,
                                       v[2], 0, -v[0], 0,
                                       -v[1], v[0], 0, 0,
                                       0, 0, 0, 1
                                    );
        
        float4x4 I = matrix4x4_identity();
        
        float4x4 r = I + vx + vx * vx * ((1 - c) / (s * s));
        
        // remove translation/scale from calculation
        r.columns[0][3] = 0;
        r.columns[1][3] = 0;
        r.columns[2][3] = 0;
        
        r.columns[3][0] = 0;
        r.columns[3][1] = 0;
        r.columns[3][2] = 0;
        
        r.columns[3][3] = 1;
        
        
        rot = r;
        
        if(simd_equal(a,b)) {
            rot = I;
        }
        
        return rot;
    }
    
    // https://stackoverflow.com/questions/2752725/finding-whether-a-point-lies-inside-a-rectangle-or-not
    static bool isPointInRectangle(float3 A, float3 B, float3 C, float3 M) {
        float3 AB = B - A;
        float3 AM = M - A;
        float3 BC = C - B;
        float3 BM = M - B;
        
        float D1 = dot(AB, AM);
        float D2 = dot(AB, AB);
        float D3 = dot(BC, BM);
        float D4 = dot(BC, BC);
        
        bool insideRect =
            0 <= D1 && D1 <= D2 &&
            0 <= D3 && D3 <= D4;
        
        return insideRect;
    }

};
