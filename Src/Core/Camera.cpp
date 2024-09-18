//
//  Camera.cpp
//  MetalTutorial
//
//  Created by Ronnin Padilla on 8/22/24.
//
#include "Camera.hpp"
#import "AAPLMathUtilities.h"
#include "assert.h"
#include "Math/CommonMath.hpp"

Camera::Camera(const Camera::InitParams params)
:
    position(params.pos),
    pitch(params.pitch),
    yaw(params.yaw),
    speed(params.speed),
    rotateSpeed(params.rotateSpeed),
    moveDirection(make_float3(0,0,0)),
    useYawPitch(params.useYawPitch),
    isOrthographic(params.isOrtho),
    sensitivity(params.sensitivity)
{
    up = make_float3(0,1,0);
    if(useYawPitch) {
        setPitchYaw(pitch, yaw); // update forward and right
    }
}

void Camera::setPitchYaw(float inPitch, float inYaw) {
    if(!useYawPitch) {
        assert(false);
        return;
    }
    
    yaw = inYaw;
    pitch = inPitch;
    
    if(pitch >= 90.0f) {
        pitch = 89.9f;
    }
    if(pitch <= -90.0f) {
        pitch = -89.9f;
    }

    const float3 newForward = make_float3(
                            cosf(radians_from_degrees(yaw)) * cosf(radians_from_degrees(pitch)),
                            sinf(radians_from_degrees(pitch)),
                            sinf(radians_from_degrees(yaw)) * cosf(radians_from_degrees(pitch))
                        );
    
    setForwardVector(normalize(newForward));
}

float4x4 Camera::calculateProjectionViewMatrix() const {
    return calculateProjectionMatrix() * calculateViewMatrix();
}

float4x4 Camera::calculateProjectionMatrix(float zAlphaStart, float zAlphaEnd) const {
    return isOrthographic? calculateProjectionMatrix_Orthographic(zAlphaStart, zAlphaEnd) : calculateProjectionMatrix_Perspective(zAlphaStart, zAlphaEnd);
}

float4x4 Camera::calculateViewMatrix() const {
    const float3 R = right;
    const float3 U = -up;
    const float3 F = forward;
    const float3 P = position;
    
    const matrix_float4x4 view = matrix_make_rows(
                                             R.x,  R.y,  R.z, -dot(R, P),
                                             U.x,  U.y,  U.z, -dot(U, P),
                                            -F.x, -F.y, -F.z,  dot(F, P),
                                             0,    0,    0,    1);
    
    return view;
}

float4x4 Camera::calculateNormalMatrix() const {
    float4x4 view = calculateViewMatrix();
    float4x4 res = transpose(inverse(view));
    return res;
}

std::array<float3, 8> Camera::calculateFrustumVertices(float zAlphaStart, float zAlphaEnd) const {
    
    float4x4 inv = inverse(calculateProjectionMatrix(zAlphaStart, zAlphaEnd) * calculateViewMatrix());
    
    float4 ndc0 {-1, 1, 0, 1};
    float4 ndc1 {1, 1, 0, 1};
    float4 ndc2 {1, -1, 0, 1};
    float4 ndc3 {-1, -1, 0, 1};
    
    float4 ndc4 {-1, 1, 1, 1};
    float4 ndc5 {1, 1, 1, 1};
    float4 ndc6 {1, -1, 1, 1};
    float4 ndc7 {-1, -1, 1, 1};
    
    std::array<float3, 8> outArr;
    
    outArr[0] = CmnMath::ndcToWorld(inv, ndc0);
    outArr[1] = CmnMath::ndcToWorld(inv, ndc1);
    outArr[2] = CmnMath::ndcToWorld(inv, ndc2);
    outArr[3] = CmnMath::ndcToWorld(inv, ndc3);
    
    outArr[4] = CmnMath::ndcToWorld(inv, ndc4);
    outArr[5] = CmnMath::ndcToWorld(inv, ndc5);
    outArr[6] = CmnMath::ndcToWorld(inv, ndc6);
    outArr[7] = CmnMath::ndcToWorld(inv, ndc7);
    
    return outArr;
}

void Camera::setForwardVectorDirect(const float3 inForward) {
    if(useYawPitch) {
        assert(false);
        return;
    }
    setForwardVector(inForward);
}

void Camera::setForwardVector(const float3 inForward) {
    forward = inForward;
    right = normalize(cross(forward, make_float3(0, 1, 0)));
    up = normalize(cross(forward, right));
}

float4x4 Camera::calculateProjectionMatrix_Perspective(float zAlphaStart, float zAlphaEnd) const {
    float d = farZ - nearZ;
    float zs = zAlphaStart * d;
    float ze = zAlphaEnd * d;
    
    return matrix_perspective_right_hand(fov, aspectRatio, nearZ + zs, nearZ + ze);
}
float4x4 Camera::calculateProjectionMatrix_Orthographic(float zAlphaStart, float zAlphaEnd) const {
    return matrix_ortho_right_hand(orthoL, orthoR, orthoB, orthoT, orthoN, orthoF);
}
