#include <metal_stdlib>
using namespace metal;
#include "VertexDataTypes.hpp"

struct VertexOut {
    // The [[position]] attribute of this member indicates that this value
    // is the clip space position of the vertex when this structure is
    // returned from the vertex function.
    float4 position [[position]];

    // Since this member does not have a special attribute, the rasterizer
    // interpolates its value with the values of the other triangle vertices
    // and then passes the interpolated value to the fragment shader for each
    // fragment in the triangle.
    float2 textureCoordinate;
    
    int atlasIndex;
};

vertex VertexOut vertexShader(uint vertexID [[vertex_id]], constant VertexData* vertexData, constant TransformationData* td)
{
    VertexOut out;
    out.position = td->perspective * td->view * td->model * vertexData[vertexID].position;
    out.textureCoordinate = vertexData[vertexID].textureCoordinates;
    out.atlasIndex = vertexData[vertexID].atlasIndex;

    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]], texture2d<float> colorTexture [[texture(0)]])
{
    constexpr sampler textureSampler(mag_filter::nearest, mag_filter::nearest);
    
    // repeat not needed for voxel "repeating" with whole number tex coords since we
    // normalize them again anyway in the calculation of sprite local UVs to absolute UVs
    //
    // constexpr sampler textureSampler(address::repeat);
    
    // Idea:
    //      1. take voxel type => this is the offset into the texture atlas
    //            - from this we can find the start x,y and end x,y texture coordinates of the image
    //      2. extract fractional part of in.textureCoordinate, say F
    //            - we will end up sampling between start/end x,y using F
    
    // constants for calculation
    // TODO: (perhaps should be loaded in a uniform if we want to customize textures)
    const float2 spriteSize = float2(16,16);
    const float2 atlasSize = float2(512, 512);
    const int numRows = atlasSize.y / spriteSize.y;
    const int numCols = atlasSize.x / spriteSize.x;
    
    // original texture coordinates, this is actually within (width, height) of the quad we're rendering
    const float2 texCoord = in.textureCoordinate;
    
    // whole number only of texCoord
    const float2 texCoordFloored = float2(floor(texCoord.x), floor(texCoord.y));
    
    // fraction part only of texCoord (ie. the local uvs within the sprite)
    const float2 frac = texCoord - texCoordFloored;
    
    // atlasIndex indexes the atlas from top-left to bottom-right.
    const int col = in.atlasIndex % numCols;
    const int row = in.atlasIndex / numRows;
    
    // NOTE: UV (0,0) starts at bottom-left corner and (1,1) is at top-right corner,
    // however, our atlas index starts at top-left corner. This doesn't affect the U coordinate
    // but it does affect the V
    // (the top of the first row (index-0) is at V=atlasHeight and the bottom is at V=atlasHeight-spriteHeight
    //
    // e.g. when col == 0 && row == 0, bottom-left corner (of the sprite) is (0,512-16)
    // and top-right corner is at (16,512)
    const float2 atlasStartUV = float2(col, numRows - (row + 1)) * spriteSize / atlasSize;
    const float2 atlasEndUV = float2(col + 1, numRows - row) * spriteSize / atlasSize;
    
    // capture the absolute UV by using frac to interpolate between start and end
    const float2 absoluteUV = atlasStartUV + frac * (atlasEndUV - atlasStartUV);
    
    float4 colorSample = colorTexture.sample(textureSampler, absoluteUV);
    //float a = colorSample.a;
    //colorSample = float4(a,a,a, 1.0);
    return colorSample;
}
