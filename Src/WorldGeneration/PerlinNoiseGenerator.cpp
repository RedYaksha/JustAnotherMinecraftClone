//
//  PerlinNoiseGenerator.cpp
//  MetalTutorial
//
//  Created by Ronnin Padilla on 8/10/24.
//
#include "PerlinNoiseGenerator.hpp"
#include <random>
#include <cstdlib>
#include <cassert>

int PerlinNoiseGenerator::defaultPermutation[] = {
    151,160,137,91,90,15,
    131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,37,240,21,10,23,
    190, 6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,57,177,33,
    88,237,149,56,87,174,20,125,136,171,168, 68,175,74,165,71,134,139,48,27,166,
    77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,55,46,245,40,244,
    102,143,54, 65,25,63,161, 1,216,80,73,209,76,132,187,208, 89,18,169,200,196,
    135,130,116,188,159,86,164,100,109,198,173,186, 3,64,52,217,226,250,124,123,
    5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,
    223,183,170,213,119,248,152, 2,44,154,163, 70,221,153,101,155,167, 43,172,9,
    129,22,39,253, 19,98,108,110,79,113,224,232,178,185, 112,104,218,246,97,228,
    251,34,242,193,238,210,144,12,191,179,162,241, 81,51,145,235,249,14,239,107,
    49,192,214, 31,181,199,106,157,184, 84,204,176,115,121,50,45,127, 4,150,254,
    138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180,
    151
};

simd::float3 PerlinNoiseGenerator::gradients3D[] = {{1,1,0},{-1,1,0},{1,-1,0},{-1,-1,0},
    {1,0,1},{-1,0,1},{1,0,-1},{-1,0,-1},
    {0,1,1},{0,-1,1},{0,1,-1},{0,-1,-1}
};

PerlinNoiseGenerator::PerlinNoiseGenerator(simd::int3 resolution)
: resolution(resolution) {
    int maxRes = std::max(resolution.x, std::max(resolution.y, resolution.z));
    
    perm.clear();
    
    std::random_device rd;     // Only used once to initialise (seed) engine
    std::mt19937 rng(rd());    // Random-number engine used (Mersenne-Twister in this case)
    std::uniform_int_distribution<int> uni(0, maxRes - 1); // Guaranteed unbiased

    for(int i = 0; i < maxRes * 2; i++) {
        perm.push_back(uni(rng));
    }
    
    
    std::uniform_int_distribution<int> uniGradient(0, 11); // Guaranteed unbiased
    
    std::array<int, 3> dims = {resolution.x + 1, resolution.y + 1, resolution.z + 1};
    
    // due to this order and iteration organization, faceGradients should be defined as:
    // 0: YZ face when x==0
    // 1: YZ face when x==resolution.x-1
    // 2: XZ face when y==0
    // 3: YZ face when y==resolution.y-1
    // 4: XY face when z==0
    // 5: XY face when z==resolution.z-1
    std::vector<std::array<int, 3>> dimSelection = { {1,0,0}, {0,1,0}, {0,0,1}};
    for(int i = 0; i < 3; i++) {
        // dimension selection
        std::array<int, 3> curDim = dimSelection[i];
        std::vector<int> otherDims;
        for(int j = 0; j < 3; j++) {
            if(curDim[j] == 0) {
                otherDims.push_back(dims[j]);
            }
        }
        
        // do twice, for when curDim=0 and curDim=resolution-1
        for(int side=0; side<2;side++) {
            for(int u = 0; u < otherDims[0]; u++) {
                for(int v = 0; v < otherDims[1]; v++) {
                    
                    // conditions for being a corner
                    if( (u == 0 && v == 0) ||
                        (u == otherDims[0] - 1 && v == otherDims[1] - 1) ||
                        (u == 0 && v == otherDims[1] - 1) ||
                        (u == otherDims[0] - 1 && v == 0)
                       ) {
                        faceGradients[2 * i + side].push_back(-1);
                    }
                    
                    else {
                        faceGradients[2 * i + side].push_back(uniGradient(rng));
                    }
                }
            }
        }
    }
    
    // 000
    // 100
    // 010
    // 110
    // 001
    // 101
    // 011
    // 111
    cornerGradients.clear();
    
    const int resX = resolution.x;
    const int resY = resolution.y;
    const int resZ = resolution.z;
    
    cornerGradients.insert({std::make_tuple(0,0,0), uniGradient(rng)});
    cornerGradients.insert({std::make_tuple(resX,0,0), uniGradient(rng)});
    cornerGradients.insert({std::make_tuple(0,resY,0), uniGradient(rng)});
    cornerGradients.insert({std::make_tuple(resX,resY,0), uniGradient(rng)});
    cornerGradients.insert({std::make_tuple(0,0,resZ), uniGradient(rng)});
    cornerGradients.insert({std::make_tuple(resX,0,resZ), uniGradient(rng)});
    cornerGradients.insert({std::make_tuple(0,resY,resZ), uniGradient(rng)});
    cornerGradients.insert({std::make_tuple(resX,resY,resZ), uniGradient(rng)});
}

