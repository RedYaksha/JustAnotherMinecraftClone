#pragma once
#include <simd/simd.h>
#include <vector>
#include <map>

/*
 https://github.com/keijiro/PerlinNoise/blob/master/Assets/Perlin.cs
 
 */
class PerlinNoiseGenerator {
public:
    
    PerlinNoiseGenerator() = default;
    
    PerlinNoiseGenerator(simd::int3 resolution);

    static int defaultPermutation[];
    static simd::float3 gradients3D[];
    
    
    float noise(float v);
    float noise(simd::float2 v);
    float noise(simd::float3 v);
    
    void syncFace(const PerlinNoiseGenerator& source, int srcFace, int dstFace);
    simd::int3 getResolution() const { return resolution; }
    
private:
    int getGradientIndex(int X, int Y, int Z);
    
    static float fade(float t) {
        return t * t * t * (t * (t * 6 - 15) + 10);
    }

    static float lerp(float t, float a, float b) {
        return a + t * (b - a);
    }

    static float gradient(int hash, float x) {
        return (hash & 1) == 0 ? x : -x;
    }

    static float gradient(int hash, float x, float y){
        return ((hash & 1) == 0 ? x : -x) + ((hash & 2) == 0 ? y : -y);
    }

    static float gradient(int hash, float x, float y, float z){
        int h = hash & 15;
        float u = h < 8 ? x : y;
        float v = h < 4 ? y : (h == 12 || h == 14 ? x : z);
        return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v);
    }
    
private:
    simd::int3 resolution;
    std::vector<int> perm;
    
    std::array<std::vector<int>, 6> faceGradients;
    std::map<std::tuple<int,int,int>, int> cornerGradients;
};
