//
//  Camera.hpp
//  MetalTutorial
//
//  Created by Ronnin Padilla on 8/22/24.
//
#include <simd/simd.h>
using namespace simd;

#include <array>

class Camera {
public:
    
    struct InitParams {
        InitParams()
        : useYawPitch(true) {}
        
        float3 pos;
        float pitch;
        float yaw;
        float speed;
        float rotateSpeed;
        bool isOrtho;
        bool useYawPitch;
        
        float sensitivity;
    };
    
    Camera() = default;
    
    Camera(const InitParams params);

    // general setters
    void setPitchYaw(float inPitch, float inYaw);
    void setPosition(const float3 inPos) { position = inPos; }
    void setMoveDirection(const float3 inDir) { moveDirection = inDir; }
    void setSpeed(const float inSpeed) { speed = inSpeed; }
    void setForwardVectorDirect(const float3 inForward);
    void setUseYawPitch(bool v) { useYawPitch = v; }
    
    // perspective setters
    void setFOV(float inFOV) { fov = inFOV; }
    void setFOVDeg(float inFOV) { fov = inFOV * (M_PI / 180.0f); }
    void setAspectRatio(float inAspectRatio) { aspectRatio = inAspectRatio; }
    void setNearZ(float inNearZ) { nearZ = inNearZ; }
    void setFarZ(float inFarZ) { farZ = inFarZ; }
    
    // orthographic setters
    void setOrthoLRBTNF(float inL, float inR, float inB, float inT, float inN, float inF) {
        orthoL = inL;
        orthoR = inR;
        orthoB = inB;
        orthoT = inT;
        orthoN = inN;
        orthoF = inF;
    }
    // delta setters
    void addPosition(const float3 deltaPos) { position += deltaPos; }
    void addPitchYaw(float deltaPitch, float deltaYaw) {
        setPitchYaw(pitch + deltaPitch, yaw + deltaYaw);
    }
    
    // matrices
    float4x4 calculateProjectionViewMatrix() const;
    float4x4 calculateProjectionMatrix(float zAlphaStart = 0.f, float zAlphaEnd = 1.f) const;
    float4x4 calculateViewMatrix() const;
    float4x4 calculateNormalMatrix() const;
    
    // utils
    
    // frustum vertices in the following order:
    //      [0,3] => tl, tr, br, bl (of nearest face to position)
    //      [5,7] => tl, tr, br, bl (of farthest face to position)
    std::array<float3, 8> calculateFrustumVertices(float zAlphaStart = 0.f, float zAlphaEnd = 1.f) const;
    
    const float3& getPosition() const { return position; }
    const float3& getForwardVector() const { return forward; }
    const float3& getRightVector() const { return right; }
    const float3& getUpVector() const { return up; }
    const float3& getMoveDirection() const { return moveDirection; }
    const float& getSpeed() const { return speed; }
    const float& getRotateSpeed() const { return rotateSpeed; }
    const float& getPitch() const { return pitch; }
    const float& getYaw() const { return yaw; }
    const float& getSensitivity() const { return sensitivity; }
    
    const float& getFOV() const { return fov; }
    const float& getAspectRatio() const { return aspectRatio; }
    const float& getNearZ() const { return nearZ; }
    const float& getFarZ() const { return farZ; }
    
    
private:
    void setForwardVector(const float3 inForward);
    float4x4 calculateProjectionMatrix_Perspective(float zAlphaStart = 0.f, float zAlphaEnd = 1.f) const;
    float4x4 calculateProjectionMatrix_Orthographic(float zAlphaStart = 0.f, float zAlphaEnd = 1.f) const;
    
private:
    
    float3 position;
    
    float3 forward;
    float3 right;
    float3 up;
    
    float speed;
    float rotateSpeed;
    float3 moveDirection;
    
    float pitch;
    float yaw;
    
    bool useYawPitch;
    float sensitivity;
    
    ///
    bool isOrthographic;
    
    // perspective properties
    float fov;
    float aspectRatio;
    float nearZ;
    float farZ;
    
    // orthographic properties
    float orthoL;
    float orthoR;
    float orthoT;
    float orthoB;
    float orthoN;
    float orthoF;
};

