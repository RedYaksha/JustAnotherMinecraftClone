//
//  geometryPass.metal
//  MetalTutorial
//
//  Created by Ronnin Padilla on 8/15/24.
//
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
    
    float3 normal;
    
    int atlasIndex;
    
    float4 positionWS;
    float4 posNDC;
    float3 colorScale;
};

struct LightingPassVertexOut {
    float4 position [[position]];
    float4 posNDC;
    float4 posWS;
    float radius;
    float4 lightCenterWS;
    bool isLightVolume;
    float4 scaleColor;
};

vertex LightingPassVertexOut lightVolumePassVS(uint vertexID [[vertex_id]],
                                               uint instanceID [[instance_id]],
                                               constant PositionVertexData* vertexData [[buffer(0)]],
                                               constant CameraData* cd [[buffer(1)]],
                                               constant LightVolumeData* lightData [[buffer(2)]]) {
    
    LightVolumeData myLightData = lightData[instanceID];
    
    LightingPassVertexOut out;
    
    out.position = cd->projection * cd->view * myLightData.localToWorld * vertexData[vertexID].position;
    out.posNDC = out.position;
    out.posWS = myLightData.localToWorld * vertexData[vertexID].position;
    out.isLightVolume = true;
    out.radius = myLightData.localToWorld[0][0];
    out.lightCenterWS = float4(myLightData.localToWorld[3][0], myLightData.localToWorld[3][1], myLightData.localToWorld[3][2], 1.0f);
    out.scaleColor = myLightData.color;
    
    return out;
}

vertex LightingPassVertexOut lightingPassVS(uint vertexID [[vertex_id]],
                                            constant LightingPassVertexData* vertexData [[buffer(0)]]) {
    LightingPassVertexOut out;
    
    out.position = vertexData[vertexID].position;
    out.posNDC = vertexData[vertexID].position;
   // out.textureCoordinates = vertexData[vertexID].uv;
    out.isLightVolume = false;
    
    return out;
}

float3 calculateDirectionalLight(float3 posWS, float3 normalWS, float3 lightDirWS, float3 lightColor, float3 camPos, float shadow) {
    float3 ambient = 0.4 * lightColor;
    
    float3 posToLight = normalize(-lightDirWS);
    
    float diff = max(dot(posToLight, normalWS), 0.0);
    float3 diffuse = diff * lightColor;
    
    // blinn-phong
    float3 viewDir    = normalize(camPos - posWS);
    float3 halfwayDir = normalize(posToLight + viewDir);
    float spec = pow(max(dot(normalWS, halfwayDir), 0.0), 32);
    float3 specular = lightColor * spec;
    
    return (ambient + (1 - shadow) * (diffuse + specular));
}

float3 calculatePointLight(float3 posWS, float3 normalWS, float3 lightPosWS, float3 lightColor, float3 camPos, float3 emission) {
    float3 ambient = 0.3 * lightColor;
    
    float3 posToLight = normalize(lightPosWS - posWS);
    
    float diff = max(dot(posToLight, normalWS), 0.0);
    float3 diffuse = diff * lightColor;
    
    // blinn-phong
    float3 viewDir    = normalize(camPos - posWS);
    float3 halfwayDir = normalize(posToLight + viewDir);
    float spec = pow(max(dot(normalWS, halfwayDir), 0.0), 32);
    float3 specular = lightColor * spec;
    
    float distToLight = distance(posWS, lightPosWS);
    
    const float lightConstant = 1.0f;
    const float lightLinear = 0.22f;
    const float lightQuadratic = 0.2f;

    float attenuation = 1.0 / (lightConstant + lightLinear * distToLight + lightQuadratic * distToLight * distToLight);
    ambient *= attenuation;
    diffuse *= attenuation;
    specular *= attenuation;
    
    // return lightColor;
    return (ambient + diffuse + specular);
}