float PerlinNoiseGenerator::noise(float v) {
    int X = (int) simd::floor(v) & 0xff;
    v -= simd::floor(v);
    float u = fade(v);
    return lerp(u, gradient(defaultPermutation[X], v), gradient(defaultPermutation[X+1], v-1)) * 2;
}

float PerlinNoiseGenerator::noise(simd::float2 input) {
    float x = input.x;
    float y = input.y;
    
    int X = (int) simd::floor(x) & 0xff;
    int Y = (int) simd::floor(y) & 0xff;
    x -= simd::floor(x);
    y -= simd::floor(y);
    float u = fade(x);
    float v = fade(y);
    int A = (defaultPermutation[X  ] + Y) & 0xff;
    int B = (defaultPermutation[X+1] + Y) & 0xff;
    return lerp(v, lerp(u, gradient(defaultPermutation[A  ], x, y  ), gradient(defaultPermutation[B  ], x-1, y  )),
                lerp(u, gradient(defaultPermutation[A+1], x, y-1), gradient(defaultPermutation[B+1], x-1, y-1)));
}

float PerlinNoiseGenerator::noise(simd::float3 input) {
    float x = std::abs(input.x);
    float y = std::abs(input.y);
    float z = std::abs(input.z);

    int X = ((int) simd::floor(x));
    int Y = ((int) simd::floor(y));
    int Z = ((int) simd::floor(z));
    
    // xyz becomes fractional part of input
    x = x - X;
    y = y - Y;
    z = z - Z;
    
    // smooth-step interpolation
    float u = fade(x);
    float v = fade(y);
    float w = fade(z);
    
    // Calculate a set of eight hashed gradient indices
    // mod 12 because we have 12 gradients
    /*
    int gi000 = perm[X+perm[Y+perm[Z]]] % 12;
    int gi001 = perm[X+perm[Y+perm[Z+1]]] % 12;
    int gi010 = perm[X+perm[Y+1+perm[Z]]] % 12;
    int gi011 = perm[X+perm[Y+1+perm[Z+1]]] % 12;
    int gi100 = perm[X+1+perm[Y+perm[Z]]] % 12;
    int gi101 = perm[X+1+perm[Y+perm[Z+1]]] % 12;
    int gi110 = perm[X+1+perm[Y+1+perm[Z]]] % 12;
    int gi111 = perm[X+1+perm[Y+1+perm[Z+1]]] % 12;
     */
    int gi000 = getGradientIndex(X, Y, Z);
    int gi001 = getGradientIndex(X, Y, Z + 1);
    int gi010 = getGradientIndex(X, Y + 1, Z);
    int gi011 = getGradientIndex(X, Y + 1, Z + 1);
    int gi100 = getGradientIndex(X + 1, Y, Z);
    int gi101 = getGradientIndex(X + 1, Y, Z + 1);
    int gi110 = getGradientIndex(X + 1, Y + 1, Z);
    int gi111 = getGradientIndex(X + 1, Y + 1, Z + 1);
    
    // Calculate noise contributions from each of the eight corners
    simd::float3 xyz = simd_make_float3(x, y, z);
    
    static simd::float3 offsets[] = {
        {0,0,0}, {-1,0,0}, {0,-1,0}, {-1,-1,0},
        {0,0,-1}, {-1,0,-1}, {0,-1,-1}, {-1, -1, -1}
    };
    
    double n000 = simd::dot(gradients3D[gi000], xyz + offsets[0]);
    double n100 = simd::dot(gradients3D[gi100], xyz + offsets[1]);
    double n010 = simd::dot(gradients3D[gi010], xyz + offsets[2]);
    double n110 = simd::dot(gradients3D[gi110], xyz + offsets[3]);
    double n001 = simd::dot(gradients3D[gi001], xyz + offsets[4]);
    double n101 = simd::dot(gradients3D[gi101], xyz + offsets[5]);
    double n011 = simd::dot(gradients3D[gi011], xyz + offsets[6]);
    double n111 = simd::dot(gradients3D[gi111], xyz + offsets[7]);
    
    // Interpolate along x the contributions from each of the corners
    double nx00 = lerp(u, n000, n100);
    double nx01 = lerp(u, n001, n101);
    double nx10 = lerp(u, n010, n110);
    double nx11 = lerp(u, n011, n111);
    // Interpolate the four results along y
    double nxy0 = lerp(v, nx00, nx10);
    double nxy1 = lerp(v, nx01, nx11);
    // Interpolate the two last results along z
    double nxyz = lerp(w, nxy0, nxy1);

    return nxyz;
    
    /*
    // hashed indices
    int A  = (defaultPermutation[X  ] + Y) & 0xff;
    int B  = (defaultPermutation[X+1] + Y) & 0xff;
    int AA = (defaultPermutation[A  ] + Z) & 0xff;
    int BA = (defaultPermutation[B  ] + Z) & 0xff;
    int AB = (defaultPermutation[A+1] + Z) & 0xff;
    int BB = (defaultPermutation[B+1] + Z) & 0xff;
    
    return lerp(w, lerp(v, lerp(u, gradient(defaultPermutation[AA  ], x, y  , z  ), gradient(defaultPermutation[BA  ], x-1, y  , z  )),
                           lerp(u, gradient(defaultPermutation[AB  ], x, y-1, z  ), gradient(defaultPermutation[BB  ], x-1, y-1, z  ))),
                   lerp(v, lerp(u, gradient(defaultPermutation[AA+1], x, y  , z-1), gradient(defaultPermutation[BA+1], x-1, y  , z-1)),
                           lerp(u, gradient(defaultPermutation[AB+1], x, y-1, z-1), gradient(defaultPermutation[BB+1], x-1, y-1, z-1))));
     */
}

