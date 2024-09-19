#pragma once

#define GLFW_INCLUDE_NONE
#import <GLFW/glfw3.h>

#define GLFW_EXPOSE_NATIVE_COCOA
#import <GLFW/glfw3native.h>

#include <Metal/Metal.hpp>
#include <Metal/Metal.h>
#include <QuartzCore/CAMetalLayer.hpp>
#include <QuartzCore/CAMetalLayer.h>
#include <QuartzCore/QuartzCore.hpp>
#include "Foundation/NSString.hpp"
#include <Foundation/Foundation.h>

#include <simd/simd.h>

#include <stb/stb_image.h>
#include "VertexDataTypes.hpp"
#include "Core/Texture.hpp"
#include <filesystem>
#include <array>
#include <map>
#include <queue>
#include <iostream>
#include <vector>
#include <thread>
#include <mutex>
#include <chrono>
#include <optional>

#import "AAPLMathUtilities.h"
#import "WorldGeneration/PerlinNoiseGenerator.hpp"
#import "Core/Camera.hpp"
#import "Voxel/VoxelTypes.hpp"

#include <assimp/scene.h>
#include "Core/Mesh/AssimpNodeManager.hpp"
#include "Core/Mesh/Animator.hpp"
#include "Core/CoreTypes.hpp"
#include "Core/ChunkRenderer.hpp"

#include "EngineInterface.hpp"
#include "Core/Drawables.hpp"
#include "concurrentqueue/concurrentqueue.h"

class Player;

static const int g_atlasNumCol = 32;
static const int g_atlasNumRow = 32;

static std::map<EVoxelType, VoxelAtlasEntry> voxelTypeAtlasIndexMap = {
    {EVoxelType::Grass, VoxelAtlasEntry(1,1,1,1,2,0)},
    {EVoxelType::Stone, VoxelAtlasEntry(3)},
    {EVoxelType::Dirt, VoxelAtlasEntry(0)},
    {EVoxelType::Water, VoxelAtlasEntry(g_atlasNumCol * 1 + 0)},
    {EVoxelType::Lamp, VoxelAtlasEntry(g_atlasNumCol * 2 + 0)}
};

struct ShadowLayerInfo {
    int resolution;
    float camAlpha; // value [0,1] denoting distance from main camera's near to far
};

static std::vector<ShadowLayerInfo> shadowLayerInfos = {
    {4096, 0.2}, {2048, 0.4}, {512, 1.0}
};

enum EPlayerCameraType {
    FirstPerson,
    ThirdPerson,
    Debug
};

class MTLEngine : public IEngine {
public:
    static const int loadDistance;
    static const int renderDistance;
    static const Int3D chunkDims;
    
public:
    MTLEngine()
    :  chunkGenPending(false), chunksToMeshPTok(moodycamel::ProducerToken(chunksToMesh))
    {}
    
    MTL::Device* getDevice() const { return metalDevice; }
    
    void init();
    void run();
    void cleanup();
    
    
    virtual int addLine(float3 p1, float3 p2, float thickness, float3 color);
    virtual void setLineTransform(int index, float3 p1, float3 p2, float thickness);
    virtual void setLineColor(int index, simd::float3 color);
    virtual void setLineVisibility(int index, bool isVisible);
    
protected:
    virtual void commitLines();

private:
    void initDevice();
    void initWindow();
    
    void createTriangle();
    void createSquare();
    void createCube();
    void createSphere();
    
    void initCameras();

    // chunk generation/mesh
    void initChunkGeneration();
    void initiatePerlinGeneration();
    void resolveChunkGeneration();
    void createPerlinGenerators();
    void tryGenerateChunk();
    void generateChunk(Int3D chunkIndex);
    void tryMeshChunk();
    void meshChunk(Int3D chunkIndex);
    void initChunkRenderers();
    
    // init
    void initCascadingShadowMaps();
    void initSSAO();
    void initSkybox();
    void initLightVolumePass();
    void initGaussianBlurPass();
    void initPostProcessPass();
    void initMeshRenderPass();
    void initLinePass();
    
    void createBuffers();
    void createDepthAndMSAATextures();
    void createGBufferTextures();
    void createShadowMapTextures();
    void createLineTextures();
    void createLightPassTextures();
    
    void createGeometryPassPipeline();
    void createLightingPassPipeline();
    void createShadowPassPipeline();
    
    void createLinePassPipeline();
    
    void createRenderPassDescriptor();
    
    void createLightingRenderPassDescriptor();
    void createShadowRenderPassDescriptor();
    
    void createLineRenderPassDescriptor();
    
    // for window resizing
    void updateRenderPassDescriptor();
    
    void createDefaultLibrary();
    void createCommandQueue();
    void createRenderPipeline();

    void renderChunk(const Chunk& chunk);
    void sendRenderCommand();
    void draw();
    void drawChunkGeometry(MTL::RenderCommandEncoder* renderCommandEncoder);
    