fragment float4 lightingPassFS(LightingPassVertexOut in [[stage_in]],
                               texture2d<float> gPosition [[texture(0)]],
                               texture2d<float> gNormal [[texture(1)]],
                               texture2d<float> gColor [[texture(2)]],
                               texture2d<float> gEmission [[texture(3)]],
                               
                               depth2d<float> shadowMap0 [[texture(4)]],
                               depth2d<float> shadowMap1 [[texture(5)]],
                               depth2d<float> shadowMap2 [[texture(6)]],
                               
                               texture2d<float> ssaoMap [[texture(7)]],
                               
                               constant CameraData* cd [[buffer(0)]],
                               
                               constant CameraData* lt0 [[buffer(1)]],
                               constant CameraData* lt1 [[buffer(2)]],
                               constant CameraData* lt2 [[buffer(3)]],
                               
                               constant RenderState* rs [[buffer(4)]]
                               ) {
    float2 uv = in.posNDC.xy;
    uv.y *= -1;
    uv /= in.posNDC.w;
    uv = uv * 0.5 + 0.5;
    
   //return float4(uv, 0.0, 1.0f);
    
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);

    // this value is bugged for skeletal meshes
    float4 positionWSRaw = gPosition.sample(textureSampler, uv);
    
    const float depthNDC = positionWSRaw.w;
    
    float4 normalWS = gNormal.sample(textureSampler, uv);
    float4 emission = gEmission.sample(textureSampler, uv);
    
    // Can't figure out why world space coordinate is off
    // when transforming by the skeletal bone transforms, but the
    // postion g-buffer looks fine.
    //
    // But it seems like calculating the world position just from the depth value seems to work
    // just fine... so weird.
    
    // conversion from depth:
    // https://stackoverflow.com/questions/32227283/getting-world-position-from-depth-buffer-value
    
    // rawProj is in NDC space (-1,1) for xy, (0,1) z, and 1.0f for w
    // this is after dividing by the w component to get these, which makes w 1.0f, since it's divided by itself.
    float4 rawProj = float4(uv.x * 2 - 1, -(uv.y * 2 - 1), depthNDC, 1.0f);
    
    // I need to multiply by the previous w?? But where is it
    rawProj *= positionWSRaw.z;
    
    // after that, we'd have points of NDC but in the range of [-w,w]
    
    // then we can multiply invProjection
    rawProj = cd->invView * cd->invProjection * rawProj;
    
    float4 rawClip = float4(uv.x * 2 - 1, -(uv.y * 2 - 1), depthNDC, 1.0f);
    float4 rawView = cd->invProjection * rawClip;
    rawView /= rawView.w;
    
    
    float4 positionWS = positionWSRaw; //cd->invView * rawView;
    
    
    
    float3 position = positionWS.xyz;
    float3 normal = normalize(normalWS.xyz);
    
    float3 dirLightColor = float3(1.0,1.0,1.0);
    
    float3 directionalLightDir = float3(1,-1,0.25);
    
    // float3 lightDir = normalize(-directionalLightDir);
    float gamma = 1.3f;
    
    if(in.isLightVolume) {
        position = positionWSRaw.xyz;
        
        float distFromLight = length(position.xyz - in.lightCenterWS.xyz);
        if(distFromLight > in.radius || depthNDC >= 1) {
            discard_fragment();
        }
        
        float3 ret = calculatePointLight(position, normal, in.lightCenterWS.xyz, in.scaleColor.xyz, cd->position.xyz, emission.xyz);
        
        //ret += emission.xyz;
        
        // ret = ret * color.xyz * ao;
        
        ret = ret / (ret + float3(1));
        //ret = float3(1.0) - exp(-ret * 0.6f);
        ret = pow(ret, float3(1.0 / gamma));
        
        return float4(ret, 1.0f);
    }
    
    
    float ao = ssaoMap.sample(textureSampler, uv).x;
    float4 color = gColor.sample(textureSampler, uv);
    
    
    // when sampling texture (0,0) is top-left and (1,1) is bottom-right
    // ----- Why does negating y work here?
 
    // get closest depth value from light's perspective (using [0,1] range fragPosLight as coords)
    
    // get depth of current fragment from light's perspective
    float currentDepth = 1.0f;
    float closestDepth = 1.0f; // shadowMap.sample(textureSampler, projCoords.xy);
    
    // todo: divide by far plane distance, put i camera data
    float distAlpha = distance(cd->position.xyz, position) / cd->zPlaneRange.y;
    
    float bias = max(0.005 * (1.0 - dot(normal, -directionalLightDir)), 0.0008);
    
    bool inShadow = false;
    
    float shadow = 0.0; // inShadow ? 1.0 : 0.0;
    
    float3 dc;
    
    // todo: read distances from uniform
    if(rs->useShadowMap && !in.isLightVolume) {
        if(distAlpha < 1) {
            float4 lightSpacePos = lt2->projection * lt2->view * float4(position, 1.0f);
            float3 projCoords = lightSpacePos.xyz;
            projCoords.y *= -1;
            projCoords /= lightSpacePos.w;
            projCoords = projCoords * 0.5 + float3(0.5);
            
            currentDepth = projCoords.z;
            closestDepth = shadowMap2.sample(textureSampler, projCoords.xy);
            
            inShadow = currentDepth - bias > closestDepth;
            
            shadow = 0.0;
            float2 texelSize = 1.0 / float2(shadowMap2.get_width(), shadowMap2.get_height());
            for(int x = -1; x <= 1; ++x)
            {
                for(int y = -1; y <= 1; ++y)
                {
                    float2 offset = float2(x,y) * texelSize;
                    float pcfDepth = shadowMap2.sample(textureSampler, projCoords.xy + offset);
                    shadow += currentDepth - bias > pcfDepth ? 1.0 : 0.0;
                }
            }
            shadow /= 9.0;
            
            dc = float3(1,0,0);
        }
        
        if(distAlpha < 0.4) {
            float4 lightSpacePos = lt1->projection * lt1->view * float4(position, 1.0f);
            float3 projCoords = lightSpacePos.xyz;
            projCoords.y *= -1;
            
            projCoords /= lightSpacePos.w;
            projCoords = projCoords * 0.5 + float3(0.5, 0.5, 0.5);
            
            currentDepth = projCoords.z;
            closestDepth = shadowMap1.sample(textureSampler, projCoords.xy);
            
            inShadow = currentDepth - bias > closestDepth;
            shadow = 0.0;
            float2 texelSize = 1.0 / float2(shadowMap1.get_width(), shadowMap1.get_height());
            for(int x = -1; x <= 1; ++x)
            {
                for(int y = -1; y <= 1; ++y)
                {
                    float2 offset = float2(x,y) * texelSize;
                    float pcfDepth = shadowMap1.sample(textureSampler, projCoords.xy + offset);
                    shadow += currentDepth - bias > pcfDepth ? 1.0 : 0.0;
                }
            }
            shadow /= 9.0;
            
            dc = float3(0,1,0);
        }
        
        if(distAlpha < .2) {
            float4 lightSpacePos = lt0->projection * lt0->view * float4(position, 1.0f);
            float3 projCoords = lightSpacePos.xyz;
            projCoords.y *= -1;
            projCoords /= lightSpacePos.w;
            projCoords = projCoords * 0.5 + float3(0.5, 0.5, 0.5);
            
            currentDepth = projCoords.z;
            closestDepth = shadowMap0.sample(textureSampler, projCoords.xy);
            
            inShadow = currentDepth - bias > closestDepth;
            shadow = 0.0f;
            
            float2 texelSize = 1.0 / float2(shadowMap0.get_width(), shadowMap0.get_height());
            for(int x = -1; x <= 1; ++x)
            {
                for(int y = -1; y <= 1; ++y)
                {
                    float2 offset = float2(x,y) * texelSize;
                    float pcfDepth = shadowMap0.sample(textureSampler, projCoords.xy + offset);
                    shadow += currentDepth - bias > pcfDepth ? 1.0 : 0.0;
                }
            }
            shadow /= 9.0;
            
            
            dc = float3(0,0,1);
        }
    }
    
    // visualize the regions
    // lightColor = dc;
    
    shadow = rs->useShadowMap? shadow : 0.0f;
    ao = rs->useSSAO? ao : 1.0f;
    
    float3 out = float3(0.0f);

    out = calculateDirectionalLight(position, normal, directionalLightDir, dirLightColor, cd->position.xyz, shadow);
    out *= color.xyz * ao;
     
    
    // the backdrop is the skybox, whose colors are written in the gPositionRT.
    // The linear depth is also stored in the w component of each position,
    // so if it's out of the projection, then we render the skybox colors
    if(depthNDC >= 1) {
        out = positionWSRaw.xyz;
    }
    
    float distFromCam = distance(positionWS.xz, cd->position.xz);
    
    // NOTE: uniform bug? wrong values uploaded
    float fogDist = 150.f;
    float3 fogColor = float3(179,199,209) / 255;
    
    float distFromCamAlpha = distFromCam / fogDist;
    
    float2 r = float2(0.995, 1.0);
    if(distFromCamAlpha > r.x && depthNDC < 1) {
        float a = (distFromCamAlpha - r.x) / (r.y - r.x);
        a = clamp(a, 0.0f, 1.0f);
        
        out = mix(out, fogColor, depthNDC >= 1? 1 : a);
    }
    
    //out = float3(positionWS.xyz);
    //  bool insideLightOrtho = ! (projCoords.x > 1 || projCoords.x < 0 || projCoords.y > 1 || projCoords.y < 0 || projCoords.z < 0 || projCoords.z > 1);
    
    return float4(out, 1.0f);

}

