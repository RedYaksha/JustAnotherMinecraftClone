#pragma once
#include <simd/simd.h>

class IEngine {
public:
    virtual int addLine(simd::float3 p1, simd::float3 p2, float thickness, simd::float3 color) = 0;
    virtual void setLineTransform(int index, simd::float3 p1, simd::float3 p2, float thickness) = 0;
    virtual void setLineColor(int index, simd::float3 color) = 0;
    virtual void setLineVisibility(int index, bool isVisible) = 0;
    
protected:
    virtual void commitLines() = 0;
};