    struct CameraMovementKeyMap {
        EKey forward;
        EKey back;
        EKey left;
        EKey right;
        EKey up;
        EKey down;
        EKey turnLeft;
        EKey turnRight;
        EKey turnUp;
        EKey turnDown;
    };
    
    void tickPlayerCameraThirdPerson(const float deltaTime, Camera& outCamera);
    void tickPlayerCameraFirstPerson(const float deltaTime, Camera& outCamera);
    
    void keyTick(const float deltaTime);
    void mouseTick(const float deltaTime);
    void engineTick(const float deltaTime);
    void physicsTick(const float deltaTime);
    void freeFloatingCameraTick(const float deltaTime, Camera& outCamera, const CameraMovementKeyMap keyMap);
    
    void bindShadowMapFrustumWithMainCamera(float zAlphaStart, float zAlphaEnd, Camera& shadowCam);
    
    void updateUniforms();
    Int3D calculateCurrentChunk(const float3 pos) const;
    void updateVisibleChunkIndices();
    
    // glfw callbacks
    static void frameBufferSizeCallback(GLFWwindow* window, int width, int height);
    static void glfwKeyCallback(GLFWwindow* window, int key, int scancode, int action, int mods);
    static void glfwMousePosCallback(GLFWwindow* window, double xpos, double ypos);
    // ~end glfw callbacks
    
    // engine callbacks
    void resizeFrameBuffer(int width, int height);
    void handleKeyInput(int key, int scancode, int action, int mods);
    void handleMousePos(double xpos, double ypos);
    // ~end engine callbacks
    //
    bool isKeyDown(const EKey k) const { return keydownArr[k]; }

    void addPointLight(float3 posWS, float3 color);

private:
    MTL::Device* metalDevice;
    GLFWwindow* glfwWindow;
    NSWindow* metalWindow;
    CAMetalLayer* metalLayer;
    CA::MetalDrawable* metalDrawable;
    
    MTL::Library* metalDefaultLibrary;
    MTL::CommandQueue* metalCommandQueue;
    MTL::CommandBuffer* metalCommandBuffer;
    
    //
    Texture* atlasTexture;
    
    // 
    // imgui
    //
    MTL::RenderPassDescriptor* imguiRenderPassDescriptor;
    
    //
    // lighting pass (final step of deferred shading)
    //
    MTL::RenderPipelineState* lightingRenderPipeline;
    MTL::RenderPassDescriptor* lightingRenderPassDescriptor;
    MTL::Texture* msaaRenderTarget = nullptr;
    
    //
    // lines
    //
    MTL::RenderPipelineState* linePassPipeline;
    MTL::RenderPassDescriptor* linePassDescriptor;
    MTL::DepthStencilState* lineDepthStencilState;
    MTL::Texture* debugRT = nullptr;
    MTL::Texture* debugDepthRT = nullptr;
    MTL::Buffer* lineBuffer;
    MTL::Buffer* lineTransformsBuffer = nullptr;
    MTL::Buffer* lineSquareVB = nullptr;
    MTL::Buffer* lineSquareIB = nullptr;
    std::vector<LineVertexData> lineVertexData;
    std::vector<float4x4> lineTransforms;
    std::vector<LineData> lines;
    std::vector<LineData> visibleLines;
    int lineDataUBSize;
    bool linesDirty;
    int curLineIndex;
    MTL::Buffer* lineDataUB;
    
    //
    // cascading shadow maps
    // 
    std::vector<MTL::Texture*> shadowMapRTs;
    std::vector<MTL::RenderPassDescriptor*> shadowMapRPDescriptors;
    std::vector<Camera> shadowMapCameras;
    std::vector<MTL::Buffer*> shadowCameraUBs;
    MTL::Texture* shadowMapColorRT = nullptr;
    MTL::RenderPipelineState* voxelShadowMapRPS;
    MTL::RenderPipelineState* skeletalMeshShadowMapRPS;
    int sampleCount = 4;
    MTL::DepthStencilState* shadowDepthStencilState;
    
    //
    // ssao
    // 
    MTL::Buffer* ssaoKernelUB;
    MTL::Texture* ssaoNoiseTex;
    MTL::Texture* ssaoRT;
    MTL::Texture* ssaoBlurRT;
    MTL::RenderPipelineState* ssaoRenderPipeline;
    MTL::RenderPipelineState* ssaoBlurRenderPipeline;
    MTL::RenderPassDescriptor* ssaoRenderPassDescriptor;
    MTL::RenderPassDescriptor* ssaoBlurRenderPassDescriptor;
    
    //
    // skybox
    //
    MTL::Texture* skyboxTex;
    MTL::Buffer* skyboxCubeVB;
    MTL::RenderPipelineState* skyboxRPS;
    MTL::RenderPassDescriptor* skyboxRPD;
    MTL::Buffer* skyboxMVPUB;
    