int PerlinNoiseGenerator::getGradientIndex(int X, int Y, int Z) {
    // if XYZ is on a face, return index from faceGradients, otherwise return the hashed index
    
    // TODO: handle corners...?
    // due to this order and iteration organization, faceGradients should be defined as:
    // 0: YZ face when x==0
    // 1: YZ face when x==resolution.x
    // 2: XZ face when y==0
    // 3: XZ face when y==resolution.y
    // 4: XY face when z==0
    // 5: XY face when z==resolution.z
    int out = -100;
    
    if(X == 0) {
        out = faceGradients[0][Y * resolution.z + Z];
    }
    else if(X == resolution.x) {
        out = faceGradients[1][Y * resolution.z + Z];
    }
    
    else if(Y == 0) {
        out = faceGradients[2][X * resolution.z + Z];
    }
    else if(Y == resolution.y) {
        out = faceGradients[3][X * resolution.z + Z];
    }
    
    else if(Z == 0) {
        out = faceGradients[4][X * resolution.y + Y];
    }
    else if(Z == resolution.y) {
        out = faceGradients[5][X * resolution.y + Y];
    }
    
    if(out == -1) {
        // is a corner
        return cornerGradients[std::make_tuple(X,Y,Z)];
    }
    
    return perm[X+perm[Y+perm[Z]]] % 12;
}

void PerlinNoiseGenerator::syncFace(const PerlinNoiseGenerator& source, int srcFace, int dstFace) {
    // goal: all possible (X,Y,Z) along the XY face of this should match source, wrt the index hashing
    // ie.
    // int gi000 = perm[X+perm[Y+perm[Z]]] % 12;
    //
    
    // if sizes don't match (ie trying to match different resolution generators or
    // matching different sides, then queries are needed
    assert(source.faceGradients[srcFace].size() == faceGradients[dstFace].size());
    faceGradients[dstFace] = source.faceGradients[srcFace];
    
    // sync corners

    // 0: YZ face when x==0
    // 1: YZ face when x==resolution.x
    // 2: XZ face when y==0
    // 3: XZ face when y==resolution.y
    // 4: XY face when z==0
    // 5: XY face when z==resolution.z
    
    // 000 - 0
    // 100 - 1
    // 010 - 2
    // 110 - 3
    // 001 - 4
    // 101 - 5
    // 011 - 6
    // 111 - 7
    
    // TODO: map face index to corner indices
    // eg. 0 -> 000, 010, 001, 011 -> 0,2,4,6
    //     1 -> 100, 110, 101, 111 -> 1,3,5,7
    //     2 -> 000, 100, 001, 101 -> 0,1,4,5
    //     3 -> 010, 110, 011, 111 -> 2,3,6,7
    //     4 -> 000, 100, 010, 110 -> 0,1,2,3
    //     5 -> 001, 101, 011, 111 -> 4,5,6,7
    const int resX = resolution.x;
    const int resY = resolution.y;
    const int resZ = resolution.z;
    
    std::vector<std::array<std::tuple<int,int,int>, 4>> faceToCorners = {
        {std::make_tuple(0,0,0), std::make_tuple(0,resY,0), std::make_tuple(0,0,resZ), std::make_tuple(0,resY,resZ)},
        {std::make_tuple(resX,0,0), std::make_tuple(resX,resY,0), std::make_tuple(resX,0,resZ), std::make_tuple(resX,resY,resZ)},
        {std::make_tuple(0,0,0), std::make_tuple(resX,0,0), std::make_tuple(0,0,resZ), std::make_tuple(resX,0,resZ)},
        {std::make_tuple(0,resY,0), std::make_tuple(resX,resY,0), std::make_tuple(0,resY,resZ), std::make_tuple(resX,resY,resZ)},
        {std::make_tuple(0,0,0), std::make_tuple(resX,0,0), std::make_tuple(0,resY,0), std::make_tuple(resX,resY,0)},
        {std::make_tuple(0,0,resZ), std::make_tuple(resX,0,resZ), std::make_tuple(0,resY,resZ), std::make_tuple(resX,resY,resZ)},
    };
    
    std::array<std::tuple<int,int,int>, 4> srcCorners = faceToCorners[srcFace];
    std::array<std::tuple<int,int,int>, 4> dstCorners = faceToCorners[dstFace];
    for(int i=0; i<4; i++) {
        const int srcVal = (*source.cornerGradients.find(srcCorners[i])).second;
        cornerGradients[dstCorners[i]] = srcVal;
        
        assert(srcVal >= 0 && srcVal < 12);
    }
}



