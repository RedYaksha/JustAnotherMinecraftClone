//
//  Debug.hpp
//  MetalTutorial
//
//  Created by Ronnin Padilla on 8/22/24.
//
#include <string>
#include "fmt/format.h"
#include <iostream>
#include "simd/simd.h"

class DebugUtils {
public:
    
    
    
    static std::string stringify_int3(const simd::int3 V) {
        return fmt::format("({},{},{})", V.x, V.y, V.z);
    }
    
    static std::string stringify_float3(const simd::float3 V) {
        return fmt::format("({},{},{})", V.x, V.y, V.z);
    }
    
    static std::string stringify_float4(const simd::float4 V) {
        return fmt::format("({},{},{},{})", V.x, V.y, V.z, V.w);
    }
    
    static std::string stringify_tupleInt3(const std::tuple<int,int,int> V) {
        return fmt::format("({},{},{})", std::get<0>(V), std::get<1>(V), std::get<2>(V));
    }
};