    //
    // sphere volume pipeline (render instanced spheres for each point-light)
    //
    MTL::RenderPipelineState* lightVolumeRPS;
    MTL::RenderPassDescriptor* lightVolumeRPD;
    MTL::Buffer* lightVolumeInstanceUB;
    int numLights;
    
    std::vector<LightVolumeData> pointLights;
    std::mutex pointLightArrMutex;
    int curPointLightIndex;
    
    //
    // bloom - gaussian blur pipeline
    //
    MTL::RenderPipelineState* gaussianBlurRPSHorizontal;
    MTL::RenderPipelineState* gaussianBlurRPSVertical;
    MTL::RenderPassDescriptor* gaussianBlurRPD0;
    MTL::RenderPassDescriptor* gaussianBlurRPD1;
    MTL::Buffer* gaussianBlurUB;
    MTL::Texture* gaussianBlurRT0;
    MTL::Texture* gaussianBlurRT1;
    
    //
    // combine pipeline
    //
    MTL::RenderPipelineState* postProcessRPS;
    MTL::RenderPassDescriptor* postProcessRPD;
    MTL::Texture* lightPassRT;
    
    //
    // mesh render pipeline (renders to g-buffer)
    // 
    MTL::Texture* gPositionRT = nullptr;
    MTL::Texture* gNormalRT = nullptr;
    MTL::Texture* gAlbedoSpecRT = nullptr;
    MTL::Texture* gEmissionRT = nullptr;
    MTL::Texture* depthRenderTarget = nullptr;
    // meshes
    MTL::RenderPipelineState* meshRPS;
    MTL::RenderPassDescriptor* meshRPD;
    // voxel geometry
    MTL::RenderPassDescriptor* renderPassDescriptor;
    MTL::DepthStencilState* depthStencilState;
    MTL::RenderPipelineState* metalRenderPSO;
    

    // only needed in import step - ultimately loaded into buffer and doesn't change (since mesh is static)
    Player* player;
    
    //
    // physics
    //
    simd::float3 collisionPushBackVel;
    
    //
    // shape buffers (TODO: can abstract to Mesh)
    //
    MTL::Buffer* sphereVB;
    MTL::Buffer* sphereIB;
    int numSphereIndices;
    MTL::Buffer* cubeVB;
    MTL::Buffer* triangleVertexBuffer;
    MTL::Buffer* squareVertexBuffer;
    
    
    // 
    // input
    //
    std::array<bool, 104> keydownArr;
    bool isInitialMousePos = true;
    float2 curMousePos;
    float2 prevMousePos;
    bool captureMouse = true;
    bool spaceWasDown;
    
    //
    // camera
    //
    Camera camera;
    Camera debugCamera;
    Camera shadowMapCamera;
    EPlayerCameraType activeCameraType;
    MTL::Buffer* cameraUB;
    
    // 
    
    MTL::Buffer* renderStateUB;
    
    //
    // configuration / profiling
    //
    bool enableSSAO;
    bool enableShadowMap;
    int avgFPS;
    int numCollisions = 0;

    //
    // voxel creation/selection/removal
    // 
    DebugBox* playerVoxelSelectIndicator;
    int playerVoxelSelectionLineId;
    DebugRect* playerVoxelSelectedRect;

    struct VoxelSelection {
	Int3D chunk;
	Int3D voxelCoords;
    };

    // selectedRemoveVoxel. Note: the voxel coordinates may fall outside the dimensions,
    // which in that case we must adjust the chunk index
    std::optional<VoxelSelection> selectedVoxel;

    // the voxel that is in the direction of the face normal when calculating
    // selectedRemoveVoxel. Note: the voxel coordinates may fall outside the dimensions,
    // which in that case we must adjust the chunk index
    std::optional<VoxelSelection> selectedCreateVoxel; 
    
    std::vector<DebugRect*> debugRects;
    
    //
    // chunk/mesh generation
    // 
    std::vector<std::thread> chunkGenThreads;
    std::vector<std::thread> meshGenThreads;
    // thread to check which chunks, say set C, need perlin generators
    //  - will then add all chunks in C to the terrain generation queue
    std::thread perlinGenThread;
    std::map<Int3D, PerlinNoiseGenerator> generators;
    moodycamel::ConcurrentQueue<Int3D> chunksToGenerate;
    moodycamel::ConcurrentQueue<Int3D> chunksToMesh;
    moodycamel::ProducerToken chunksToMeshPTok;
    std::mutex chunksToMeshPTokMutex;
    std::mutex loadedChunksMutex;
    std::mutex cachedChunkRDMutex;
    bool chunkGenPending;

    // all loaded chunks
    std::map<Int3D, Chunk> loadedChunks;
    std::map<Int3D, std::shared_ptr<ChunkRenderer>> chunkRenderers;
    std::vector<Int3D> sortedVisibleChunks;
    
    bool visibleChunksDirty;
    MTL::Buffer* visibleChunkBuffer;
    int numVisibleChunkVertices;
    Int3D curChunk;
    
    std::vector<Chunk> chunks;
};