struct GeometryFragmentOut {
    float4 positionWS [[color(0)]];
    float4 normalWS [[color(1)]];
    float4 albedoSpec [[color(2)]];
    float4 emission [[color(3)]];
};

// for voxels
vertex VertexOut geometryPassVS(uint vertexID [[vertex_id]],
                                constant VertexData* vertexData [[buffer(0)]],
                                constant CameraData* cd [[buffer(1)]])
{
    VertexOut out;
    out.position = cd->projection * cd->view * vertexData[vertexID].position;
    out.textureCoordinate = vertexData[vertexID].textureCoordinates;
    out.normal = vertexData[vertexID].normal;
    out.atlasIndex = vertexData[vertexID].atlasIndex;
    out.positionWS = vertexData[vertexID].position;
    out.posNDC = out.position;
    out.colorScale = vertexData[vertexID].colorScale;

    return out;
}

fragment GeometryFragmentOut geometryPassFS(VertexOut in [[stage_in]], texture2d<float> colorTexture [[texture(0)]])
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
    
    GeometryFragmentOut out;
    
    // we hardcode "brightness" checking, perhaps this can change when I implement
    // HDR
    bool emitsLight = length(in.colorScale) > 0.01;
    float3 colorScale = emitsLight? in.colorScale : float3(1.f);
    out.albedoSpec = colorSample * float4(colorScale, 1.f);
    
    out.emission = emitsLight? out.albedoSpec : float4(0.0, 0.0, 0.0, 1.f);
    
    out.positionWS = in.positionWS; // in.position;
    
    // store linear depth into w-component
    float3 projCoords = in.posNDC.xyz / in.posNDC.w;
    //projCoords = projCoords * 0.5 + float3(0.5, 0.5, 0.5);
    out.positionWS.w = projCoords.z;
    
    out.normalWS = float4(in.normal, 0.0f);
    
    return out;
}
