//
//  mtl_engine.m
//  MetalTutorial
//
//  Created by Ronnin Padilla on 7/19/24.
//

#import "Engine.hpp"
#include <mutex>
#import <iostream>
#include <format>
#import <chrono>
#import <map>
#import <tuple>
#import <memory>

#include "imgui.h"
#include "imgui_impl_glfw.h"
#include "imgui_impl_metal.h"

#include <thread>
#include <set>
#include <algorithm>
#include <random>

#include "assimp/Importer.hpp"
#include <assimp/scene.h>
#include <assimp/postprocess.h>

#include "WorldGeneration/PerlinNoiseGenerator.hpp"
#include "Math/CommonMath.hpp"
#include "Utilities/Profiling.hpp"
#include "Gameplay/Player.hpp"

#include <stb/stb_image.h>

const int MTLEngine::loadDistance = 16;
const int MTLEngine::renderDistance = 10;
const Int3D MTLEngine::chunkDims = {16,32,16};


void MTLEngine::init() {
    //  - generate PerlinGenerator per chunk, radiating from origin chunk (Breadth-first search) (single-thread)
    //      - during gameplay, re-create this thread if there's a good reason to (e.g. player moves chunks)
    //  - add chunk to queue denoting it is ready for vertex buffer generation (can be spread out over X threads)
    //      - finished vertex buffer added to cache
    //  - chunk renderers will just check if vertex buffer is ready, and render only if it is
    //  - as player moves, repeat step 1 for the new chunks within loadDistance
    
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO(); (void)io;
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;  // Enable Keyboard Controls
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;   // Enable Gamepad Controls

    // Setup style
    ImGui::StyleColorsDark();

    curLineTransformIndex = 1;
    curLineIndex = 0;
    
    visibleChunkBuffer = nullptr;
    visibleChunksDirty = true;
    curChunk = Int3D(0,0,0);
    
    spaceWasDown = false;
    showShadowMap = false;
    debugState = 0;
    
    keydownArr.fill(false);
    
    enableSSAO = true;
    enableShadowMap = true;
    
    initDevice();
    initWindow();
    
    initCameras();
    //initPlayerMesh();
    
    // Setup Platform/Renderer backends
    ImGui_ImplGlfw_InitForOpenGL(glfwWindow, true);
    ImGui_ImplMetal_Init(this->metalDevice);
    
    atlasTexture = new Texture("assets/aldi_brand_minecraft_atlas.png", metalDevice, STBI_rgb_alpha);
    
    
    createSquare();
    createSphere();
    
    createBuffers();
    
    
    createDefaultLibrary();
    createCommandQueue();
    createRenderPipeline();
    createLightingPassPipeline();
    // createShadowPassPipeline();
    //createLinePassPipeline();
    
    createDepthAndMSAATextures();
    createGBufferTextures();
    // createShadowMapTextures();
    //createLineTextures();
    createLightPassTextures();

    createRenderPassDescriptor();
    createLightingRenderPassDescriptor();
    // createShadowRenderPassDescriptor();
    createLineRenderPassDescriptor();
    
    initCascadingShadowMaps();
    initSSAO();
    initSkybox();
    initLightVolumePass();
    initGaussianBlurPass();
    initPostProcessPass();
    initMeshRenderPass();
    initLinePass();
    
    
    initChunkGeneration();
    resolveChunkGeneration();
    initChunkRenderers();
    updateVisibleChunkIndices();
    
    player = new Player(this, metalDevice);
    activeCameraType = EPlayerCameraType::ThirdPerson;
}

void MTLEngine::run() {
    auto prevTime = std::chrono::steady_clock::now();
    float msSoFar = 0.0f;
    int numFramesSoFar = 0;
    
    while (!glfwWindowShouldClose(glfwWindow)) {
        auto currentTime = std::chrono::steady_clock::now();
        float deltaTimeMS = std::chrono::duration_cast<std::chrono::milliseconds> (currentTime - prevTime).count();
        
        msSoFar += deltaTimeMS;
        
        if(msSoFar >= 1000.0f) {
            msSoFar = 0.0f;
            avgFPS = numFramesSoFar;
            numFramesSoFar = 0;
        }
        
        @autoreleasepool {
            metalDrawable = (__bridge CA::MetalDrawable*)[metalLayer nextDrawable];
            
            engineTick(deltaTimeMS / 1000.0f); // convert to seconds
            draw();
        }
        glfwPollEvents();
        
        prevTime = currentTime;
        ++numFramesSoFar;
    }
}

void MTLEngine::cleanup() {
    // Cleanup
   ImGui_ImplMetal_Shutdown();
   ImGui_ImplGlfw_Shutdown();
   ImGui::DestroyContext();
    
    glfwTerminate();
    //transformationUB->release();
    msaaRenderTarget->release();
    depthRenderTarget->release();
    renderPassDescriptor->release();
    metalDevice->release();
    delete atlasTexture;
}

void MTLEngine::initDevice() {
    metalDevice = MTL::CreateSystemDefaultDevice();
}

void MTLEngine::initWindow() {
    glfwInit();
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindow = glfwCreateWindow(1200, 900, "Metal Engine", NULL, NULL);
    if (!glfwWindow) {
        glfwTerminate();
        exit(EXIT_FAILURE);
    }
    
    glfwSetWindowUserPointer(glfwWindow, this);
    glfwSetInputMode(glfwWindow, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
    glfwSetWindowSizeCallback(glfwWindow, frameBufferSizeCallback);
    glfwSetKeyCallback(glfwWindow, glfwKeyCallback);
    glfwSetCursorPosCallback(glfwWindow, glfwMousePosCallback);
    
    int width, height;
    glfwGetFramebufferSize(glfwWindow, &width , &height);
    
    metalWindow = glfwGetCocoaWindow(glfwWindow);
    metalLayer = [CAMetalLayer layer];
    metalLayer.device = (__bridge id<MTLDevice>)metalDevice;
    metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    metalLayer.drawableSize = CGSizeMake(width, height);
    metalWindow.contentView.layer = metalLayer;
    metalWindow.contentView.wantsLayer = YES;
    
    metalDrawable = (__bridge CA::MetalDrawable*)[metalLayer nextDrawable];
}

void MTLEngine::createTriangle() { 
    simd::float3 triangleVertices[] = {
        {-0.5f, -0.5f, 0.0f},
        { 0.5f, -0.5f, 0.0f},
        { 0.0f,  0.5f, 0.0f}
    };
    
    
    
    triangleVertexBuffer = metalDevice->newBuffer(&triangleVertices,
                                                  sizeof(triangleVertices),
                                                  MTL::ResourceStorageModeShared);
}

void MTLEngine::createSquare() {
    LightingPassVertexData squareVertices[] {
            {{-1.0f, -1.0f,  1.0f, 1.0f}, {0.0f, 1.0f}},
            {{-1.0f,  1.0f,  1.0f, 1.0f}, {0.0f, 0.0f}},
            {{ 1.0f,  1.0f,  1.0f, 1.0f}, {1.0f, 0.0f}},
            {{-1.0f, -1.0f,  1.0f, 1.0f}, {0.0f, 1.0f}},
            {{ 1.0f,  1.0f,  1.0f, 1.0f}, {1.0f, 0.0f}},
            {{ 1.0f, -1.0f,  1.0f, 1.0f}, {1.0f, 1.0f}}
    };
    
    squareVertexBuffer = metalDevice->newBuffer(&squareVertices, sizeof(squareVertices), MTL::ResourceStorageModeShared);
}

void MTLEngine::createCube() {
    // Cube for use in a right-handed coordinate system with triangle faces
    // specified with a Counter-Clockwise winding order.
    VertexData cubeVertices[] = {
        // Front face
        {{-0.5, -0.5, 0.5, 1.0}, {0.0, 0.0}},
        {{0.5, -0.5, 0.5, 1.0}, {1.0, 0.0}},
        {{0.5, 0.5, 0.5, 1.0}, {1.0, 1.0}},
        {{0.5, 0.5, 0.5, 1.0}, {1.0, 1.0}},
        {{-0.5, 0.5, 0.5, 1.0}, {0.0, 1.0}},
        {{-0.5, -0.5, 0.5, 1.0}, {0.0, 0.0}},

        // Back face
        {{0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}},
        {{-0.5, -0.5, -0.5, 1.0}, {1.0, 0.0}},
        {{-0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}},
        {{-0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}},
        {{0.5, 0.5, -0.5, 1.0}, {0.0, 1.0}},
        {{0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}},

        // Top face
        {{-0.5, 0.5, 0.5, 1.0}, {0.0, 0.0}},
        {{0.5, 0.5, 0.5, 1.0}, {1.0, 0.0}},
        {{0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}},
        {{0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}},
        {{-0.5, 0.5, -0.5, 1.0}, {0.0, 1.0}},
        {{-0.5, 0.5, 0.5, 1.0}, {0.0, 0.0}},

        // Bottom face
        {{-0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}},
        {{0.5, -0.5, -0.5, 1.0}, {1.0, 0.0}},
        {{0.5, -0.5, 0.5, 1.0}, {1.0, 1.0}},
        {{0.5, -0.5, 0.5, 1.0}, {1.0, 1.0}},
        {{-0.5, -0.5, 0.5, 1.0}, {0.0, 1.0}},
        {{-0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}},

        // Left face
        {{-0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}},
        {{-0.5, -0.5, 0.5, 1.0}, {1.0, 0.0}},
        {{-0.5, 0.5, 0.5, 1.0}, {1.0, 1.0}},
        {{-0.5, 0.5, 0.5, 1.0}, {1.0, 1.0}},
        {{-0.5, 0.5, -0.5, 1.0}, {0.0, 1.0}},
        {{-0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}},

        // Right face
        {{0.5, -0.5, 0.5, 1.0}, {0.0, 0.0}},
        {{0.5, -0.5, -0.5, 1.0}, {1.0, 0.0}},
        {{0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}},
        {{0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}},
        {{0.5, 0.5, 0.5, 1.0}, {0.0, 1.0}},
        {{0.5, -0.5, 0.5, 1.0}, {0.0, 0.0}},
    };
    
    cubeVB = metalDevice->newBuffer(&cubeVertices, sizeof(cubeVertices), MTL::ResourceStorageModeShared);
}

void MTLEngine::createSphere() {
    // Simple sphere from:
    // https://github.com/Erkaman/cute-deferred-shading/blob/master/src/main.cpp#L573
    
    int stacks = 6;
    int slices = 6;
    const float PI = 3.14f;

    std::vector<PositionVertexData> positions;
    std::vector<uint32_t> indices;

    // loop through stacks.
    for (int i = 0; i <= stacks; ++i){

        float V = (float)i / (float)stacks;
        float phi = V * PI;

        // loop through the slices.
        for (int j = 0; j <= slices; ++j){

            float U = (float)j / (float)slices;
            float theta = U * (PI * 2);

            // use spherical coordinates to calculate the positions.
            float x = cos(theta) * sin(phi);
            float y = cos(phi);
            float z = sin(theta) * sin(phi);
            
            PositionVertexData pvd;
            pvd.position = make_float4(x,y,z, 1.0f);
            positions.push_back(pvd);
        }
    }

    // Calc The Index Positions
    for (int i = 0; i < slices * stacks + slices; ++i){
        indices.push_back(i);
        indices.push_back(i + slices + 1);
        indices.push_back(i + slices);

        indices.push_back(i + slices + 1);
        indices.push_back(i);
        indices.push_back(i + 1);
    }
    
    sphereVB = metalDevice->newBuffer(positions.data(), sizeof(PositionVertexData) * positions.size(), MTL::ResourceStorageModeShared);
    sphereIB = metalDevice->newBuffer(indices.data(), sizeof(uint32_t) * indices.size(), MTL::ResourceStorageModeShared);
    numSphereIndices = indices.size();
}

void MTLEngine::initCameras() {
    Camera::InitParams perspParams;
    // perspParams.pos = make_float3(-chunkDims.x, chunkDims.y, 0);
    perspParams.pos = make_float3(0, 0, 0);
    perspParams.pitch = 0;
    perspParams.yaw = 0;
    perspParams.speed = 5;
    perspParams.rotateSpeed = 80.0f;
    perspParams.isOrtho = false;
    perspParams.useYawPitch = true;
    perspParams.sensitivity = 0.1;
    
    // aspect ratio must be updated every frame, or at least whenever the viewport is resized
    float aspectRatio = (metalLayer.frame.size.width / metalLayer.frame.size.height);
    
    // main camera
    camera = Camera(perspParams);
    camera.setAspectRatio(aspectRatio);
    camera.setFOVDeg(70);
    camera.setNearZ(0.1f);
    camera.setFarZ(300.0f);
    
    // debug camera
    debugCamera = Camera(perspParams);
    
    debugCamera.setAspectRatio(aspectRatio);
    debugCamera.setFOVDeg(45);
    debugCamera.setNearZ(0.1f);
    debugCamera.setFarZ(120.0f);
    
    // shadow map orthographic camera (for directional light)
    //
    // position, and orthographic projection properties are set every frame
    // (as they depend on the main camera's view frustum)
    Camera::InitParams shadowCamParams;
    shadowCamParams.isOrtho = true;
    shadowCamParams.useYawPitch = false;

    shadowMapCamera = Camera(shadowCamParams);
    
    shadowMapCameras.clear();
    for(int i = 0; i < shadowLayerInfos.size(); i++) {
        shadowMapCameras.push_back(shadowCamParams);
    }
}

void MTLEngine::initChunkGeneration() {
    
    // init worker threads
    {
        chunkGenThreads.clear();
        int numWorkers = 4;
        for(int i = 0; i < numWorkers; i++) {
            chunkGenThreads.push_back(std::thread(&MTLEngine::tryGenerateChunk, this));
        }
    }
    {
        meshGenThreads.clear();
        int numWorkers = 4;
        for(int i = 0; i < numWorkers; i++) {
            meshGenThreads.push_back(std::thread(&MTLEngine::tryMeshChunk, this));
        }
    }
    
}

void MTLEngine::resolveChunkGeneration() {
    // https://stackoverflow.com/a/36224563
    if(perlinGenThread.joinable()) {
        std::cout << "perlinGenThread is busy" << std::endl;
        return;
    }
    
    chunkGenPending = false;
    
    perlinGenThread = std::thread(&MTLEngine::createPerlinGenerators, this);
}

void MTLEngine::createPerlinGenerators() {
    // perlinGenThreadBusy = true;
    // bfs
    //
    //
    const int3 perlinRes = {1,1,1};
    
    std::set<Int3D> seen;
    
    std::queue<Int3D> queue;
    
    
    queue.push(curChunk);
    seen.insert(queue.front());
    
    while(!queue.empty()) {
        Int3D index = queue.front();
        queue.pop();
        
        // imagine top-down view
        const Int3D right = index + Int3D(1, 0, 0);
        const Int3D left = index + Int3D(-1, 0, 0);
        const Int3D top = index + Int3D(0, 0, 1);// top as in +z
        const Int3D bottom = index + Int3D(0, 0, -1);
        
        if(!generators.contains(index)) {
            PerlinNoiseGenerator newGenerator(perlinRes);
            
            // try to sync faces if the corresponding generator exists
            // (we only generate of XZ plane, so only neighbors in that dimension)
            
            // 0: YZ face when x==0
            // 1: YZ face when x==resolution.x
            // 2: XZ face when y==0 (not used)
            // 3: XZ face when y==resolution.y (not used)
            // 4: XY face when z==0
            // 5: XY face when z==resolution.z
            if(generators.contains(right)) {
                newGenerator.syncFace(generators[right], 0, 1);
            }
            
            if(generators.contains(left)) {
                newGenerator.syncFace(generators[left], 1, 0);
            }
            
            if(generators.contains(top)) {
                newGenerator.syncFace(generators[top], 4, 5);
            }
            
            if(generators.contains(bottom)) {
                newGenerator.syncFace(generators[bottom], 5, 4);
            }
            
            generators.insert({index, newGenerator});
            
            // this chunk is ready to generate, and should be generated right away
            // perhaps there's a "watcher" thread, watching chunksToGenerate and
            // dispatches jobs as the queue fills up
	    //
	    chunksToGenerate.enqueue(index);
            // std::lock_guard<std::mutex> guard(chunksToGenerateMutex);
            //chunksToGenerate.push(index);
        }
        else {
            // checking dup is fine, since we always start from the chunk where the player is.
            // - We will constantly be checking loadDistance * loadDistance chunks in this queue.
            // - A better solution would be storing the current edge chunks and performing bfs from there
            // - That would make this operation go from O(n^2) to O(2n)==O(n) where n is loadDistance
            
            // std::cout << "Checking dup!!!" << std::endl;
        }
        
        
        if(abs(curChunk.x - index.x) < loadDistance &&
           abs(curChunk.z - index.z) < loadDistance) {
            
            std::array<Int3D, 4> neighbors = {left, right, top, bottom};
            
            for(int i = 0; i < 4; i++) {
                const Int3D& curNeighbor = neighbors[i];
                if(!seen.contains(curNeighbor)) {
                    seen.insert(curNeighbor);
                    queue.push(curNeighbor);
                }
            }
        }
    }
    
    // dispatch chunk generation jobs
    // std::cout << "generators finished" << std::endl;
    
    // perlinGenThreadBusy = false;
    perlinGenThread.detach();
}

void MTLEngine::tryGenerateChunk() {
    using namespace std::chrono_literals;
    
    while(true) {
        std::optional<Int3D> chunkToGen;
        {
	    Int3D chunkInd;
            if(chunksToGenerate.try_dequeue(chunkInd)) {
		chunkToGen = chunkInd;
            }
        }
        
        if(chunkToGen.has_value()) {
            generateChunk(chunkToGen.value());
        }

	// TODO: need std::conditional
        std::this_thread::sleep_for(10ms);
    }
}

void MTLEngine::generateChunk(Int3D chunkIndex) {
    // generates chunk's voxel types and initializes its vertex buffer

    Chunk newChunk(this);
    newChunk.setDimensions(chunkDims);
    newChunk.setIndex(chunkIndex);
    
    // generate chunk voxel data
    {
        // Timer ttt("Generate chunk voxels");
        
        // const int3 chunkXYZ = make_int3(chunkIndex.x, chunkIndex.y, chunkIndex.z);
        
        // world position is its index * dimensions per chunk
        newChunk.setPosition(chunkIndex * chunkDims);
        
        float3 chunkDimsFloat3 = make_float3(chunkDims.x, chunkDims.y, chunkDims.z);
        
        PerlinNoiseGenerator perlin = generators[chunkIndex];
        int3 perlinRes = perlin.getResolution();
        float3 perlinResFloat3 = make_float3(perlinRes.x, perlinRes.y, perlinRes.z);
        
        const int seaLevel = 5;
        
        std::uniform_real_distribution<float> dis(0.f, 1.f);
        std::default_random_engine gen;
        
        const auto dims = newChunk.getDimensions();
        for(int x=0; x<dims.x; x++) {
            for(int y=0; y<dims.y; y++) {
                for(int z=0; z<dims.z; z++) {
                    float3 v = (make_float3(x,y,z) / chunkDimsFloat3) * perlinResFloat3; // * chunkDimsFloat3 + chunkPosFloat3;
                    
                    float p = perlin.noise(v);
                    
                    EVoxelType voxelType = EVoxelType::Dirt;
                    
                    float py = (float) y / dims.y;
                    
                    p += py * 0.9;
                    
                    // if y is high, more chance of being None
                    
                    
                    if(p > 0) {
                        voxelType = EVoxelType::None;
                    }
                    
                    if(y == 0) {
                        voxelType = EVoxelType::Stone;
                    }
                    
                    if(y == dims.y - 1) {
                        //  voxelType = EVoxelType::Stone;
                    }
                    
                    if(voxelType == EVoxelType::Dirt && y < seaLevel + (-25 * perlin.noise(v * 0.5) + 5)) {
                        voxelType = EVoxelType::Stone;
                    }
                    
                    if(voxelType == EVoxelType::None &&
                       y > 0 &&
                       newChunk.getVoxel(Int3D(x,y-1,z)) == EVoxelType::Dirt
                       ) {
                        
                        newChunk.setVoxel(Int3D(x,y-1,z), EVoxelType::Grass);
                    }
                    
                    if(y == dims.y - 1 && voxelType == EVoxelType::Dirt) {
                        voxelType = EVoxelType::Grass;
                    }
                    
                    if(voxelType == EVoxelType::None && y < seaLevel) {
                        voxelType = EVoxelType::Water;
                    }
                    
                    
                    //voxelType = EVoxelType::Water;
                    if(y == 0) {
                        //voxelType = EVoxelType::Stone;
                    }
                    
                    newChunk.setVoxel({x,y,z}, voxelType);
                }
            }
        }
        
        // 2nd pass (trees, etc.)
        for(int x=0; x<dims.x; x++) {
            for(int y=0; y<dims.y; y++) {
                for(int z=0; z<dims.z; z++) {
                    auto voxelType = newChunk.getVoxel(Int3D(x,y,z));
                    
                    
                    
                    
                    // 1% chance for lamp block
                    if((chunkIndex == Int3D(0,0,0) || chunkIndex == Int3D(1,0,0) || chunkIndex == Int3D(-1,0,0)) && voxelType == EVoxelType::Stone && y > seaLevel) {
                        Int3D curLocalInd (x,y,z);
                        bool hasEmptyNeighbor = false;
                        for(auto n : curLocalInd.getAllNeighbors()) {
                            hasEmptyNeighbor |= (newChunk.getVoxel(n) == EVoxelType::None);
                        }
                        
                        if(hasEmptyNeighbor && dis(gen) > 0.9f) {
                            
                            voxelType = EVoxelType::Lamp;
                            
                            float3 randColor {dis(gen), dis(gen), dis(gen)};
                            newChunk.setVoxelLightColor({x,y,z}, randColor);
                            
                            float3 voxelPosWS = newChunk.getPositionAsFloat3() + make_float3(x,y,z);
                            addPointLight(voxelPosWS + make_float3(0.5, 0.5, 0.5), randColor);
                            newChunk.setVoxel({x,y,z}, voxelType);
                        }
                    }
                }
            }
        }
    }
    
    {
        std::lock_guard<std::mutex> guard(loadedChunksMutex);
        loadedChunks.insert({chunkIndex, newChunk});
    }
    
    {
	std::lock_guard<std::mutex> guard(chunksToMeshPTokMutex);
	assert(chunksToMesh.enqueue(chunksToMeshPTok, chunkIndex));
    }
}

void MTLEngine::tryMeshChunk() {
    using namespace std::chrono_literals;
    
    while(true) {
        std::optional<Int3D> chunkToMesh;
	Int3D chunkInd;
	if(chunksToMesh.try_dequeue(chunkInd)) {
	    // we can only mesh the chunk if all of its neighbors are loaded
	    bool allNeighborsLoaded = true;
	    {
		std::lock_guard<std::mutex> guard(loadedChunksMutex);
		auto neighbors = chunkInd.getNeighbors();
		for(const auto n: neighbors) {
		    bool hasNeighbor = loadedChunks.find(n) != loadedChunks.end();
		    allNeighborsLoaded &= hasNeighbor;
		}
	    }
	    
	    if(allNeighborsLoaded) {
		chunkToMesh = chunkInd;
	    }
	    else {
		// re-queue
		//
		std::lock_guard<std::mutex> guard(chunksToMeshPTokMutex);
		assert(chunksToMesh.enqueue(chunksToMeshPTok, chunkInd));
		
		// std::cout << "re-queueing chunk: " << chunkInd.x << ", " << chunkInd.y << ", " << chunkInd.z << std::endl;
	    }
	}
        
        if(chunkToMesh.has_value()) {
	    //std::cout << "meshing chunk: " << chunkInd.x << ", " << chunkInd.y << ", " << chunkInd.z << std::endl;
            meshChunk(chunkToMesh.value());
        }

        std::this_thread::sleep_for(50ms);
    }
}

void MTLEngine::meshChunk(Int3D chunkIndex) {
    Chunk* chunk;
    std::array<Chunk*, 4> neighbors;
    {
        std::lock_guard<std::mutex> guard(loadedChunksMutex);
        chunk = &loadedChunks.at(chunkIndex);
        auto neighborInds = chunkIndex.getNeighbors();
        for(int i=0; i<(int)neighborInds.size(); i++) {
            neighbors[i] = &loadedChunks.at(neighborInds[i]);
        }
    }
    
    std::vector<VertexData> chunkVertices;
    std::vector<VertexData> transparentVertices;
    
    {
        // Timer ttt("Chunk Greedy Meshing");
        
        // greedy meshing
        Int3D dimsU = chunk->getDimensions();
        std::array<int, 3> dims = { (int) dimsU.x, (int) dimsU.y, (int) dimsU.z};
        
        struct Quad {
            Quad() = default;
            
            std::array<float4, 4> positions; // world-space positions
            float3 normal;
            float width;
            float height;
            EVoxelType vxType;
        };
        
        std::vector<Quad> quads;
        std::vector<Quad> waterQuads;
        // std::vector<int2> quadHW;
        
        // TODO: chunk will hold array of possible voxel types it currently has
        std::vector<EVoxelType> voxelTypesToCheck = {EVoxelType::Grass, EVoxelType::Dirt, EVoxelType::Stone, EVoxelType::Water};
        
        // this currently costs: O(n * dims^3) where n is number of voxel types
        for(const EVoxelType& voxelType : voxelTypesToCheck) {
            for(int d=0; d<3; d++) {
                // std::cout << "mask = " << d << std::endl;
                int u = (d+1)%3;
                int v = (d+2)%3;
                std::array<int, 3> x = {0,0,0};
                std::array<int, 3> q = {0,0,0}; // delta
                
                struct MaskData {
                    MaskData() = default;
                    MaskData(bool incident, bool isBackface)
                    : incident(incident), isBackface(isBackface) {};
                    
                    bool incident;
                    bool isBackface;
                };
                std::vector<MaskData> mask(dims[u] * dims[v], MaskData());
                
                
                q[d] = 1;
                
                for(x[d]=-1; x[d]<(int)dims[d]; ) {
                    int n = 0;
                    
                    for(x[v]=0; x[v]<dims[v]; x[v]++) {
                        for(x[u]=0; x[u]<dims[u]; x[u]++) {
                            
                            // d==0 front-back
                            // d==1 top-bottom
                            // d==2 left-right
                            Chunk* beforeChunk = nullptr;
                            Chunk* afterChunk = nullptr;
                            if(d==0) {
                                beforeChunk = neighbors[1];
                                afterChunk = neighbors[0];
                            }
                            else if(d==2) {
                                beforeChunk = neighbors[3];
                                afterChunk = neighbors[2];
                            }
                            
                            const bool xInRangeLeft = x[d] >= 0; // only invalid when x[d]==-1 on first iteration
                            const bool xInRangeRight = x[d] < dims[d] - 1;
                            
                            bool xVal = false;
                            
                            EVoxelType xValType = EVoxelType::None;
                            EVoxelType xDeltaValType = EVoxelType::None;
                            
                            if(xInRangeLeft) {
                                xValType = chunk->getVoxel({(int) x[0], (int) x[1], (int) x[2]});
                            }
                            else {
                                if(d != 1) {
                                    if(d == 0) {
                                        xValType = beforeChunk->getVoxel({(int) dims[d] - 1, (int) x[1], (int) x[2]});
                                    }
                                    else if(d == 2) {
                                        xValType = beforeChunk->getVoxel({(int) x[0], (int) x[1], (int) dims[d] - 1});
                                    }
                                }
                                else {
                                    xValType = EVoxelType::None;
                                }
                            }
                            
                           
                            bool xDeltaVal = false;
                            if(xInRangeRight) {
                                xDeltaValType = chunk->getVoxel({(int) x[0] + q[0], (int) x[1]+q[1], (int) x[2]+q[2]});
                            }
                            else {
                                if(d != 1) {
                                    if(d == 0) {
                                        xDeltaValType = afterChunk->getVoxel({(int) 0, (int) x[1], (int) x[2]});
                                    }
                                    else if(d == 2) {
                                        xDeltaValType = afterChunk->getVoxel({(int) x[0], (int) x[1], (int) 0});
                                    }
                                }
                                else {
                                    xDeltaValType = EVoxelType::None;
                                }
                            }
                            
                            
                            /*
                             
                            const bool xVal = xInRangeLeft?
                            chunk.getVoxel({(int) x[0], (int) x[1], (int) x[2]}) == voxelType
                            : false;
                             
                             
                            const bool xDeltaVal = xInRangeRight?
                            chunk.getVoxel({(int) x[0] + q[0], (int) x[1]+q[1], (int) x[2]+q[2]}) == voxelType
                            : false;
                            */
                            
                            //
                            // depending which is seen determines the normal (and quad orientation)
                            //
                            // Say X is a non-empty voxel:
                            //
                            // [ |X| ] =>  - when x==0  =>  normal is <-
                            // [0|1|2]     - when x==1  =>  normal is ->
                            //
                            
                            bool incident = false;
                            bool isBackface = false;
                            
                            if(voxelType != EVoxelType::Water) {
                                if(xValType == voxelType && (xDeltaValType == EVoxelType::None || xDeltaValType == EVoxelType::Water)) {
                                    incident = true;
                                    isBackface = true;
                                }
                                
                                if(xDeltaValType == voxelType && (xValType == EVoxelType::None || xValType == EVoxelType::Water)) {
                                    incident = true;
                                    isBackface = false;
                                }
                            }
                            else {
                                if(xValType == voxelType && (xDeltaValType == EVoxelType::None)) {
                                    incident = true;
                                    isBackface = true;
                                }
                                
                                if(xDeltaValType == voxelType && (xValType == EVoxelType::None)) {
                                    incident = true;
                                    isBackface = false;
                                }
                            }
                            
                            
                            // mask[n] = MaskData(xVal != xDeltaVal, xVal && !xDeltaVal);
                            mask[n] = MaskData(incident, isBackface);
                            n++;
                        }
                    }
                    
                    x[d]++;
                    n = 0;
                    
                    for(int j=0; j<dims[v]; j++) {
                        for(int i=0; i<dims[u]; ) {
                            if(mask[n].incident) {
                                int w;
                                for(w=1; i+w<dims[u] && mask[n+w].incident ; w++) {
                                }
                                
                                bool done = false;
                                int h;
                                int k;
                                for(h=1; j+h<dims[v]; h++) {
                                    for(k=0; k<w; k++) {
                                        if(!mask[n+k+h*dims[u]].incident) {
                                            done = true;
                                            break;
                                        }
                                    }
                                    if(done) {
                                        break;
                                    }
                                }
                                
                                
                                x[u] = i; x[v] = j;
                                std::array<int, 3> du = {0, 0, 0};
                                std::array<int, 3> dv = {0, 0, 0};
                                du[u] = w;
                                dv[v] = h;
                                
                                float4 worldOffset = chunk->getPositionAsFloat4();
                                
                                // coords in counter-clockwise (CCW)
                                std::array<float4, 4> verts = {
                                    make_float4(x[0], x[1], x[2], 1.0) + worldOffset,
                                    make_float4(x[0]+du[0], x[1]+du[1], x[2]+du[2], 1.0) + worldOffset,
                                    make_float4(x[0]+du[0]+dv[0], x[1]+du[1]+dv[1], x[2]+du[2]+dv[2], 1.0) + worldOffset,
                                    make_float4(x[0]+dv[0], x[1]+dv[1], x[2]+dv[2], 1.0) + worldOffset,
                                };
                                
                                // ordering to ensure CCW direction
                                static int order[6][4] = {
                                    {0,3,2,1}, // front-back
                                    {3,2,1,0}, // top-bottom
                                    {1,0,3,2}, // left-right
                                    
                                    {3,0,1,2}, // front-back (backface)
                                    {0,1,2,3}, // top-bottom (backface)
                                    {0,1,2,3}, // left-right (backface)
                                };
                                
                                Quad newQuad;
                                newQuad.vxType = voxelType;
                                
                                if(mask[n].isBackface) {
                                    newQuad.positions[0] = verts[order[d+3][0]];
                                    newQuad.positions[1] = verts[order[d+3][1]];
                                    newQuad.positions[2] = verts[order[d+3][2]];
                                    newQuad.positions[3] = verts[order[d+3][3]];
                                }
                                else{
                                    newQuad.positions[0] = verts[order[d][0]];
                                    newQuad.positions[1] = verts[order[d][1]];
                                    newQuad.positions[2] = verts[order[d][2]];
                                    newQuad.positions[3] = verts[order[d][3]];
                                }
                                
                                // BUG: width/height reversed in certain directions???
                                newQuad.width = d == 0? h : w;
                                newQuad.height = d == 0? w : h;
                                
                                if(d == 0) {
                                    newQuad.normal = make_float3(-1.0,0,0);
                                }
                                else if(d == 1) {
                                    // algo goes bottom to top
                                    newQuad.normal = make_float3(0,-1.0,0);
                                }
                                else if(d == 2) {
                                    newQuad.normal = make_float3(0,0,-1.0f);
                                }
                                
                                if(mask[n].isBackface) {
                                    newQuad.normal = -1 * newQuad.normal;
                                }
                                
                                // TODO: we can add quads to 3 separate arrays (when d=0,1,2)
                                // so we can assume normals when constructing the vertex buffer
                                if(voxelType == EVoxelType::Water) {
                                    waterQuads.push_back(newQuad);
                                }
                                else {
                                    quads.push_back(newQuad);
                                }
                                
                                for(int l=0; l<h; l++) {
                                    for(k=0; k<w; k++) {
                                        // reset
                                        mask[n+k+l*dims[u]] = MaskData();
                                    }
                                }
                                
                                i += w; n += w;
                            }
                            else {
                                i++;
                                n++;
                            }
                        }
                    }
                }
            }
        }
        
        const float3 defaultColorScale {0,0,0};
        
        for(int i=0; i<quads.size(); i++) {
            const Quad& q = quads[i];
            
            if(!voxelTypeAtlasIndexMap.contains(q.vxType)) {
                continue;
            }
            
            // rely on correct vertex-ordering for texture orientation,
            // as we treat these uv coords as a front-face for all faces.
            
            const VoxelAtlasEntry& atlasEntry = voxelTypeAtlasIndexMap[q.vxType];
            int atlasIndex = -1;
            
            EAxis collisionAxis = EAxis::X;
            
            if(q.normal.x == 1.0f) {
                atlasIndex = atlasEntry.right;
                collisionAxis = EAxis::X;
            }
            else if(q.normal.x == -1.0f) {
                atlasIndex = atlasEntry.left;
                collisionAxis = EAxis::X;
            }
            else if(q.normal.y == 1.0f) {
                atlasIndex = atlasEntry.top;
                collisionAxis = EAxis::Y;
            }
            else if(q.normal.y == -1.0f) {
                atlasIndex = atlasEntry.bottom;
                collisionAxis = EAxis::Y;
            }
            else if(q.normal.z == 1.0f) {
                atlasIndex = atlasEntry.front;
                collisionAxis = EAxis::Z;
            }
            else if(q.normal.z == -1.0f) {
                atlasIndex = atlasEntry.back;
                collisionAxis = EAxis::Z;
            }
            
            
            chunkVertices.push_back({q.positions[0], {0.0, 0.0}, q.normal, atlasIndex, defaultColorScale });
            chunkVertices.push_back({q.positions[1], {q.width, 0.0}, q.normal, atlasIndex, defaultColorScale });
            chunkVertices.push_back({q.positions[2], {q.width, q.height}, q.normal, atlasIndex, defaultColorScale });
            
            chunkVertices.push_back({q.positions[2], {q.width, q.height}, q.normal, atlasIndex, defaultColorScale });
            chunkVertices.push_back({q.positions[3], {0.0, q.height}, q.normal, atlasIndex, defaultColorScale });
            chunkVertices.push_back({q.positions[0], {0.0, 0.0}, q.normal, atlasIndex, defaultColorScale });
            
            std::array<simd::float3, 4> quadPosLS;
            for(int i = 0; i < q.positions.size(); i++) {
                quadPosLS[i] = q.positions[i].xyz - chunk->getPositionAsFloat3();
            }
            
            chunk->addCollisionRect(quadPosLS, q.normal);
        }
        
        for(int i=0; i<waterQuads.size(); i++) {
            const Quad& q = waterQuads[i];
            
            if(!voxelTypeAtlasIndexMap.contains(q.vxType)) {
                continue;
            }
            
            // rely on correct vertex-ordering for texture orientation,
            // as we treat these uv coords as a front-face for all faces.
            
            const VoxelAtlasEntry& atlasEntry = voxelTypeAtlasIndexMap[q.vxType];
            int atlasIndex = -1;
            
            if(q.normal.x == 1.0f) {
                atlasIndex = atlasEntry.right;
            }
            else if(q.normal.x == -1.0f) {
                atlasIndex = atlasEntry.left;
            }
            else if(q.normal.y == 1.0f) {
                atlasIndex = atlasEntry.top;
            }
            else if(q.normal.y == -1.0f) {
                atlasIndex = atlasEntry.bottom;
            }
            else if(q.normal.z == 1.0f) {
                atlasIndex = atlasEntry.front;
            }
            else if(q.normal.z == -1.0f) {
                atlasIndex = atlasEntry.back;
            }
            
            
            transparentVertices.push_back({q.positions[0], {0.0, 0.0}, q.normal, atlasIndex, defaultColorScale });
            transparentVertices.push_back({q.positions[1], {q.width, 0.0}, q.normal, atlasIndex, defaultColorScale });
            transparentVertices.push_back({q.positions[2], {q.width, q.height}, q.normal, atlasIndex, defaultColorScale });
            
            transparentVertices.push_back({q.positions[2], {q.width, q.height}, q.normal, atlasIndex, defaultColorScale });
            transparentVertices.push_back({q.positions[3], {0.0, q.height}, q.normal, atlasIndex, defaultColorScale });
            transparentVertices.push_back({q.positions[0], {0.0, 0.0}, q.normal, atlasIndex, defaultColorScale });
        }
        
        // invidiual voxels (voxels that shouldn't be merged, e.g. light blocks)
        // essentially non-terrain voxels, or more complex voxels that have their own attributes
        
        // Cube for use in a right-handed coordinate system with triangle faces
        // specified with a Counter-Clockwise winding order.
        
        const float3 fwd {0,0,1};
        const float3 top {0,1,0};
        const float3 right {1,0,0};
        std::vector<VertexData> cubeVertTemplate = {
            // Front face
            {{-0.5, -0.5, 0.5, 1.0}, {0.0, 0.0}, fwd},
            {{0.5, -0.5, 0.5, 1.0}, {1.0, 0.0}, fwd},
            {{0.5, 0.5, 0.5, 1.0}, {1.0, 1.0}, fwd},
            {{0.5, 0.5, 0.5, 1.0}, {1.0, 1.0}, fwd},
            {{-0.5, 0.5, 0.5, 1.0}, {0.0, 1.0}, fwd},
            {{-0.5, -0.5, 0.5, 1.0}, {0.0, 0.0}, fwd},

            // Back face
            {{0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}, -fwd},
            {{-0.5, -0.5, -0.5, 1.0}, {1.0, 0.0}, -fwd},
            {{-0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}, -fwd},
            {{-0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}, -fwd},
            {{0.5, 0.5, -0.5, 1.0}, {0.0, 1.0}, -fwd},
            {{0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}, -fwd},

            // Top face
            {{-0.5, 0.5, 0.5, 1.0}, {0.0, 0.0}, top},
            {{0.5, 0.5, 0.5, 1.0}, {1.0, 0.0}, top},
            {{0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}, top},
            {{0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}, top},
            {{-0.5, 0.5, -0.5, 1.0}, {0.0, 1.0}, top},
            {{-0.5, 0.5, 0.5, 1.0}, {0.0, 0.0}, top},

            // Bottom face
            {{-0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}, -top},
            {{0.5, -0.5, -0.5, 1.0}, {1.0, 0.0}, -top},
            {{0.5, -0.5, 0.5, 1.0}, {1.0, 1.0}, -top},
            {{0.5, -0.5, 0.5, 1.0}, {1.0, 1.0}, -top},
            {{-0.5, -0.5, 0.5, 1.0}, {0.0, 1.0}, -top},
            {{-0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}, -top},

            // Left face
            {{-0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}, -right},
            {{-0.5, -0.5, 0.5, 1.0}, {1.0, 0.0}, -right},
            {{-0.5, 0.5, 0.5, 1.0}, {1.0, 1.0}, -right},
            {{-0.5, 0.5, 0.5, 1.0}, {1.0, 1.0}, -right},
            {{-0.5, 0.5, -0.5, 1.0}, {0.0, 1.0}, -right},
            {{-0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}, -right},

            // Right face
            {{0.5, -0.5, 0.5, 1.0}, {0.0, 0.0}, right},
            {{0.5, -0.5, -0.5, 1.0}, {1.0, 0.0}, right},
            {{0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}, right},
            {{0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}, right},
            {{0.5, 0.5, 0.5, 1.0}, {0.0, 1.0}, right},
            {{0.5, -0.5, 0.5, 1.0}, {0.0, 0.0}, right},
        };
        
        const VoxelAtlasEntry& lampEntry = voxelTypeAtlasIndexMap[EVoxelType::Lamp];
        for(auto [coord, color] : chunk->getVoxelLightColorMap()) {
            std::vector<VertexData> voxelVerts = cubeVertTemplate;
            
            float3 localOffset = coord.to_float3() + make_float3(0.5, 0.5, 0.5);
            
            float4 offset = chunk->getPositionAsFloat4() + make_float4(localOffset.x, localOffset.y, localOffset.z, 0.0f);
            for(auto& vd : voxelVerts) {
                // to WS position
                vd.position = matrix4x4_translation(offset.x, offset.y, offset.z) * vd.position;
                vd.atlasIndex = lampEntry.right; // all the same, anyway
                vd.colorScale = color;
            }
            
            chunkVertices.insert(chunkVertices.end(), voxelVerts.begin(), voxelVerts.end());
        }
        
        
    }

    
    ChunkRenderData rd;
    rd.buffer = chunkVertices.size() > 0? metalDevice->newBuffer(chunkVertices.data(), sizeof(VertexData) * chunkVertices.size(), MTL::ResourceStorageModeShared) : 0;
    rd.numVertices = (int) chunkVertices.size();
    
    ChunkRenderData rdt;
    rdt.buffer = transparentVertices.size() > 0? metalDevice->newBuffer(transparentVertices.data(), sizeof(VertexData) * transparentVertices.size(), MTL::ResourceStorageModeShared) : nullptr;
    rdt.numVertices = (int) transparentVertices.size();
    {
        std::lock_guard<std::mutex> guard(cachedChunkRDMutex);
        if(chunkVertices.size() > 0) {
            ChunkRenderer::cachedChunkBuffers.insert({chunkIndex, rd});
        }
        if(transparentVertices.size() > 0) {
            ChunkRenderer::cachedTransparentChunkBuffers.insert({chunkIndex, rdt});
        }
        
    }
}


void MTLEngine::initChunkRenderers() {
    // chunkRenderers is a 2D array, with each dimension == (2 * renderDistance + 1)
    // (imagine renderDistance as a radius, radiating from the chunk the player is currently inside)
    //
    // Currently, render distance only applies to the XZ plane (because world generation only happens in the
    // XZ plane chunk-wise) In the future, Y may be included
    
    chunkRenderers.clear();
    
    // TODO: depends on player's start position
    const int2 startXZ = {0,0};
    
    for(int x = -renderDistance; x <= renderDistance; x++) {
        for(int z = -renderDistance; z <= renderDistance; z++) {
            std::shared_ptr<ChunkRenderer> cr = std::make_shared<ChunkRenderer>();
            
            Int3D key(x, 0, z);
            chunkRenderers.insert({key, cr});
        }
    }
}

void MTLEngine::initCascadingShadowMaps() {
    auto createRenderPipelineState = [this](const char* pipelineName, const char* funcNameVS, const char* funcNameFS)->MTL::RenderPipelineState*{
        MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string(funcNameVS, NS::ASCIIStringEncoding));
        assert(vertexShader);
        
        MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string(funcNameFS, NS::ASCIIStringEncoding));
        assert(fragmentShader);
        
        MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
        assert(renderPipelineDescriptor);
        
        renderPipelineDescriptor->setLabel(NS::String::string(pipelineName, NS::ASCIIStringEncoding));
        renderPipelineDescriptor->setVertexFunction(vertexShader);
        renderPipelineDescriptor->setFragmentFunction(fragmentShader);
        
        renderPipelineDescriptor->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);
        
        NS::Error* error;
        MTL::RenderPipelineState* outRPS = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);
        
        if(outRPS == nullptr) {
            std::cout << "Error render pipeline: " << error->description() << std::endl;
            std::exit(1);
        }
        
        return outRPS;
    };
    
    // Specific mesh-types need a different vertex shader to capture its depth in the shadow pass
    // e.g. voxel meshes already contain WS positions per vertex, but the skeletal meshes need to resolve
    // mesh->model->world wrt its current animation frame.
    //
    // However, once we capture the fragments world-space position, we can capture its depth the same way,
    // so the fragment shader is the same here.
    voxelShadowMapRPS = createRenderPipelineState("Voxel Shadow Map Pipeline",
                                                  "voxelShadowPassVS",
                                                  "shadowPassFS");
    
    skeletalMeshShadowMapRPS = createRenderPipelineState("Skeletal Mesh Shadow Map Pipeline",
                                                         "skeletalMeshShadowPassVS",
                                                         "shadowPassFS");
    
    MTL::DepthStencilDescriptor* depthStencilDescriptor = MTL::DepthStencilDescriptor::alloc()->init();
    depthStencilDescriptor->setDepthCompareFunction(MTL::CompareFunctionLessEqual);
    depthStencilDescriptor->setDepthWriteEnabled(true);
    shadowDepthStencilState = metalDevice->newDepthStencilState(depthStencilDescriptor);
    depthStencilDescriptor->release();
    
    // render-targets
    shadowMapRTs.clear();
    const int numShadowLayers = (int) shadowLayerInfos.size();

    for(int i = 0; i < numShadowLayers; i++) {
        MTL::TextureDescriptor* descriptor = MTL::TextureDescriptor::alloc()->init();
        descriptor->setTextureType(MTL::TextureType2D);
        descriptor->setPixelFormat(MTL::PixelFormatDepth32Float);
        
        descriptor->setWidth(shadowLayerInfos[i].resolution);
        descriptor->setHeight(shadowLayerInfos[i].resolution);
        descriptor->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead);

        MTL::Texture* newTexture = metalDevice->newTexture(descriptor);
        shadowMapRTs.push_back(newTexture);
    }
    
    // descriptors
    int ind = 0;
    shadowMapRPDescriptors.clear();
    for(auto it = std::begin(shadowLayerInfos); it != std::end(shadowLayerInfos); ++it, ind++) {
        
        MTL::RenderPassDescriptor* newDescriptor = MTL::RenderPassDescriptor::alloc()->init();
        MTL::RenderPassDepthAttachmentDescriptor* depthAttachment = newDescriptor->depthAttachment();
        depthAttachment->setTexture(shadowMapRTs[ind]);
        depthAttachment->setLoadAction(MTL::LoadActionClear);
        depthAttachment->setStoreAction(MTL::StoreActionStore);
        depthAttachment->setClearDepth(1.0f);
        
        shadowMapRPDescriptors.push_back(newDescriptor);
    }
}

void MTLEngine::initSSAO() {
    // helper
    auto createTexture = [](MTL::Device* device, int width, int height, MTL::PixelFormat format)->MTL::Texture* {
        MTL::TextureDescriptor* descriptor = MTL::TextureDescriptor::alloc()->init();
        descriptor->setTextureType(MTL::TextureType2D);
        descriptor->setPixelFormat(format);
    
        descriptor->setWidth(width);
        descriptor->setHeight(height);
        descriptor->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead);
        
        MTL::Texture* outTex = device->newTexture(descriptor);
        
        descriptor->release();
        return outTex;
    };
    
    // create samples on hemisphere with normal as +Z
    std::uniform_real_distribution<float> dis(0.f, 1.f);
    std::default_random_engine gen;
    std::vector<float3> ssaoKernel;
    
    // todo: store kernel size in UB
    for(int i = 0; i < 16; i++) {
        
        // dis outputs an alpha value [0,1], a
        // to map between range [-1,1] we use a to get distance between the range by a * (dist)
        // then add the start number, -1.
        // where we get (1 - (-1)) * a + -1 = 2 * a - 1
        float3 sample = make_float3(
                                    dis(gen) * 2 - 1,
                                    dis(gen) * 2 - 1,
                                    dis(gen) // map z to just [0,1] => hemisphere
                                );
        
        sample = normalize(sample); // direction
        
        // this will linearily distribute distance from source,
        // but we want to a bias towards the source
        // sample *= dis(gen); // randomize how far from source position
        
        // notice what happens to scale as i grows
        // - low values of i will stay low for a while because we use scale^2 as the alpha in the lerp
        // - this forms an exponential graph
        float scale = (float) i / 64.f;
        scale = lerp(0.01f, 1.f, scale * scale);
        
        sample *= scale;
        
        ssaoKernel.push_back(sample);
    }
    
    // 4x4 random vecs (we will store these in a texture and just tile over along the SSAO quad)
    std::vector<float4> ssaoNoise;
    int noiseWidth = 4;
    int noiseHeight = 4;
    for(int i = 0; i < noiseWidth * noiseHeight; i++) {
        float4 noise = make_float4(
                                   dis(gen) * 2 - 1,
                                   dis(gen) * 2 - 1,
                                   0.0f,
                                   1.0f
                                   );
        ssaoNoise.push_back(noise);
    }
    
    // store kernel in a uniform buffer
    ssaoKernelUB = metalDevice->newBuffer(ssaoKernel.data(), ssaoKernel.size() * sizeof(float3), MTL::ResourceStorageModeShared);
    
    
    // store noise in a texture2D
    ssaoNoiseTex = createTexture(metalDevice, noiseWidth, noiseHeight, MTL::PixelFormatRGBA16Float);
    MTL::Region region = MTL::Region(0, 0, 0, noiseWidth, noiseHeight, 1);
    // 4 32-bit floats per cell, and texture has 4 cells per row.
    NS::UInteger bytesPerRow = (4 * 32 / 8) * noiseWidth;

    ssaoNoiseTex->replaceRegion(region, 0, ssaoNoise.data(), bytesPerRow);
    
    const int w = metalLayer.drawableSize.width;
    const int h = metalLayer.drawableSize.height;
    
    
    
    // render-target for SSAO, say R1
    ssaoRT = createTexture(metalDevice, w, h, MTL::PixelFormatR16Float);
    
    // render-target to blur R1 -> then used in light pass
    ssaoBlurRT = createTexture(metalDevice, w, h, MTL::PixelFormatR16Float);
    
    
    //
    // render pipeline initialization
    //
    {
        MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("ssaoPassVS", NS::ASCIIStringEncoding));
        assert(vertexShader);
        MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string("ssaoPassFS", NS::ASCIIStringEncoding));
        assert(fragmentShader);
        
        MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
        assert(renderPipelineDescriptor);
        renderPipelineDescriptor->setLabel(NS::String::string("SSAO Pass Pipeline", NS::ASCIIStringEncoding));
        renderPipelineDescriptor->setVertexFunction(vertexShader);
        renderPipelineDescriptor->setFragmentFunction(fragmentShader);
        
        renderPipelineDescriptor->colorAttachments()->object(0)->setPixelFormat(MTL::PixelFormatR16Float);
        
        NS::Error* error;
        ssaoRenderPipeline = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);
        
        if(ssaoRenderPipeline == nullptr) {
            std::cout << "Error render pipeline: " << error->description() << std::endl;
            std::exit(1);
        }

        renderPipelineDescriptor->release();
        vertexShader->release();
        fragmentShader->release();
    }
    {
        MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("ssaoBlurPassVS", NS::ASCIIStringEncoding));
        assert(vertexShader);
        MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string("ssaoBlurPassFS", NS::ASCIIStringEncoding));
        assert(fragmentShader);
        
        MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
        assert(renderPipelineDescriptor);
        renderPipelineDescriptor->setLabel(NS::String::string("SSAO Blur Pass Pipeline", NS::ASCIIStringEncoding));
        renderPipelineDescriptor->setVertexFunction(vertexShader);
        renderPipelineDescriptor->setFragmentFunction(fragmentShader);
        
        renderPipelineDescriptor->colorAttachments()->object(0)->setPixelFormat(MTL::PixelFormatR16Float);
        
        NS::Error* error;
        ssaoBlurRenderPipeline = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);
        
        if(ssaoBlurRenderPipeline == nullptr) {
            std::cout << "Error render pipeline: " << error->description() << std::endl;
            std::exit(1);
        }

        renderPipelineDescriptor->release();
        vertexShader->release();
        fragmentShader->release();
    }
    
    //
    // render pass descriptor (2 for ssao and ssao blur)
    //
    {
        ssaoRenderPassDescriptor = MTL::RenderPassDescriptor::alloc()->init();
        
        MTL::RenderPassColorAttachmentDescriptor* colorAttachment = ssaoRenderPassDescriptor->colorAttachments()->object(0);
        colorAttachment->setTexture(ssaoRT);
        colorAttachment->setLoadAction(MTL::LoadActionClear);
        colorAttachment->setClearColor(MTL::ClearColor(0.f, 0.f, 0.f, 1.0));
        colorAttachment->setStoreAction(MTL::StoreActionStore);
        
    }
    
    {
        ssaoBlurRenderPassDescriptor = MTL::RenderPassDescriptor::alloc()->init();
        
        MTL::RenderPassColorAttachmentDescriptor* colorAttachment = ssaoBlurRenderPassDescriptor->colorAttachments()->object(0);
        colorAttachment->setTexture(ssaoBlurRT);
        colorAttachment->setLoadAction(MTL::LoadActionClear);
        colorAttachment->setClearColor(MTL::ClearColor(0.f, 0.f, 0.f, 1.0));
        colorAttachment->setStoreAction(MTL::StoreActionStore);
    }
}

void MTLEngine::initSkybox() {
    MTL::TextureDescriptor* descriptor = MTL::TextureDescriptor::alloc()->init();
    descriptor->setTextureType(MTL::TextureTypeCube);
    descriptor->setPixelFormat(MTL::PixelFormatRGBA8Unorm);
    
    std::array<std::string, 6> filePaths = {
        "assets/HDRI/Sky/px.png",
        "assets/HDRI/Sky/nx.png",
        
        
        "assets/HDRI/Sky/ny.png",
        "assets/HDRI/Sky/py.png",
        
        "assets/HDRI/Sky/pz.png",
        "assets/HDRI/Sky/nz.png",
    };
    
    {
        int width, height, channels;
        unsigned char* image = stbi_load(filePaths[0].c_str(), &width, &height, &channels, STBI_rgb);
        descriptor->setWidth(width);
        descriptor->setHeight(height);
    }
    descriptor->setUsage(MTL::TextureUsageShaderRead);

    skyboxTex = metalDevice->newTexture(descriptor);
    
    int imageWidth=0, imageHeight=0;
    NS::UInteger bytesPerRow=0, bytesPerImage=0;

    for(int i = 0; i < 6; i++) {
        std::string fp = filePaths[i];
        
        stbi_set_flip_vertically_on_load(true);
        int width, height, channels;
        unsigned char* image = stbi_load(fp.c_str(), &width, &height, &channels, STBI_rgb);
        
        std::vector<unsigned char> tmp;
        tmp.reserve(width*height);
        for(int j=0; j<width*height*channels;j+=channels){
            tmp.push_back(image[j]);
            tmp.push_back(image[j + 1]);
            tmp.push_back(image[j + 2]);
            tmp.push_back((char) 0xFF);
        }
        
        // 3 channels (rgb), 8 bit float each
        
        if(i == 0) {
            imageWidth = width;
            imageHeight = height;
            bytesPerRow = 4 * imageWidth;
            bytesPerImage = 4 * imageWidth * imageHeight;
        }
        
        MTL::Region region = MTL::Region(0, 0, imageWidth, imageHeight);
        skyboxTex->replaceRegion(region, 0, i, tmp.data(), bytesPerRow, bytesPerImage);
    }
    
    // Cube for use in a right-handed coordinate system with triangle faces
    // specified with a Counter-Clockwise winding order.
    
    float4 frontNormal = {0.0, 0.0, -1.0, 1.0};
    float4 rightNormal = {-1.0, 0.0, 0.0, 1.0};
    float4 topNormal = {0.0, -1.0, 0.0, 1.0};
    
    SkyBoxCubeVertexData cubeVertices[] = {
        
        // Front face
        {{-0.5, -0.5, 0.5, 1.0}, frontNormal},
        {{0.5, -0.5, 0.5, 1.0}, frontNormal},
        {{0.5, 0.5, 0.5, 1.0}, frontNormal},
        {{0.5, 0.5, 0.5, 1.0}, frontNormal},
        {{-0.5, 0.5, 0.5, 1.0}, frontNormal},
        {{-0.5, -0.5, 0.5, 1.0}, frontNormal},

        // Back face
        {{0.5, -0.5, -0.5, 1.0}, -frontNormal},
        {{-0.5, -0.5, -0.5, 1.0}, -frontNormal},
        {{-0.5, 0.5, -0.5, 1.0}, -frontNormal},
        {{-0.5, 0.5, -0.5, 1.0}, -frontNormal},
        {{0.5, 0.5, -0.5, 1.0}, -frontNormal},
        {{0.5, -0.5, -0.5, 1.0}, -frontNormal},

        // Top face
        {{-0.5, 0.5, 0.5, 1.0}, topNormal},
        {{0.5, 0.5, 0.5, 1.0}, topNormal},
        {{0.5, 0.5, -0.5, 1.0}, topNormal},
        {{0.5, 0.5, -0.5, 1.0}, topNormal},
        {{-0.5, 0.5, -0.5, 1.0}, topNormal},
        {{-0.5, 0.5, 0.5, 1.0}, topNormal},

        // Bottom face
        {{-0.5, -0.5, -0.5, 1.0}, -topNormal},
        {{0.5, -0.5, -0.5, 1.0}, -topNormal},
        {{0.5, -0.5, 0.5, 1.0}, -topNormal},
        {{0.5, -0.5, 0.5, 1.0}, -topNormal},
        {{-0.5, -0.5, 0.5, 1.0}, -topNormal},
        {{-0.5, -0.5, -0.5, 1.0}, -topNormal},

        // Left face
        {{-0.5, -0.5, -0.5, 1.0}, -rightNormal},
        {{-0.5, -0.5, 0.5, 1.0}, -rightNormal},
        {{-0.5, 0.5, 0.5, 1.0}, -rightNormal},
        {{-0.5, 0.5, 0.5, 1.0}, -rightNormal},
        {{-0.5, 0.5, -0.5, 1.0}, -rightNormal},
        {{-0.5, -0.5, -0.5, 1.0}, -rightNormal},

        // Right face
        {{0.5, -0.5, 0.5, 1.0}, rightNormal},
        {{0.5, -0.5, -0.5, 1.0}, rightNormal},
        {{0.5, 0.5, -0.5, 1.0}, rightNormal},
        {{0.5, 0.5, -0.5, 1.0}, rightNormal},
        {{0.5, 0.5, 0.5, 1.0}, rightNormal},
        {{0.5, -0.5, 0.5, 1.0}, rightNormal},
    };
    
    skyboxCubeVB = metalDevice->newBuffer(&cubeVertices, sizeof(cubeVertices), MTL::ResourceStorageModeShared);
    
    // render pipeline
    {
        MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("skyboxVS", NS::ASCIIStringEncoding));
        assert(vertexShader);
        MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string("skyboxFS", NS::ASCIIStringEncoding));
        assert(fragmentShader);
        
        MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
        assert(renderPipelineDescriptor);
        renderPipelineDescriptor->setLabel(NS::String::string("Skybox Pipeline", NS::ASCIIStringEncoding));
        renderPipelineDescriptor->setVertexFunction(vertexShader);
        renderPipelineDescriptor->setFragmentFunction(fragmentShader);
        
        renderPipelineDescriptor->colorAttachments()->object(0)->setPixelFormat(MTL::PixelFormatRGBA32Float);
        
        NS::Error* error;
        skyboxRPS = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);
        
        if(skyboxRPS == nullptr) {
            std::cout << "Error render pipeline: " << error->description() << std::endl;
            std::exit(1);
        }

        renderPipelineDescriptor->release();
        vertexShader->release();
        fragmentShader->release();
    }
    {
        skyboxRPD = MTL::RenderPassDescriptor::alloc()->init();
        
        MTL::RenderPassColorAttachmentDescriptor* colorAttachment = skyboxRPD->colorAttachments()->object(0);
        colorAttachment->setTexture(gPositionRT);
        colorAttachment->setLoadAction(MTL::LoadActionClear);
        colorAttachment->setClearColor(MTL::ClearColor(0.f, 0.f, 0.f, 1.0));
        colorAttachment->setStoreAction(MTL::StoreActionStore);
    }
    
    //
    skyboxMVPUB = metalDevice->newBuffer(sizeof(TransformationData), MTL::ResourceStorageModeShared);
}


void MTLEngine::initLightVolumePass() {
    // render pipeline
    {
        MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("lightVolumePassVS", NS::ASCIIStringEncoding));
        assert(vertexShader);
        MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string("lightingPassFS", NS::ASCIIStringEncoding));
        assert(fragmentShader);
        
        MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
        assert(renderPipelineDescriptor);
        renderPipelineDescriptor->setLabel(NS::String::string("Light Volume Pipeline", NS::ASCIIStringEncoding));
        renderPipelineDescriptor->setVertexFunction(vertexShader);
        renderPipelineDescriptor->setFragmentFunction(fragmentShader);
        
        renderPipelineDescriptor->colorAttachments()->object(0)->setPixelFormat(MTL::PixelFormatRGBA8Unorm);
        
        
        MTL::RenderPipelineColorAttachmentDescriptor* colorAttachment = renderPipelineDescriptor->colorAttachments()->object(0);
        
        colorAttachment->setBlendingEnabled(true);
        colorAttachment->setRgbBlendOperation(MTL::BlendOperationAdd);
        //colorAttachment->setAlphaBlendOperation(MTL::BlendOperationAdd);
        
        // TODO:
        // directional light + point light => 1 pipeline A
        // emissive + bloom (not affected by light) => 1 pipeline (just emissive) B
        // render B over A => last pipeline pass
        //
        // actually the emissive pipeline can blend with A,
        // with destination factor == 0 and source factor == 1
        //
        // right now we have inaccurate emissive colors
        colorAttachment->setDestinationRGBBlendFactor(MTL::BlendFactorOne);
        colorAttachment->setSourceRGBBlendFactor(MTL::BlendFactorSourceColor);
        
        
        NS::Error* error;
        lightVolumeRPS = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);
        
        if(lightVolumeRPS == nullptr) {
            std::cout << "Error render pipeline: " << error->description() << std::endl;
            std::exit(1);
        }

        renderPipelineDescriptor->release();
        vertexShader->release();
        fragmentShader->release();
    }
    {
        lightVolumeRPD = MTL::RenderPassDescriptor::alloc()->init();
        
        MTL::RenderPassColorAttachmentDescriptor* colorAttachment = lightVolumeRPD->colorAttachments()->object(0);
        
        colorAttachment->setTexture(lightPassRT);
        colorAttachment->setLoadAction(MTL::LoadActionLoad);
        colorAttachment->setClearColor(MTL::ClearColor(0.f, 0.f, 0.f, 1.0));
        colorAttachment->setStoreAction(MTL::StoreActionStore);
    }
    
    int maxPointLights = 100;
    LightVolumeData ld;
    pointLights.resize(maxPointLights, ld);
    curPointLightIndex = 0;
    lightVolumeInstanceUB = metalDevice->newBuffer(maxPointLights * sizeof(LightVolumeData), MTL::ResourceStorageModeShared);
}

void MTLEngine::initGaussianBlurPass() {
    // helper
    auto createTexture = [this]()->MTL::Texture* {
        MTL::TextureDescriptor* descriptor = MTL::TextureDescriptor::alloc()->init();
        descriptor->setTextureType(MTL::TextureType2D);
        descriptor->setPixelFormat(MTL::PixelFormatRGBA16Float); // must match gEmissionRT
    
        descriptor->setWidth(metalLayer.drawableSize.width / 8);
        descriptor->setHeight(metalLayer.drawableSize.height / 8);

        descriptor->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead);
        
        MTL::Texture* outTex = metalDevice->newTexture(descriptor);
        
        descriptor->release();
        return outTex;
    };
    
    // ping-pong render targets
    gaussianBlurRT0 = createTexture();
    gaussianBlurRT1 = createTexture();
    
    // render pipeline
    {
        MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("gaussianBlurVS", NS::ASCIIStringEncoding));
        assert(vertexShader);
        MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string("gaussianBlurHorizontalFS", NS::ASCIIStringEncoding));
        assert(fragmentShader);
        
        MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
        assert(renderPipelineDescriptor);
        renderPipelineDescriptor->setLabel(NS::String::string("Gaussian Blur (Horizontal) Pipeline", NS::ASCIIStringEncoding));
        renderPipelineDescriptor->setVertexFunction(vertexShader);
        renderPipelineDescriptor->setFragmentFunction(fragmentShader);
        
        MTL::RenderPipelineColorAttachmentDescriptor* colorAttachment = renderPipelineDescriptor->colorAttachments()->object(0);
        colorAttachment->setPixelFormat(MTL::PixelFormatRGBA16Float); // must match format of gEmissionRT
        
        //colorAttachment->setBlendingEnabled(true);
        colorAttachment->setRgbBlendOperation(MTL::BlendOperationAdd);
        //colorAttachment->setAlphaBlendOperation(MTL::BlendOperationAdd);
        
        colorAttachment->setDestinationRGBBlendFactor(MTL::BlendFactorOne);
        colorAttachment->setSourceRGBBlendFactor(MTL::BlendFactorSourceColor);
        
        NS::Error* error;
        gaussianBlurRPSHorizontal = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);
        
        if(gaussianBlurRPSHorizontal == nullptr) {
            std::cout << "Error render pipeline: " << error->description() << std::endl;
            std::exit(1);
        }

        renderPipelineDescriptor->release();
        vertexShader->release();
        fragmentShader->release();
    }
    {
        MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("gaussianBlurVS", NS::ASCIIStringEncoding));
        assert(vertexShader);
        MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string("gaussianBlurVerticalFS", NS::ASCIIStringEncoding));
        assert(fragmentShader);
        
        MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
        assert(renderPipelineDescriptor);
        renderPipelineDescriptor->setLabel(NS::String::string("Gaussian Blur (Vertical) Pipeline", NS::ASCIIStringEncoding));
        renderPipelineDescriptor->setVertexFunction(vertexShader);
        renderPipelineDescriptor->setFragmentFunction(fragmentShader);
        
        MTL::RenderPipelineColorAttachmentDescriptor* colorAttachment = renderPipelineDescriptor->colorAttachments()->object(0);
        colorAttachment->setPixelFormat(MTL::PixelFormatRGBA16Float); // must match format of gEmissionRT
        
        //colorAttachment->setBlendingEnabled(true);
        colorAttachment->setRgbBlendOperation(MTL::BlendOperationAdd);
        //colorAttachment->setAlphaBlendOperation(MTL::BlendOperationAdd);
        
        colorAttachment->setDestinationRGBBlendFactor(MTL::BlendFactorOne);
        colorAttachment->setSourceRGBBlendFactor(MTL::BlendFactorSourceColor);
        
        NS::Error* error;
        gaussianBlurRPSVertical = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);
        
        if(gaussianBlurRPSVertical == nullptr) {
            std::cout << "Error render pipeline: " << error->description() << std::endl;
            std::exit(1);
        }

        renderPipelineDescriptor->release();
        vertexShader->release();
        fragmentShader->release();
    }
    
    
    
    // ping-pong passes
    {
        gaussianBlurRPD0 = MTL::RenderPassDescriptor::alloc()->init();
        
        MTL::RenderPassColorAttachmentDescriptor* colorAttachment = gaussianBlurRPD0->colorAttachments()->object(0);
        
        colorAttachment->setTexture(gaussianBlurRT0);
        colorAttachment->setLoadAction(MTL::LoadActionClear);
        colorAttachment->setClearColor(MTL::ClearColor(0.f, 0.f, 0.f, 1.0));
        colorAttachment->setStoreAction(MTL::StoreActionStore);
    }
    {
        gaussianBlurRPD1 = MTL::RenderPassDescriptor::alloc()->init();
        
        MTL::RenderPassColorAttachmentDescriptor* colorAttachment = gaussianBlurRPD1->colorAttachments()->object(0);
        
        colorAttachment->setTexture(gaussianBlurRT1);
        colorAttachment->setLoadAction(MTL::LoadActionClear);
        colorAttachment->setClearColor(MTL::ClearColor(0.f, 0.f, 0.f, 1.0));
        colorAttachment->setStoreAction(MTL::StoreActionStore);
    }
    
    // buffers
    gaussianBlurUB = metalDevice->newBuffer(sizeof(GaussianBlurState), MTL::ResourceStorageModeShared);
}

void MTLEngine::initPostProcessPass() {
    // render pipeline
    {
        MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("postProcessVS", NS::ASCIIStringEncoding));
        assert(vertexShader);
        MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string("postProcessFS", NS::ASCIIStringEncoding));
        assert(fragmentShader);
        
        MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
        assert(renderPipelineDescriptor);
        renderPipelineDescriptor->setLabel(NS::String::string("Post Process Pipeline", NS::ASCIIStringEncoding));
        renderPipelineDescriptor->setVertexFunction(vertexShader);
        renderPipelineDescriptor->setFragmentFunction(fragmentShader);
        
        MTL::RenderPipelineColorAttachmentDescriptor* colorAttachment = renderPipelineDescriptor->colorAttachments()->object(0);
        colorAttachment->setPixelFormat((MTL::PixelFormat) metalLayer.pixelFormat);
        
        NS::Error* error;
        postProcessRPS = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);
        
        if(postProcessRPS == nullptr) {
            std::cout << "Error render pipeline: " << error->description() << std::endl;
            std::exit(1);
        }

        renderPipelineDescriptor->release();
        vertexShader->release();
        fragmentShader->release();
    }
    {
        postProcessRPD = MTL::RenderPassDescriptor::alloc()->init();
        
        MTL::RenderPassColorAttachmentDescriptor* colorAttachment = postProcessRPD->colorAttachments()->object(0);

        colorAttachment->setTexture(metalDrawable->texture());
        colorAttachment->setStoreAction(MTL::StoreActionStore);
        colorAttachment->setLoadAction(MTL::LoadActionClear);
        colorAttachment->setClearColor(MTL::ClearColor(0.f, 0.f, 0.f, 1.0));
    }
}

void MTLEngine::initMeshRenderPass() {
    {
        MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("skeletalMeshPassVS", NS::ASCIIStringEncoding));
        assert(vertexShader);
        MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string("meshPassFS", NS::ASCIIStringEncoding));
        assert(fragmentShader);
        
        MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
        assert(renderPipelineDescriptor);
        renderPipelineDescriptor->setLabel(NS::String::string("Mesh Rendering Pipeline", NS::ASCIIStringEncoding));
        renderPipelineDescriptor->setVertexFunction(vertexShader);
        renderPipelineDescriptor->setFragmentFunction(fragmentShader);
        
        // outputs to G-Buffer
        renderPipelineDescriptor->colorAttachments()->object(0)->setPixelFormat(MTL::PixelFormatRGBA32Float); // position
        renderPipelineDescriptor->colorAttachments()->object(1)->setPixelFormat(MTL::PixelFormatRGBA32Float); // normal
        renderPipelineDescriptor->colorAttachments()->object(2)->setPixelFormat(MTL::PixelFormatRGBA32Float); // color
        renderPipelineDescriptor->colorAttachments()->object(3)->setPixelFormat(MTL::PixelFormatRGBA32Float); // emission
        
        // renderPipelineDescriptor->setSampleCount(sampleCount);
        renderPipelineDescriptor->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);
        
        MTL::RenderPipelineColorAttachmentDescriptor* colorAttachment = renderPipelineDescriptor->colorAttachments()->object(2);
        
        // alpha-blending
        colorAttachment->setBlendingEnabled(true);
        colorAttachment->setRgbBlendOperation(MTL::BlendOperationAdd);
        colorAttachment->setAlphaBlendOperation(MTL::BlendOperationAdd);
        colorAttachment->setDestinationRGBBlendFactor(MTL::BlendFactorOneMinusSourceAlpha);
        colorAttachment->setSourceRGBBlendFactor(MTL::BlendFactorSourceAlpha);
        
        NS::Error* error;
        meshRPS = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);
        
        if(meshRPS == nullptr) {
            std::cout << "Error render pipeline: " << error->description() << " " << error->code() << std::endl;
            NSLog(@"Whatever: %@", error);
            std::exit(1);
        }
        
        MTL::DepthStencilDescriptor* depthStencilDescriptor = MTL::DepthStencilDescriptor::alloc()->init();
        depthStencilDescriptor->setDepthCompareFunction(MTL::CompareFunctionLessEqual);
        depthStencilDescriptor->setDepthWriteEnabled(true);
        depthStencilState = metalDevice->newDepthStencilState(depthStencilDescriptor);
        
        renderPipelineDescriptor->release();
        vertexShader->release();
        fragmentShader->release();
    }
    {
        meshRPD = MTL::RenderPassDescriptor::alloc()->init();
            
        struct Local {
            static void setupColorAttachment(MTL::RenderPassDescriptor* rpdescriptor, NS::UInteger index, MTL::Texture* texture, MTL::LoadAction loadAction) {
                MTL::RenderPassColorAttachmentDescriptor* colorAttachment = rpdescriptor->colorAttachments()->object(index);
                colorAttachment->setTexture(texture);
                
                colorAttachment->setLoadAction(loadAction);
                colorAttachment->setClearColor(MTL::ClearColor(0.f, 0.f, 0.f, 1.0));
                colorAttachment->setStoreAction(MTL::StoreActionStore);
            }
        };
            
        // Everything should not clear, we render meshes after the Voxel Mesh Pass
        Local::setupColorAttachment(meshRPD, 0, gPositionRT, MTL::LoadActionLoad);
        Local::setupColorAttachment(meshRPD, 1, gNormalRT, MTL::LoadActionLoad);
        Local::setupColorAttachment(meshRPD, 2, gAlbedoSpecRT, MTL::LoadActionLoad);
        Local::setupColorAttachment(meshRPD, 3, gEmissionRT, MTL::LoadActionLoad);
            
        // don't clear depth - voxels are rendered BEFORE meshes
        MTL::RenderPassDepthAttachmentDescriptor* depthAttachment = meshRPD->depthAttachment();
        depthAttachment->setTexture(depthRenderTarget);
        depthAttachment->setLoadAction(MTL::LoadActionLoad);
        depthAttachment->setStoreAction(MTL::StoreActionStore);
        depthAttachment->setClearDepth(1.0f);
    }
}

void MTLEngine::initLinePass() {
    {
        MTL::TextureDescriptor* descriptor = MTL::TextureDescriptor::alloc()->init();
        descriptor->setTextureType(MTL::TextureType2D);
        descriptor->setPixelFormat(MTL::PixelFormatDepth32Float);
        
        descriptor->setWidth(metalLayer.drawableSize.width);
        descriptor->setHeight(metalLayer.drawableSize.height);
        descriptor->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead);

        debugDepthRT = metalDevice->newTexture(descriptor);
    }
    {
        MTL::TextureDescriptor* descriptor = MTL::TextureDescriptor::alloc()->init();
        descriptor->setTextureType(MTL::TextureType2D);
        descriptor->setPixelFormat(MTL::PixelFormatRGBA8Unorm);
        
        descriptor->setWidth(metalLayer.drawableSize.width);
        descriptor->setHeight(metalLayer.drawableSize.height);
        descriptor->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead);

        debugRT = metalDevice->newTexture(descriptor);
    }
    
    // line pipeline
    MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("lineVS", NS::ASCIIStringEncoding));
    assert(vertexShader);
    MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string("lineFS", NS::ASCIIStringEncoding));
    assert(fragmentShader);

    
    MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
    assert(renderPipelineDescriptor);
    renderPipelineDescriptor->setLabel(NS::String::string("Debug Lines Pipeline", NS::ASCIIStringEncoding));
    renderPipelineDescriptor->setVertexFunction(vertexShader);
    renderPipelineDescriptor->setFragmentFunction(fragmentShader);
    
    renderPipelineDescriptor->colorAttachments()->object(0)->setPixelFormat(MTL::PixelFormatRGBA8Unorm);
    
    renderPipelineDescriptor->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);
    
    NS::Error* error;
    linePassPipeline = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);
    
    if(linePassPipeline == nullptr) {
        std::cout << "Error render pipeline: " << error->description() << std::endl;
        std::exit(1);
    }
    
    MTL::DepthStencilDescriptor* depthStencilDescriptor = MTL::DepthStencilDescriptor::alloc()->init();
    depthStencilDescriptor->setDepthCompareFunction(MTL::CompareFunctionLessEqual);
    depthStencilDescriptor->setDepthWriteEnabled(true);
    lineDepthStencilState = metalDevice->newDepthStencilState(depthStencilDescriptor);
    
    renderPipelineDescriptor->release();
    vertexShader->release();
    fragmentShader->release();
    
    // line descriptor
    linePassDescriptor = MTL::RenderPassDescriptor::alloc()->init();
    
    MTL::RenderPassColorAttachmentDescriptor* colorAttachment = linePassDescriptor->colorAttachments()->object(0);
    colorAttachment->setTexture(debugRT);
    colorAttachment->setLoadAction(MTL::LoadActionClear);
    colorAttachment->setClearColor(MTL::ClearColor(0.f, 0.f, 0.f, 1.0));
    colorAttachment->setStoreAction(MTL::StoreActionStore);
    
    MTL::RenderPassDepthAttachmentDescriptor* depthAttachment = linePassDescriptor->depthAttachment();
    depthAttachment->setTexture(debugDepthRT);
    depthAttachment->setLoadAction(MTL::LoadActionClear);
    depthAttachment->setStoreAction(MTL::StoreActionStore);
    depthAttachment->setClearDepth(1.0f);
    
    //
    LineVertexData squareVertices[] {
            {{-0.5f, -0.5f,  0.0f,  1.0f}},
            {{-0.5f,  0.5f,  0.0f,  1.0f}},
            {{ 0.5f,  0.5f,  0.0f,  1.0f}},
            {{ 0.5f, -0.5f,  0.0f,  1.0f}}
    };
    
    uint32_t squareIndices[] {
        0, 2, 1,
        0, 2, 3
    };
    
    lineSquareVB = metalDevice->newBuffer(&squareVertices, sizeof(squareVertices), MTL::ResourceStorageModeShared);
    lineSquareIB = metalDevice->newBuffer(&squareIndices, sizeof(uint32_t) * 6, MTL::ResourceStorageModeShared);
    
    //
    lines.resize(50);
    
    lineDataUBSize = 50;
    lineDataUB = metalDevice->newBuffer(lineDataUBSize * sizeof(LineData), MTL::ResourceStorageModeShared);
}

void MTLEngine::initPlayerMesh() {
    playerNodeManager = AssimpNodeManager("assets/Meshes/Steve/Steve.fbx");
    animator = Animator(&playerNodeManager);
    
    const std::vector<MeshUnit>& meshUnits = playerNodeManager.getMeshUnits();
    const std::vector<AssimpNode>& nodes = playerNodeManager.getNodes();
    const std::vector<Bone>& bones = playerNodeManager.getBones();
    
    for(const auto& mu : meshUnits) {
        assert(mu.positions.size() == mu.normals.size());
        assert(mu.positions.size() == mu.uvs.size());
        
        for(int i = 0; i < (int) mu.positions.size(); i++) {
            SkeletalMeshVertexData v;
            v.position = mu.positions[i];
            v.normal = mu.normals[i];
            v.uv = mu.uvs[i];
            v.transformationIndex = mu.node;
            v.debugColor = make_float3(0);
            int boneWeightsAdded = 0;
            
            // vidToBoneWeights is local wrt the MeshUnit
            if(mu.vidToBoneWeights.contains(i)) {
                auto boneWeights = mu.vidToBoneWeights.at(i);
                for(; boneWeightsAdded < (int) boneWeights.size(); boneWeightsAdded++) {
                    if(boneWeightsAdded >= 4) { // max bone weights per vertex // todo: should be a const... or actually shader defines this
                        break;
                    }
                    
                    const int bwIndex = boneWeightsAdded;
                    v.boneWeights[bwIndex].weight = boneWeights[bwIndex].weight;
                    v.boneWeights[bwIndex].boneIndex = boneWeights[bwIndex].boneId;
                    
                    int bid = boneWeights[bwIndex].boneId;
                    float w = boneWeights[bwIndex].weight;
                    
                    if(bid == playerNodeManager.getBoneId("Bone.014")) {
                        v.debugColor += make_float3(0, w, 0); // top leg
                    }
                    
                    if(bid == playerNodeManager.getBoneId("Bone.015")) {
                        v.debugColor += make_float3(w, 0, 0); // top leg
                    }
                    
                    if(bid == playerNodeManager.getBoneId("Bone.016")) {
                        v.debugColor += make_float3(0, 0, w); // bottom leg
                    }
                    
                    assert(v.boneWeights[bwIndex].boneIndex < bones.size());
                }
            }
            
            // initialize weight to zero for the slots not needed
            for(; boneWeightsAdded < 4; boneWeightsAdded++) {
                v.boneWeights[boneWeightsAdded].weight = 0.0f;
                v.boneWeights[boneWeightsAdded].boneIndex = 0;
            }
            
            playerMeshVertices.push_back(v);
        }
        
        
        std::cout << nodes[mu.node].name << " using transformation: " << mu.node << std::endl;
        
    }
    
    playerMeshIndices = playerNodeManager.createSingleBufferIndices();
    playerMeshTransformations = playerNodeManager.createNodeModelTransforms();
    
    animTransformations.resize(bones.size());
    
    for(int i = 0; i < nodes.size(); i++) {
        auto node = nodes[i];
        float4x4 mt = playerNodeManager.calculateModelTransform(i);
        
        int boneId = playerNodeManager.getBoneId(node.name);
        
        if(boneId >= 0) {
            animTransformations[boneId] = mt * bones[boneId].offsetMat; // float4x4(1); // mt * bones[boneId].offsetMat;
        }
    }
    
    /*
    playerMeshVertices.clear();
    playerMeshIndices.clear();
    processAssimpAnimations(scene->mRootNode, scene);
    processAssimpNode(scene->mRootNode, scene);
    
    */
    
    
    // load mesh data into buffers
    playerMeshVB = metalDevice->newBuffer(playerMeshVertices.data(), playerMeshVertices.size() * sizeof(SkeletalMeshVertexData), MTL::ResourceStorageModeShared);
    playerMeshIB = metalDevice->newBuffer(playerMeshIndices.data(), playerMeshIndices.size() * sizeof(uint32_t), MTL::ResourceStorageModeShared);
    playerMeshTexture = new Texture("assets/Meshes/Steve/diffuse.png", metalDevice, STBI_rgb);
    playerMeshTransformationUB = metalDevice->newBuffer(playerMeshTransformations.data(), playerMeshTransformations.size() * sizeof(float4x4), MTL::ResourceStorageModeShared);
    
    animTransformationsUB = metalDevice->newBuffer(animTransformations.data(), animTransformations.size() * sizeof(float4x4), MTL::ResourceStorageModeShared);
    
    ObjectData od { matrix4x4_identity() };
    playerModelMat = matrix4x4_identity();
    playerObjectUB = metalDevice->newBuffer(&od, sizeof(od), MTL::ResourceStorageModeShared);
}

void MTLEngine::processAssimpAnimations(const aiNode* node, const aiScene* scene) {
    if(!scene->HasAnimations()) {
        return;
    }
    
    /*
    for(int i = 0; i < scene->mNumAnimations; i++) {
        auto anim = scene->mAnimations[i];
        
        
        for(int j = 0; j < anim->mNumChannels; j++) {
            const auto ch = anim->mChannels[j];
            
        }
    }
    */
    
}

void MTLEngine::processAssimpNode(const aiNode* node, const aiScene* scene) {
    
    if(node->mNumMeshes > 0) {
        // process all the node's meshes (if any)
        aiMatrix4x4 nt = node->mTransformation;
        
        float unitScale = 0.6f;
        float3 translate { nt.a4, nt.b4, nt.c4 };
        translate *= unitScale;
        float3 scale(unitScale);
        
        float4x4 localModel = matrix4x4_translation(translate) * matrix4x4_scale(scale);
        
        /*
        float4x4 localModel = (matrix_float4x4) { {
            {nt.a1, nt.a2, nt.a3, nt.a4},
            {nt.b1, nt.b2, nt.b3, nt.b4},
            {nt.c1, nt.c2, nt.c3, nt.c4},
            {nt.d1, nt.d2, nt.d3, nt.d4}
        } };
        */
        // NOTE:
        /*
        float4x4 localModel = (matrix_float4x4) { {
            {nt.a1, nt.b1, nt.c1, nt.d1},
            {nt.a2, nt.b2, nt.c2, nt.d2},
            {nt.a3, nt.b3, nt.c3, nt.d3},
            {nt.a4, nt.b4, nt.c4, nt.d4}
        } };
        */
        
        playerMeshTransformations.push_back(localModel);
    }
    
    for(unsigned int i = 0; i < node->mNumMeshes; i++)
    {
        aiMesh *mesh = scene->mMeshes[node->mMeshes[i]];
        
        processAssimpMesh(mesh, scene);
    }
    
    //std::cout << "Finished." << std::endl;
    
    // then do the same for each of its children
    for(unsigned int i = 0; i < node->mNumChildren; i++)
    {
        processAssimpNode(node->mChildren[i], scene);
    }
}

void MTLEngine::processAssimpMesh(const aiMesh* mesh, const aiScene* scene) {
    /*
    std::cout << fmt::format("Processing mesh: {} nVerts: {} nFaces: {} transform: {}",
                             mesh->mName.C_Str(), mesh->mNumVertices, mesh->mNumFaces,
                             playerMeshTransformations.size() - 1) << std::endl;
    
    
    for(unsigned int i =0;i < mesh->mNumBones; i++) {
        auto b = mesh->mBones[i];
        std::cout << fmt::format("Bone: {} {}", std::string(b->mName.C_Str()), b->mNumWeights) << std::endl;
        std::cout << fmt::format("{} {} {}", b->mOffsetMatrix.a1, b->mOffsetMatrix.a2, b->mOffsetMatrix.a3) << std::endl;
    }
    */
    
    int indexOffset = (int) playerMeshVertices.size();
    std::cout << "og indexoffset: " << indexOffset << std::endl;
    
    for(unsigned int i = 0; i < mesh->mNumVertices; i++)
    {
        MeshVertexData vd;
        
        float4 pos {
            mesh->mVertices[i].x,
            mesh->mVertices[i].z,
            mesh->mVertices[i].y,
            1.0f
        };
        
        float3 norm {
            mesh->mNormals[i].x,
            mesh->mNormals[i].z,
            mesh->mNormals[i].y
        };
        
        float2 uv {
            mesh->mTextureCoords[0][i].x,
            mesh->mTextureCoords[0][i].y
        };
        
        int transformationIndex = (int) playerMeshTransformations.size() - 1;
        
        vd.position = pos;
        vd.normal = norm;
        vd.uv = uv;
        vd.transformationIndex = transformationIndex;
        
        // playerMeshVertices.push_back(vd);
    }
    
    for(unsigned int i = 0; i < mesh->mNumFaces; i++)
    {
        aiFace face = mesh->mFaces[i];
        for(unsigned int j = 0; j < face.mNumIndices; j++) {
           // playerMeshIndices.push_back(face.mIndices[j + 2]);
            //playerMeshIndices.push_back(face.mIndices[j + 1]);
            playerMeshIndices.push_back(indexOffset + face.mIndices[j]);
        }
    }
}

void MTLEngine::createBuffers() {
    //transformationUB = metalDevice->newBuffer(sizeof(TransformationData), MTL::ResourceStorageModeShared);
    
    //debugTransformationUB = metalDevice->newBuffer(sizeof(TransformationData), MTL::ResourceStorageModeShared);
    
    cameraUB = metalDevice->newBuffer(sizeof(CameraData), MTL::ResourceStorageModeShared);
    
    // directional light doesn't change, let's just fill it right now
    // lightTransformationUB = metalDevice->newBuffer(sizeof(TransformationData), MTL::ResourceStorageModeShared);
    
    renderStateUB = metalDevice->newBuffer(sizeof(RenderState), MTL::ResourceStorageModeShared);
    
    // uniform for each shadow map transform
    for(int i = 0; i < shadowLayerInfos.size(); i++) {
        shadowCameraUBs.push_back(
                metalDevice->newBuffer(sizeof(CameraData), MTL::ResourceStorageModeShared)
        );
    }
    
    
    const int maxLines = 40;
    
    lineBuffer = metalDevice->newBuffer(sizeof(LineVertexData) * 6 * maxLines, MTL::ResourceStorageModeShared);
    lineTransformsBuffer = metalDevice->newBuffer(maxLines * sizeof(float4x4), MTL::ResourceStorageModeShared);
    
    lineTransforms.resize(maxLines, matrix4x4_identity());
    lineVertexData.resize(6 * maxLines);
    
    // add lines for outlining the main camera's frustum
    // we will modify these lines every frame using their index (which is base-1)
    //
    // there are 12 lines, where the order is
    //
    // 1: near-box L
    // 2: near-box U
    // 3: near-box R
    // 4: near-box D
    // 5: far-box L
    // 6: far-box U
    // 7: far-box R
    // 8: far-box D
    // 9: near-to-far TL
    // 10: near-to-far TR
    // 11: near-to-far BR
    // 12: near-to-far BL
    
    for(int i = 0; i < maxLines - 1; i++) {
        float3 color = i < 12? make_float3(1,1,0) : make_float3(0,0,1);
        if(i >= 24) {
            color = make_float3(1,0,0);
        }
        if(i >= 31) {
            color = make_float3(0,1,0);
        }
        // addLine(make_float3(0,0,0), make_float3(1,0,0), 0.25f, color);
    }
    
}

void MTLEngine::createDefaultLibrary() {
    // metalDefaultLibrary = metalDevice->newDefaultLibrary();
    NS::String* libraryPath = NS::String::string("JAMC.metallib", NS::StringEncoding::UTF8StringEncoding);

    NS::Error* error;
    metalDefaultLibrary = metalDevice->newLibrary(libraryPath, &error);


    if(!metalDefaultLibrary) {
        std::cerr << "Failed to load metal library." << std::endl;
        std::exit(-1);
    }
}

void MTLEngine::createCommandQueue() {
    metalCommandQueue = metalDevice->newCommandQueue();
}

void MTLEngine::createRenderPipeline() {
    MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("geometryPassVS", NS::ASCIIStringEncoding));
    assert(vertexShader);
    MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string("geometryPassFS", NS::ASCIIStringEncoding));
    assert(fragmentShader);
    
    MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
    assert(renderPipelineDescriptor);
    renderPipelineDescriptor->setLabel(NS::String::string("Triangle Rendering Pipeline", NS::ASCIIStringEncoding));
    renderPipelineDescriptor->setVertexFunction(vertexShader);
    renderPipelineDescriptor->setFragmentFunction(fragmentShader);
    
    renderPipelineDescriptor->colorAttachments()->object(0)->setPixelFormat(MTL::PixelFormatRGBA32Float); // position
    renderPipelineDescriptor->colorAttachments()->object(1)->setPixelFormat(MTL::PixelFormatRGBA32Float); // normal
    renderPipelineDescriptor->colorAttachments()->object(2)->setPixelFormat(MTL::PixelFormatRGBA32Float); // color
    renderPipelineDescriptor->colorAttachments()->object(3)->setPixelFormat(MTL::PixelFormatRGBA32Float); // emission
    
    // renderPipelineDescriptor->setSampleCount(sampleCount);
    renderPipelineDescriptor->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);
    
    MTL::RenderPipelineColorAttachmentDescriptor* colorAttachment = renderPipelineDescriptor->colorAttachments()->object(2);
    
    colorAttachment->setBlendingEnabled(true);
    colorAttachment->setRgbBlendOperation(MTL::BlendOperationAdd);
    colorAttachment->setAlphaBlendOperation(MTL::BlendOperationAdd);
    
    // https://learnopengl.com/Advanced-OpenGL/Blending
    // The blend function is:
    //      C = Cs * Fs + Cd * Fd
    //      - where C == color,
    //              F == factor,
    //              s == source (output of fragment shader / color buffer values),
    //              d == destination (what's currently in the output render target / the previously rendered)
    //
    //      The goal is to mix a transparent pixel, A,  with the pixel behind it, B. So this is saying
    //      in blend of the 2 pixels (A and B), the output should be A.alpha percent of A, and (1 - A.alpha) percent of B.
    //
    //      E.g. if A.alpha is 0.3, its color contribution should only be 30%, while the contribution
    //      of the pixel behind it should be (1 - 0.3 == 70%).
    //
    
    colorAttachment->setDestinationRGBBlendFactor(MTL::BlendFactorOneMinusSourceAlpha);
    colorAttachment->setSourceRGBBlendFactor(MTL::BlendFactorSourceAlpha);
    
    NS::Error* error;
    metalRenderPSO = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);
    
    if(metalRenderPSO == nullptr) {
        std::cout << "Error render pipeline: " << error->description() << " " << error->code() << std::endl;
        NSLog(@"Whatever: %@", error);
        std::exit(1);
    }
    
    MTL::DepthStencilDescriptor* depthStencilDescriptor = MTL::DepthStencilDescriptor::alloc()->init();
    depthStencilDescriptor->setDepthCompareFunction(MTL::CompareFunctionLessEqual);
    depthStencilDescriptor->setDepthWriteEnabled(true);
    depthStencilState = metalDevice->newDepthStencilState(depthStencilDescriptor);
    
    renderPipelineDescriptor->release();
    vertexShader->release();
    fragmentShader->release();
}

void MTLEngine::createDepthAndMSAATextures() {
    MTL::TextureDescriptor* msaaTextureDescriptor = MTL::TextureDescriptor::alloc()->init();
    msaaTextureDescriptor->setTextureType(MTL::TextureType2D);
    msaaTextureDescriptor->setPixelFormat(MTL::PixelFormatBGRA8Unorm);
    msaaTextureDescriptor->setWidth(metalLayer.drawableSize.width);
    msaaTextureDescriptor->setHeight(metalLayer.drawableSize.height);
    //msaaTextureDescriptor->setSampleCount(sampleCount);
    msaaTextureDescriptor->setUsage(MTL::TextureUsageRenderTarget);

    msaaRenderTarget = metalDevice->newTexture(msaaTextureDescriptor);

    MTL::TextureDescriptor* depthTextureDescriptor = MTL::TextureDescriptor::alloc()->init();
    depthTextureDescriptor->setTextureType(MTL::TextureType2D);
    depthTextureDescriptor->setPixelFormat(MTL::PixelFormatDepth32Float);
    depthTextureDescriptor->setWidth(metalLayer.drawableSize.width);
    depthTextureDescriptor->setHeight(metalLayer.drawableSize.height);
    depthTextureDescriptor->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead);
    //depthTextureDescriptor->setSampleCount(sampleCount);

    depthRenderTarget = metalDevice->newTexture(depthTextureDescriptor);

    msaaTextureDescriptor->release();
    depthTextureDescriptor->release();
}

void MTLEngine::createGBufferTextures() {
    auto createGBufferRenderTarget = [this]()->MTL::Texture* {
        MTL::TextureDescriptor* descriptor = MTL::TextureDescriptor::alloc()->init();
        descriptor->setTextureType(MTL::TextureType2D);
        descriptor->setPixelFormat(MTL::PixelFormatRGBA32Float);
        descriptor->setWidth(metalLayer.drawableSize.width);
        descriptor->setHeight(metalLayer.drawableSize.height);
        //descriptor->setSampleCount(sampleCount);
        descriptor->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead);

        MTL::Texture* ret = metalDevice->newTexture(descriptor);
        descriptor->release();
        return ret;
    };
    
    gPositionRT = createGBufferRenderTarget();
    gNormalRT = createGBufferRenderTarget();
    gAlbedoSpecRT = createGBufferRenderTarget();
    gEmissionRT = createGBufferRenderTarget();
}

void MTLEngine::createShadowMapTextures() {
    
    shadowMapRTs.clear();
    const int numShadowLayers = (int) shadowLayerInfos.size();

    for(int i = 0; i < numShadowLayers; i++) {
        MTL::TextureDescriptor* descriptor = MTL::TextureDescriptor::alloc()->init();
        descriptor->setTextureType(MTL::TextureType2D);
        descriptor->setPixelFormat(MTL::PixelFormatDepth32Float);
        
        descriptor->setWidth(shadowLayerInfos[i].resolution);
        descriptor->setHeight(shadowLayerInfos[i].resolution);
        descriptor->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead);

        MTL::Texture* newTexture = metalDevice->newTexture(descriptor);
        shadowMapRTs.push_back(newTexture);
    }
}

void MTLEngine::createLineTextures() {
    {
        MTL::TextureDescriptor* descriptor = MTL::TextureDescriptor::alloc()->init();
        descriptor->setTextureType(MTL::TextureType2D);
        descriptor->setPixelFormat(MTL::PixelFormatDepth32Float);
        
        descriptor->setWidth(metalLayer.drawableSize.width);
        descriptor->setHeight(metalLayer.drawableSize.height);
        descriptor->setUsage(MTL::TextureUsageRenderTarget);

        debugDepthRT = metalDevice->newTexture(descriptor);
    }
    {
        MTL::TextureDescriptor* descriptor = MTL::TextureDescriptor::alloc()->init();
        descriptor->setTextureType(MTL::TextureType2D);
        descriptor->setPixelFormat(MTL::PixelFormatRGBA32Float);
        
        descriptor->setWidth(metalLayer.drawableSize.width);
        descriptor->setHeight(metalLayer.drawableSize.height);
        descriptor->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead);

        debugRT = metalDevice->newTexture(descriptor);
    }
}

void MTLEngine::createLightPassTextures() {
    {
        MTL::TextureDescriptor* descriptor = MTL::TextureDescriptor::alloc()->init();
        descriptor->setTextureType(MTL::TextureType2D);
        descriptor->setPixelFormat(MTL::PixelFormatRGBA8Unorm);
        
        descriptor->setWidth(metalLayer.drawableSize.width);
        descriptor->setHeight(metalLayer.drawableSize.height);
        descriptor->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead);

        lightPassRT = metalDevice->newTexture(descriptor);
    }
}

void MTLEngine::createGeometryPassPipeline() {
    MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("geometryPassVS", NS::ASCIIStringEncoding));
    assert(vertexShader);
    MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string("geometryPassFS", NS::ASCIIStringEncoding));
    assert(fragmentShader);
    
    MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
    assert(renderPipelineDescriptor);
    renderPipelineDescriptor->setLabel(NS::String::string("Geometry Rendering Pipeline", NS::ASCIIStringEncoding));
    renderPipelineDescriptor->setVertexFunction(vertexShader);
    renderPipelineDescriptor->setFragmentFunction(fragmentShader);
    
    MTL::PixelFormat pixelFormat = (MTL::PixelFormat) metalLayer.pixelFormat;
    // renderPipelineDescriptor->colorAttachments()->object(0)->setPixelFormat(MTL::PixelFormat);
    renderPipelineDescriptor->setSampleCount(sampleCount);
    renderPipelineDescriptor->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);

    NS::Error* error;
    metalRenderPSO = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);
    
    if(metalRenderPSO == nullptr) {
        std::cout << "Error renderpipeline: " << error << std::endl;
        std::exit(1);
    }
    
    MTL::DepthStencilDescriptor* depthStencilDescriptor = MTL::DepthStencilDescriptor::alloc()->init();
    depthStencilDescriptor->setDepthCompareFunction(MTL::CompareFunctionLessEqual);
    depthStencilDescriptor->setDepthWriteEnabled(true);
    depthStencilState = metalDevice->newDepthStencilState(depthStencilDescriptor);
    
    renderPipelineDescriptor->release();
    vertexShader->release();
    fragmentShader->release();
}

void MTLEngine::createLightingPassPipeline() {
    MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("lightingPassVS", NS::ASCIIStringEncoding));
    assert(vertexShader);
    MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string("lightingPassFS", NS::ASCIIStringEncoding));
    assert(fragmentShader);
    
    MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
    assert(renderPipelineDescriptor);
    renderPipelineDescriptor->setLabel(NS::String::string("Lighting Render Pipeline", NS::ASCIIStringEncoding));
    renderPipelineDescriptor->setVertexFunction(vertexShader);
    renderPipelineDescriptor->setFragmentFunction(fragmentShader);
    
    renderPipelineDescriptor->colorAttachments()->object(0)->setPixelFormat(MTL::PixelFormatRGBA8Unorm);
    // renderPipelineDescriptor->setSampleCount(sampleCount);
    
    NS::Error* error;
    lightingRenderPipeline = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);
    
    
    if(lightingRenderPipeline == nullptr) {
        std::cout << "Error render pipeline: " << error->description() << std::endl;
        std::exit(1);
    }
    
    renderPipelineDescriptor->release();
    vertexShader->release();
    fragmentShader->release();
}

void MTLEngine::createShadowPassPipeline() {
    MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("shadowPassVS", NS::ASCIIStringEncoding));
    assert(vertexShader);
    MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string("shadowPassFS", NS::ASCIIStringEncoding));
    assert(fragmentShader);
    
    MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
    assert(renderPipelineDescriptor);
    renderPipelineDescriptor->setLabel(NS::String::string("Shadow Pass Pipeline", NS::ASCIIStringEncoding));
    renderPipelineDescriptor->setVertexFunction(vertexShader);
    renderPipelineDescriptor->setFragmentFunction(fragmentShader);
    
    renderPipelineDescriptor->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);
    
    NS::Error* error;
    MTL::RenderPipelineState* shadowPassPipeline = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);
    
    if(shadowPassPipeline == nullptr) {
        std::cout << "Error render pipeline: " << error->description() << std::endl;
        std::exit(1);
    }
    
    MTL::DepthStencilDescriptor* depthStencilDescriptor = MTL::DepthStencilDescriptor::alloc()->init();
    depthStencilDescriptor->setDepthCompareFunction(MTL::CompareFunctionLessEqual);
    depthStencilDescriptor->setDepthWriteEnabled(true);
    shadowDepthStencilState = metalDevice->newDepthStencilState(depthStencilDescriptor);
    
    renderPipelineDescriptor->release();
    vertexShader->release();
    fragmentShader->release();
}

void MTLEngine::createLinePassPipeline() {
    MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("lineVS", NS::ASCIIStringEncoding));
    assert(vertexShader);
    MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string("lineFS", NS::ASCIIStringEncoding));
    assert(fragmentShader);

    
    MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
    assert(renderPipelineDescriptor);
    renderPipelineDescriptor->setLabel(NS::String::string("Debug Lines Pipeline", NS::ASCIIStringEncoding));
    renderPipelineDescriptor->setVertexFunction(vertexShader);
    renderPipelineDescriptor->setFragmentFunction(fragmentShader);
    
    renderPipelineDescriptor->colorAttachments()->object(0)->setPixelFormat(MTL::PixelFormatRGBA32Float);
    
    renderPipelineDescriptor->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);
    
    NS::Error* error;
    linePassPipeline = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);
    
    if(linePassPipeline == nullptr) {
        std::cout << "Error render pipeline: " << error->description() << std::endl;
        std::exit(1);
    }
    
    MTL::DepthStencilDescriptor* depthStencilDescriptor = MTL::DepthStencilDescriptor::alloc()->init();
    depthStencilDescriptor->setDepthCompareFunction(MTL::CompareFunctionLessEqual);
    depthStencilDescriptor->setDepthWriteEnabled(true);
    lineDepthStencilState = metalDevice->newDepthStencilState(depthStencilDescriptor);
    
    renderPipelineDescriptor->release();
    vertexShader->release();
    fragmentShader->release();
}

void MTLEngine::createRenderPassDescriptor() {
    renderPassDescriptor = MTL::RenderPassDescriptor::alloc()->init();
       
    // TODO: order independent translucency
    //renderPassDescriptor->setImageblockSampleLength(metalRenderPSO->imageblockSampleLength());
    //renderPassDescriptor->setTileWidth(32);
    //renderPassDescriptor->setTileHeight(32);
        
    struct Local {
        static void setupColorAttachment(MTL::RenderPassDescriptor* rpdescriptor, NS::UInteger index, MTL::Texture* texture, MTL::LoadAction loadAction) {
            MTL::RenderPassColorAttachmentDescriptor* colorAttachment = rpdescriptor->colorAttachments()->object(index);
            colorAttachment->setTexture(texture);
            
            colorAttachment->setLoadAction(loadAction);
            colorAttachment->setClearColor(MTL::ClearColor(0.f, 0.f, 0.f, 1.0));
            colorAttachment->setStoreAction(MTL::StoreActionStore);
        }
    };
        
    // gPositionRT is cleared by skybox render pass, and we don't want to clear it because it's rendered first.
    // Everything else should be cleared when rendered.
    Local::setupColorAttachment(renderPassDescriptor, 0, gPositionRT, MTL::LoadActionLoad);
    Local::setupColorAttachment(renderPassDescriptor, 1, gNormalRT, MTL::LoadActionClear);
    Local::setupColorAttachment(renderPassDescriptor, 2, gAlbedoSpecRT, MTL::LoadActionClear);
    Local::setupColorAttachment(renderPassDescriptor, 3, gEmissionRT, MTL::LoadActionClear);
    
    //MTL::RenderPassColorAttachmentDescriptor* colorAttachment = renderPassDescriptor->colorAttachments()->object(0);
    // colorAttachment->setResolveTexture(metalDrawable->texture());
    //colorAttachment->setStoreAction(MTL::StoreActionMultisampleResolve);
        
    MTL::RenderPassDepthAttachmentDescriptor* depthAttachment = renderPassDescriptor->depthAttachment();
    depthAttachment->setTexture(depthRenderTarget);
    depthAttachment->setLoadAction(MTL::LoadActionClear);
    depthAttachment->setStoreAction(MTL::StoreActionStore);
    depthAttachment->setClearDepth(1.0f);
}

void MTLEngine::createLightingRenderPassDescriptor() {
    lightingRenderPassDescriptor = MTL::RenderPassDescriptor::alloc()->init();
    
    MTL::RenderPassColorAttachmentDescriptor* colorAttachment = lightingRenderPassDescriptor->colorAttachments()->object(0);

    colorAttachment->setTexture(lightPassRT);
    colorAttachment->setStoreAction(MTL::StoreActionStore);
    colorAttachment->setLoadAction(MTL::LoadActionClear);
    colorAttachment->setClearColor(MTL::ClearColor(0.f, 0.f, 0.f, 1.0));
}

void MTLEngine::createShadowRenderPassDescriptor() {
    int ind = 0;
    shadowMapRPDescriptors.clear();
    for(auto it = std::begin(shadowLayerInfos); it != std::end(shadowLayerInfos); ++it, ind++) {
        
        MTL::RenderPassDescriptor* newDescriptor = MTL::RenderPassDescriptor::alloc()->init();
        MTL::RenderPassDepthAttachmentDescriptor* depthAttachment = newDescriptor->depthAttachment();
        depthAttachment->setTexture(shadowMapRTs[ind]);
        depthAttachment->setLoadAction(MTL::LoadActionClear);
        depthAttachment->setStoreAction(MTL::StoreActionStore);
        depthAttachment->setClearDepth(1.0f);
        
        shadowMapRPDescriptors.push_back(newDescriptor);
    }
}

void MTLEngine::createLineRenderPassDescriptor() {
    linePassDescriptor = MTL::RenderPassDescriptor::alloc()->init();
    
    
    MTL::RenderPassColorAttachmentDescriptor* colorAttachment = linePassDescriptor->colorAttachments()->object(0);
    colorAttachment->setTexture(debugRT);
    colorAttachment->setLoadAction(MTL::LoadActionClear);
    colorAttachment->setClearColor(MTL::ClearColor(0.f, 0.f, 0.f, 1.0));
    colorAttachment->setStoreAction(MTL::StoreActionStore);
    
    MTL::RenderPassDepthAttachmentDescriptor* depthAttachment = linePassDescriptor->depthAttachment();
    depthAttachment->setTexture(debugDepthRT);
    depthAttachment->setLoadAction(MTL::LoadActionClear);
    depthAttachment->setStoreAction(MTL::StoreActionDontCare);
    depthAttachment->setClearDepth(1.0f);
}

void MTLEngine::updateRenderPassDescriptor() {
    //lightingRenderPassDescriptor->colorAttachments()->object(0)->setTexture(metalDrawable->texture());
    //lightVolumeRPD->colorAttachments()->object(0)->setTexture(metalDrawable->texture());
    postProcessRPD->colorAttachments()->object(0)->setTexture(metalDrawable->texture());
    //lightingRenderPassDescriptor->colorAttachments()->object(0)->setResolveTexture(metalDrawable->texture());
    // renderPassDescriptor->depthAttachment()->setTexture(depthRenderTarget);
    //shadowRenderPassDescriptor->depthAttachment()->setTexture(shadowMapRT);
}

void MTLEngine::draw() {
    //  TODO: refactor, separate 3D and imgui rendering
    metalCommandBuffer = metalCommandQueue->commandBuffer();
    metalCommandBuffer->presentDrawable(metalDrawable);
    
    postProcessRPD->colorAttachments()->object(0)->setTexture(metalDrawable->texture());
    
    // shadow pass (one per shadow layer)
    if(enableShadowMap) {
        for(int i = 0; i < shadowLayerInfos.size(); i++) {
            
            MTL::RenderCommandEncoder* rce = metalCommandBuffer->renderCommandEncoder(shadowMapRPDescriptors[i]);
            rce->setDepthStencilState(shadowDepthStencilState);
            rce->setFrontFacingWinding(MTL::WindingCounterClockwise);
            
            // avoid peter-panning.
            // BUG: causing detached shadows
            //renderCommandEncoder->setCullMode(MTL::CullModeFront);
            rce->setCullMode(MTL::CullModeBack);
            
            // voxels
            rce->setRenderPipelineState(voxelShadowMapRPS);
            rce->setVertexBuffer(shadowCameraUBs[i], 0, 1);
              
            drawChunkGeometry(rce);
            
            
            // skeletal mesh
            rce->setRenderPipelineState(skeletalMeshShadowMapRPS);
            
            MTL::Buffer* vertexBuffer = player->getVertexBuffer();
            MTL::Buffer* indexBuffer = player->getIndexBuffer();
            MTL::Buffer* btBuffer = player->getBoneTransformsUB();
            MTL::Buffer* objBuffer = player->getObjectDataUB();
            MTL::Buffer* modelBuffer = player->getMeshTransformsUB();
            
            rce->setVertexBuffer(vertexBuffer, 0, 0);
            rce->setVertexBuffer(btBuffer, 0, 1);
            rce->setVertexBuffer(modelBuffer, 0, 2);
            rce->setVertexBuffer(objBuffer, 0, 3);
            rce->setVertexBuffer(shadowCameraUBs[i], 0, 4);
            
            rce->drawIndexedPrimitives(MTL::PrimitiveTypeTriangle, player->getIndexBufferSize(), MTL::IndexTypeUInt32, indexBuffer, 0, 1);
        

            rce->endEncoding();
        }
    }
    
    // start render to G-Buffer
    
    // skybox
    {
        
        MTL::RenderCommandEncoder* rce = metalCommandBuffer->renderCommandEncoder(skyboxRPD);
        rce->setRenderPipelineState(skyboxRPS);
        
        rce->setVertexBuffer(skyboxCubeVB, 0, 0);
        rce->setVertexBuffer(skyboxMVPUB, 0, 1);
        rce->setFragmentTexture(skyboxTex, 0);
        
        rce->drawPrimitives(MTL::PrimitiveTypeTriangle, NS::UInteger(0), NS::UInteger(36));
        
        rce->endEncoding();
        
    }
    
    
    {
        // voxels
        MTL::RenderCommandEncoder* rce = metalCommandBuffer->renderCommandEncoder(renderPassDescriptor);
        rce->setFrontFacingWinding(MTL::WindingCounterClockwise);
        rce->setCullMode(MTL::CullModeBack);
        rce->setDepthStencilState(depthStencilState);
        
        rce->setRenderPipelineState(metalRenderPSO);
        rce->setFragmentTexture(atlasTexture->texture, 0);
        rce->setVertexBuffer(cameraUB, 0, 1);
        
        drawChunkGeometry(rce);
    
        rce->endEncoding();
    }
    
    // meshes
    {
        MTL::RenderCommandEncoder* rce = metalCommandBuffer->renderCommandEncoder(meshRPD);
        rce->setFrontFacingWinding(MTL::WindingCounterClockwise);
        rce->setCullMode(MTL::CullModeBack);
        rce->setDepthStencilState(depthStencilState);
        
        rce->setRenderPipelineState(meshRPS);
        
        
        MTL::Buffer* vertexBuffer = player->getVertexBuffer();
        MTL::Buffer* indexBuffer = player->getIndexBuffer();
        MTL::Buffer* btBuffer = player->getBoneTransformsUB();
        MTL::Buffer* objBuffer = player->getObjectDataUB();
        MTL::Buffer* modelBuffer = player->getMeshTransformsUB();
        
        rce->setVertexBuffer(vertexBuffer, 0, 0);
        rce->setVertexBuffer(btBuffer, 0, 1);
        rce->setVertexBuffer(modelBuffer, 0, 2);
        rce->setVertexBuffer(objBuffer, 0, 3);
        rce->setVertexBuffer(cameraUB, 0, 4);
        
        rce->setFragmentTexture(player->getMeshTexture(), 0);
        
        rce->drawIndexedPrimitives(MTL::PrimitiveTypeTriangle, player->getIndexBufferSize(), MTL::IndexTypeUInt32, indexBuffer, 0, 1);
    
        rce->endEncoding();
    }

    // end render to G-Buffer
    

    // ssao pass
    if(enableSSAO)
    {
        {
            MTL::RenderCommandEncoder* rce = metalCommandBuffer->renderCommandEncoder(ssaoRenderPassDescriptor);
            rce->setRenderPipelineState(ssaoRenderPipeline);
            rce->setVertexBuffer(squareVertexBuffer, 0, 0);
            
            rce->setFragmentTexture(gPositionRT, 0);
            rce->setFragmentTexture(gNormalRT, 1);
            rce->setFragmentTexture(gAlbedoSpecRT, 2);
            rce->setFragmentTexture(ssaoNoiseTex, 3);
            
            rce->setFragmentBuffer(ssaoKernelUB, 0, 0);
            rce->setFragmentBuffer(cameraUB, 0, 1);
            
            rce->drawPrimitives(MTL::PrimitiveTypeTriangle, NS::UInteger(0), NS::UInteger(6));
            
            rce->endEncoding();
        }
        
        {
            MTL::RenderCommandEncoder* rce = metalCommandBuffer->renderCommandEncoder(ssaoBlurRenderPassDescriptor);
            rce->setRenderPipelineState(ssaoBlurRenderPipeline);
            rce->setVertexBuffer(squareVertexBuffer, 0, 0);
            
            rce->setFragmentTexture(ssaoRT, 0);
            
            rce->drawPrimitives(MTL::PrimitiveTypeTriangle, NS::UInteger(0), NS::UInteger(6));
            
            rce->endEncoding();
        }
    }
    
    auto bindLightingPassFragmentData = [this](MTL::RenderCommandEncoder* rce) {
        rce->setFragmentTexture(gPositionRT, 0);
        rce->setFragmentTexture(gNormalRT, 1);
        rce->setFragmentTexture(gAlbedoSpecRT, 2);
        rce->setFragmentTexture(gEmissionRT, 3);
        for(int i = 0; i < shadowLayerInfos.size(); i++) {
            rce->setFragmentTexture(shadowMapRTs[i], 4 + i);
        }
        rce->setFragmentTexture(ssaoBlurRT, 7);
        
        rce->setFragmentBuffer(cameraUB, 0, 0);
        rce->setFragmentBuffer(shadowCameraUBs[0], 0, 1);
        rce->setFragmentBuffer(shadowCameraUBs[1], 0, 2);
        rce->setFragmentBuffer(shadowCameraUBs[2], 0, 3);
        rce->setFragmentBuffer(renderStateUB, 0, 4);
    };
    
    //
    // lighting pass
    //
    {
        MTL::RenderCommandEncoder* renderCommandEncoder = metalCommandBuffer->renderCommandEncoder(lightingRenderPassDescriptor);
        
        renderCommandEncoder->setRenderPipelineState(lightingRenderPipeline);
        
        renderCommandEncoder->setVertexBuffer(squareVertexBuffer, 0, 0); // we're just rendering a quad
        
        bindLightingPassFragmentData(renderCommandEncoder);
        
        MTL::PrimitiveType typeTriangle = MTL::PrimitiveTypeTriangle;
        NS::UInteger vertexStart = 0;
        NS::UInteger vertexCount = 6;
        renderCommandEncoder->drawPrimitives(typeTriangle, vertexStart, vertexCount);
        
        renderCommandEncoder->endEncoding();
    }
    
    
    // bloom
    {
        bool horizontal = true;
        int amount = 10;
        
        std::array<MTL::RenderPassDescriptor*, 2> descriptors = { gaussianBlurRPD0, gaussianBlurRPD1 };
        std::array<MTL::Texture*, 2> renderTargets = { gaussianBlurRT0, gaussianBlurRT1 };
        std::array<MTL::RenderPipelineState*, 2> pipelines = { gaussianBlurRPSVertical, gaussianBlurRPSHorizontal };
        
        for(int i = 0; i < amount; i++) {
            GaussianBlurState gbs;
            gbs.horizontal = horizontal;
            memcpy(gaussianBlurUB->contents(), &gbs, sizeof(GaussianBlurState));
            
            MTL::RenderCommandEncoder* rce = metalCommandBuffer->renderCommandEncoder(descriptors[horizontal]);
            rce->setRenderPipelineState(pipelines[horizontal]);
            
            const bool firstIter = i == 0;
            rce->setFragmentTexture(firstIter? gEmissionRT : renderTargets[!horizontal], 0);
           // rce->setFragmentTexture(renderTargets[!horizontal], 0);
            rce->setFragmentBuffer(gaussianBlurUB, 0, 0);
            
            rce->setVertexBuffer(squareVertexBuffer, 0, 0); // render a quad
            rce->drawPrimitives(MTL::PrimitiveTypeTriangle, NS::UInteger(0), NS::UInteger(6));
            
            rce->endEncoding();
            
            horizontal = !horizontal;
        }
    }
    
    
    // point light - deferred
    
    if(curPointLightIndex > 0) {
        MTL::RenderCommandEncoder* renderCommandEncoder = metalCommandBuffer->renderCommandEncoder(lightVolumeRPD);
        
        renderCommandEncoder->setRenderPipelineState(lightVolumeRPS);
        
        renderCommandEncoder->setVertexBuffer(squareVertexBuffer, 0, 0); // we're just rendering a quad
        
        bindLightingPassFragmentData(renderCommandEncoder);
        
        // we render instanced-spheres in the world with proper radius wrt each point-light
        renderCommandEncoder->setVertexBuffer(sphereVB, 0, 0);
        renderCommandEncoder->setVertexBuffer(cameraUB, 0, 1);
        renderCommandEncoder->setVertexBuffer(lightVolumeInstanceUB, 0, 2);
        
        renderCommandEncoder->drawIndexedPrimitives(MTL::PrimitiveTypeTriangle, numSphereIndices, MTL::IndexTypeUInt32, sphereIB, NS::UInteger(0), NS::UInteger(pointLights.size()));

        renderCommandEncoder->endEncoding();
    }
    
    // line pass aka unlit pass
    if(visibleLines.size() >= 1)
    {
        MTL::RenderCommandEncoder* rce = metalCommandBuffer->renderCommandEncoder(linePassDescriptor);
        rce->setRenderPipelineState(linePassPipeline);
        rce->setDepthStencilState(lineDepthStencilState);
        rce->setCullMode(MTL::CullModeNone);
        
        rce->setVertexBuffer(lineSquareVB, 0, 0); // we're just rendering a quad
        rce->setVertexBuffer(cameraUB, 0, 1);
        rce->setVertexBuffer(lineDataUB, 0, 2);
        
        rce->drawIndexedPrimitives(MTL::PrimitiveTypeTriangle, 6, MTL::IndexTypeUInt32, lineSquareIB, NS::UInteger(0), NS::UInteger(visibleLines.size()));
        rce->endEncoding();
    }
    
    // post-process - combine light + bloom + etc.
    {
        MTL::RenderCommandEncoder* rce = metalCommandBuffer->renderCommandEncoder(postProcessRPD);
        rce->setRenderPipelineState(postProcessRPS);
        
        rce->setFragmentTexture(lightPassRT, 0);
        rce->setFragmentTexture(gaussianBlurRT1, 1);
        rce->setFragmentTexture(debugRT, 2);
        
        rce->setFragmentTexture(depthRenderTarget, 3);
        rce->setFragmentTexture(debugDepthRT, 4);
        
        rce->setVertexBuffer(squareVertexBuffer, 0, 0);
        rce->drawPrimitives(MTL::PrimitiveTypeTriangle, NS::UInteger(0), NS::UInteger(6));
        
        rce->endEncoding();
    }
        
    //
    // debug pass
    //
    {
        /*
        MTL::RenderCommandEncoder* renderCommandEncoder = metalCommandBuffer->renderCommandEncoder(linePassDescriptor);
        renderCommandEncoder->setRenderPipelineState(linePassPipeline);
        // renderCommandEncoder->setTile
        renderCommandEncoder->setDepthStencilState(lineDepthStencilState);
        renderCommandEncoder->setVertexBuffer(debugTransformationUB, 0, 1);
        renderCommandEncoder->setFragmentTexture(atlasTexture->texture, 0);
        renderCommandEncoder->setFrontFacingWinding(MTL::WindingCounterClockwise);
        renderCommandEncoder->setCullMode(MTL::CullModeBack);
        //renderCommandEncoder->setTriangleFillMode(MTL::TriangleFillModeLines); // wireframe
        

        drawChunkGeometry(renderCommandEncoder);
        
        if(curLineTransformIndex > 1) {
            renderCommandEncoder->setRenderPipelineState(linePassPipeline);
            renderCommandEncoder->setCullMode(MTL::CullModeNone);
            
            /*
            LineVertexData d[] {
                    {{ 0.0f, -1.0f, -1.0f, 1.0f}, {0.0f, 1.0f, 0.0f, 1.0f}, 1},
                    {{ 0.0f,  1.0f, -1.0f, 1.0f}, {0.0f, 1.0f, 0.0f, 1.0f}, 1},
                    {{ 0.0f,  1.0f, 1.0f, 1.0f}, {0.0f, 1.0f, 0.0f, 1.0f}, 1},
                    {{ 0.0f, -1.0f, -1.0f, 1.0f}, {0.0f, 1.0f, 0.0f, 1.0f}, 1},
                    {{ 0.0f,  1.0f, 1.0f, 1.0f}, {0.0f, 0.0f, 1.0f, 1.0f}, 1},
                    {{ 0.0f, -1.0f, 1.0f, 1.0f}, {1.0f, 0.0f, 0.0f, 1.0f}, 1}
            };
            
            memcpy(lineBuffer->contents(), d, sizeof(d));
            
            
            renderCommandEncoder->setVertexBuffer(lineBuffer, 0, 0); // we're just rendering a quad
            renderCommandEncoder->setVertexBuffer(debugTransformationUB, 0, 1);
            renderCommandEncoder->setVertexBuffer(lineTransformsBuffer, 0, 2);
            
            MTL::PrimitiveType typeTriangle = MTL::PrimitiveTypeTriangle;
            NS::UInteger vertexStart = 0;
            NS::UInteger vertexCount = lineVertexData.size();
            renderCommandEncoder->drawPrimitives(typeTriangle, vertexStart, vertexCount);
        }
        
        renderCommandEncoder->endEncoding();
        */
    }
    
    
    // imgui
    {
        imguiRenderPassDescriptor = MTL::RenderPassDescriptor::alloc()->init();
        
        MTL::RenderPassColorAttachmentDescriptor* colorAttachment = imguiRenderPassDescriptor->colorAttachments()->object(0);
        
        colorAttachment->setTexture(metalDrawable->texture());
        colorAttachment->setLoadAction(MTL::LoadActionLoad);
        colorAttachment->setClearColor(MTL::ClearColor(0.0f/255.0f, 0.0f/255.0f, 0.0f/255.0f, 0.0));
        colorAttachment->setStoreAction(MTL::StoreActionStore);
        
        MTL::RenderCommandEncoder* renderCommandEncoder = metalCommandBuffer->renderCommandEncoder(imguiRenderPassDescriptor);
        
        // Start the Dear ImGui frame
        ImGui_ImplMetal_NewFrame(imguiRenderPassDescriptor);
        ImGui_ImplGlfw_NewFrame();
        ImGui::NewFrame();
        
        // 2. Show a simple window that we create ourselves. We use a Begin/End pair to create a named window.
        {
            ImGui::Begin("Persistent Info", nullptr, ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoBackground | ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoScrollbar);
            ImGui::Text("FPS: %d", avgFPS);
            ImGui::SetWindowPos(ImVec2(0,0));
            ImGui::End();
        }
        
        {
            ImGui::Begin("Debug");
//
            ImGui::Checkbox("SSAO", &enableSSAO);
            ImGui::Checkbox("CSM", &enableShadowMap);
            
            ImGui::Text("Chunks left to mesh: %d", (int) chunksToMesh.size_approx());
            ImGui::Text("Chunks left to generate: %d", (int) chunksToGenerate.size_approx());

            ImGui::Text("Collisions: %d", numCollisions);
            ImGui::Text("Visible Lines: %d", (int) visibleLines.size());
            ImGui::Text("Mouse Pos: (%f,%f)", curMousePos.x, curMousePos.y);
            ImGui::Text("Chunk: (%d, %d, %d)", curChunk.x, curChunk.y, curChunk.z);
            float3 pos = player->getPosition();
            ImGui::Text("Player: (%f, %f, %f)", pos.x, pos.y, pos.z);
            float3 vel = player->getVelocity();
            ImGui::Text("Player Vel: (%f, %f, %f)", vel.x, vel.y, vel.z);
            float3 force = player->getForce();
            ImGui::Text("Player Force: (%f, %f, %f)", force.x, force.y, force.z);
            ImGui::Text("Push back: (%f, %f, %f)", collisionPushBackVel.x, collisionPushBackVel.y, collisionPushBackVel.z);
            if(ImGui::RadioButton("First-Person", activeCameraType == EPlayerCameraType::FirstPerson)) {
                activeCameraType = EPlayerCameraType::FirstPerson;
                camera.setUseYawPitch(true);
            }
            if(ImGui::RadioButton("Third-Person", activeCameraType == EPlayerCameraType::ThirdPerson)) {
                activeCameraType = EPlayerCameraType::ThirdPerson;
                camera.setUseYawPitch(false);
            }
            
            struct NodeWrap {
                AssimpNode node;
                bool shouldPop;
            };
            
            
            ImVec2 imgSize = ImVec2(metalLayer.drawableSize.width / 4, metalLayer.drawableSize.height/4);
            ImGui::Image((void*) debugDepthRT, imgSize);
            ImGui::Image((void*) depthRenderTarget, imgSize);
            ImGui::Image((void*) gAlbedoSpecRT, imgSize);
            ImGui::Image((void*) gNormalRT, imgSize);
            
            ImGui::End();
        }
        
        // Rendering
        ImGui::Render();
        ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), metalCommandBuffer, renderCommandEncoder);
        
        
        renderCommandEncoder->endEncoding();
    }
    
    
    
    metalCommandBuffer->commit();
    metalCommandBuffer->waitUntilCompleted();
    
    imguiRenderPassDescriptor->release();
}

void MTLEngine::drawChunkGeometry(MTL::RenderCommandEncoder* renderCommandEncoder) {
    std::lock_guard<std::mutex> lcGuard(loadedChunksMutex);
    for(const Int3D& xyz : sortedVisibleChunks) {
	if(!loadedChunks.contains(xyz)) {
	    return;
	}
    }

    for(const Int3D& xyz : sortedVisibleChunks) {
	if(!loadedChunks.contains(xyz)) {
	    return;
	}

        if(!ChunkRenderer::cachedChunkBuffers.contains(xyz)) {
            // std::cout << fmt::format("render has no loaded chunk at: {}", DebugUtils::stringify_tupleInt3(xyz)) << std::endl;
            continue;
        }
        const Chunk& chunk = loadedChunks.at(xyz);
        // std::cout << fmt::format("rendering: {},{},{}", get<0>(xyz), get<1>(xyz), get<2>(xyz)) << std::endl;
        std::lock_guard<std::mutex> rdGuard(cachedChunkRDMutex);
        chunkRenderers[xyz]->render(chunk, renderCommandEncoder, metalDevice, 0);
    }
     
    for (const Int3D& xyz : sortedVisibleChunks) {
        if(!ChunkRenderer::cachedChunkBuffers.contains(xyz)) {
            // std::cout << fmt::format("render has no loaded chunk at: {}", DebugUtils::stringify_tupleInt3(xyz)) << std::endl;
            continue;
        }
        const Chunk& chunk = loadedChunks.at(xyz);
        // std::cout << fmt::format("rendering: {},{},{}", get<0>(xyz), get<1>(xyz), get<2>(xyz)) << std::endl;
        std::lock_guard<std::mutex> rdGuard(cachedChunkRDMutex);
        chunkRenderers[xyz]->renderTransparent(chunk, renderCommandEncoder);
    }
}

void MTLEngine::cameraTick(const float deltaTime, Camera& outCamera, const CameraMovementKeyMap keyMap) {
    float3 moveDir = make_float3(0,0,0);
    const float3& forward = outCamera.getForwardVector();
    const float3& right = outCamera.getRightVector();
    const float3& up = outCamera.getUpVector();
    const float3 absUp = make_float3(0,1,0);
    
    bool bAnyDown = false;
    if(keydownArr[keyMap.forward]) {
        moveDir += forward;
        bAnyDown |= true;
    }
    else if(keydownArr[keyMap.back]) {
        moveDir += -forward;
        bAnyDown |= true;
    }
    
    if(keydownArr[keyMap.left]) {
        moveDir += -right;
        bAnyDown |= true;
    }
    else if(keydownArr[keyMap.right]) {
        moveDir += right;
        bAnyDown |= true;
    }
    
    if(keydownArr[keyMap.down]) {
        moveDir += -absUp;
        bAnyDown |= true;
    }
    else if(keydownArr[keyMap.up]) {
        moveDir += absUp;
        bAnyDown |= true;
    }
    
    
    if(isKeyDown(keyMap.turnLeft)) {
        outCamera.addPitchYaw(0,-deltaTime * outCamera.getRotateSpeed());
    }
    else if(isKeyDown(keyMap.turnRight)) {
        outCamera.addPitchYaw(0, deltaTime * outCamera.getRotateSpeed());
    }
    
    if(isKeyDown(keyMap.turnUp)) {
        outCamera.addPitchYaw(deltaTime * outCamera.getRotateSpeed(), 0);
    }
    else if(isKeyDown(keyMap.turnDown)) {
        outCamera.addPitchYaw(-deltaTime * outCamera.getRotateSpeed(), 0);
    }
    
    if(bAnyDown) {
        moveDir = normalize(moveDir);
    }
    
    outCamera.setMoveDirection(moveDir);
}

void MTLEngine::tickPlayerCameraThirdPerson(const float deltaTime, Camera& outCamera) {
    outCamera.setUseYawPitch(false);
    
    float3 relPos = make_float3(-4, 2, 0);
    
    outCamera.setPosition(player->getPosition() +
                          relPos.x * player->getForwardVector() +
                          relPos.y * player->getUpVector() +
                          relPos.z * player->getRightVector());
    
    outCamera.setForwardVectorDirect(normalize(player->getPosition() - outCamera.getPosition()));
}

void MTLEngine::tickPlayerCameraFirstPerson(const float deltaTime, Camera& outCamera) {
    outCamera.setUseYawPitch(true);
    
    float3 relPos = make_float3(0.125,0,0);
    
    outCamera.setPosition(player->getPosition() +
                          relPos.x * player->getForwardVector() +
                          relPos.y * player->getUpVector() +
                          relPos.z * player->getRightVector());
    
    outCamera.setPosition(player->getHeadPosition());
    
    // outCamera.setForwardVectorDirect(player->getForwardVector() + -1 * player->getUpVector());
}

void MTLEngine::keyTick(const float deltaTime) {
    /*
    bool playerIsMoving = false;
    if(controlPlayer) {
        if(isKeyDown(EKey::W)) {
            playerIsMoving = true;
            playerModelMat = matrix4x4_translation(5 * deltaTime, 0, 0) * playerModelMat;
        }
        else if(isKeyDown(EKey::S)) {
            playerIsMoving = true;
            playerModelMat = matrix4x4_translation(-5 * deltaTime, 0, 0) * playerModelMat;
        }
    }
    else {
        
        CameraMovementKeyMap mainCamKeyMap;
        mainCamKeyMap.left = EKey::A;
        mainCamKeyMap.right = EKey::D;
        mainCamKeyMap.forward = EKey::W;
        mainCamKeyMap.back = EKey::S;
        mainCamKeyMap.up = EKey::E;
        mainCamKeyMap.down = EKey::Q;
        mainCamKeyMap.turnUp = EKey::Up;
        mainCamKeyMap.turnDown = EKey::Down;
        mainCamKeyMap.turnLeft = EKey::Left;
        mainCamKeyMap.turnRight = EKey::Right;
        
        cameraTick(deltaTime, camera, mainCamKeyMap);
    }
    
    if(playerIsMoving) {
        animator.play("Armature|Walk");
    }
    else {
        animator.pause();
    }
    
    ObjectData od;
    od.model = playerModelMat;
    memcpy(playerObjectUB->contents(), &od, sizeof(od));
    */
    
    {
        CameraMovementKeyMap keyMap;
        keyMap.left = EKey::J;
        keyMap.right = EKey::L;
        keyMap.forward = EKey::I;
        keyMap.back = EKey::K;
        keyMap.up = EKey::O;
        keyMap.down = EKey::U;
        
        keyMap.turnUp = EKey::V;
        keyMap.turnDown = EKey::B;
        keyMap.turnLeft = EKey::N;
        keyMap.turnRight = EKey::M;
        
        cameraTick(deltaTime, debugCamera, keyMap);
    }
    
    if(isKeyDown(EKey::Space)) {
        spaceWasDown = true;
    }
    
    /*
    if(spaceWasDown && !isKeyDown(EKey::Space)) {
        controlPlayer = !controlPlayer;
        
        debugState = (debugState + 1) % 6;
        
        debugCamera.setPosition(camera.getPosition());
        debugCamera.setPitchYaw(camera.getPitch(), camera.getYaw());
    }
    */
    
    if(!isKeyDown(EKey::Space)) {
        spaceWasDown = false;
    }
    
    if(isKeyDown(EKey::Escape) && captureMouse) {
        glfwSetInputMode(glfwWindow, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
        captureMouse = false;
    }
    else if(!isKeyDown(EKey::Escape) && !captureMouse) {
        glfwSetInputMode(glfwWindow, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
        captureMouse = true;
    }
    
}

void MTLEngine::mouseTick(const float deltaTime) {
    if(isInitialMousePos) {
        return;
    }
    
    const float2 mouseDelta = curMousePos - prevMousePos;
    prevMousePos = curMousePos;
    
    if(!captureMouse) {
        return;
    }
    
    float deltaYaw = camera.getSensitivity() * mouseDelta.x;
    float deltaPitch = -camera.getSensitivity() * mouseDelta.y;
    
    if(activeCameraType == EPlayerCameraType::FirstPerson) {
        camera.addPitchYaw(deltaPitch, deltaYaw);
        
        float3 cameraFwd = camera.getForwardVector();
        float3 playerFwd = normalize(make_float3(cameraFwd.x, 0, cameraFwd.z));
        const float3 unitX = make_float3(1,0,0);
        player->setRotation(quatf(unitX, playerFwd));
    }
    else if(activeCameraType == EPlayerCameraType::ThirdPerson) {
        quatf curRot = player->getRotation();
        float curAngle = curRot.angle();
        
        float deltaAngle = -0.05 * camera.getSensitivity() * mouseDelta.x;
        quatf deltaRot = quatf(deltaAngle, make_float3(0,1,0));
        
        player->setRotation(deltaRot * curRot);
        
    }
    
}

void MTLEngine::engineTick(const float deltaTime) {
    keyTick(deltaTime);
    mouseTick(deltaTime);
    
    // move player
    camera.addPosition( (deltaTime * camera.getSpeed()) * camera.getMoveDirection());
    debugCamera.addPosition( (deltaTime * debugCamera.getSpeed()) * debugCamera.getMoveDirection());
    
    Int3D prevChunk = curChunk;
    curChunk = calculateCurrentChunk(player->getPosition());
    
    if(prevChunk != curChunk) {
        updateVisibleChunkIndices();
        visibleChunksDirty = true;
        chunkGenPending = true;
    }
    
    if(chunkGenPending) {
        resolveChunkGeneration();
    }
    
    if(enableShadowMap) {
        float zStart = 0.0f;
        for(int i = 0; i < shadowLayerInfos.size(); i++) {
            float zEnd = shadowLayerInfos[i].camAlpha;
            bindShadowMapFrustumWithMainCamera(zStart, zEnd, shadowMapCameras[i]);
            zStart = zEnd;
        }
    }
    
    if(isKeyDown(EKey::J)) {
        const simd::float3 pos = player->getPosition();
        player->setPosition(simd::float3 {pos.x, 100, pos.z});
    }
    
    player->tick(deltaTime, keydownArr);
    
    // attach camera to player
    if(activeCameraType == EPlayerCameraType::FirstPerson) {
        tickPlayerCameraFirstPerson(deltaTime, camera);
    }
    else if(activeCameraType == EPlayerCameraType::ThirdPerson) {
        tickPlayerCameraThirdPerson(deltaTime, camera);
    }
    
    updateUniforms();
    
    
    physicsTick(deltaTime);
    
    if(linesDirty) {
        commitLines();
        linesDirty = false;
    }
}

void MTLEngine::physicsTick(const float deltaTime) {
    if(!loadedChunks.contains(curChunk)) {
        return;
    }
    
    const AABB& playerCollision = player->getCollision();
    bool collides = false;
    
    std::vector<Chunk*> chunksToQuery;
    std::array<Int3D, 4> neighbors = curChunk.getNeighbors();
    
    chunksToQuery.push_back(&loadedChunks.at(curChunk));
    
    for(const Int3D& n : neighbors) {
        if(loadedChunks.contains(n)) {
            chunksToQuery.push_back(&loadedChunks.at(n));
        }
    }
    
    int numCollisionsQueried = 0;
    
    struct CollisionData {
        Chunk* chunk;
        const CollisionEntity* entity;
    };
    
    std::vector<CollisionData> entitiesCollidedWith;
    
    for(Chunk* chunk : chunksToQuery) {
        std::vector<CollisionEntity*> collisionEntities;
        chunk->resetLineColors();
        
        if(chunk->getCollisionEntitiesAtPositionsWS(playerCollision.getCenterWS(), 2, collisionEntities)) {
            if(collisionEntities.size() > 0) {
                
                for(const CollisionEntity* c : collisionEntities) {
                    if(c->getType() == ECollisionEntityType::RectType) {
                        const CollisionRect* cr = static_cast<const CollisionRect*>(c);
                        bool doesCollide = CollisionChecker::doesCollide(playerCollision, *cr);
                        if(doesCollide) {
                            entitiesCollidedWith.push_back({chunk, c});
                            //chunk->setCollisionVisibility(cr->getId(), true);
                        }
                        
                        chunk->highlightCollision(cr->getId());
                        collides |= doesCollide;
                    }
                }
                
                numCollisionsQueried += collisionEntities.size();
            }
        }
    }
    
    //std::cout << "Num collision entities: " << numCollisionsQueried << std::endl;
    //std::cout << "Collides: " << collides << std::endl;
    
    simd::float3 playerVel = player->getVelocity();
    simd::float3 force {0,0,0};
    
    simd::float3 gravityAcceleration { 0.f, -9.8f, 0.f };
    force += gravityAcceleration;
    
    
    numCollisions = 0;
    
    //collisionPushBackVel = simd::float3{0,0,0};
    //
    bool collidedWithFloor = false;
    if(entitiesCollidedWith.size() > 0) {
        AABB& playerCollisionRef = player->getCollisionRef();
        for(CollisionData& cd : entitiesCollidedWith) {
            if(cd.entity->getType() == ECollisionEntityType::RectType) {
                const CollisionRect* cr = static_cast<const CollisionRect*>(cd.entity);
                
                // clamp the player's aabb to stop intersecting with each collision rect
                // generally: pull out moveable entities from immovable ones
                bool pulled = CollisionChecker::pullOut(playerCollisionRef, *cr, playerVel);
                if(pulled) {
                    // cd.chunk->highlightCollision(cr->getId());
                    
                    if(simd::equal(cr->normalWS, simd::float3 {0,1,0})) {
                        collidedWithFloor = true;
                    }
                    
                    numCollisions++;
                }
            }
        }
        
        collisionPushBackVel = playerVel - player->getVelocity();
        
        player->setPosition(playerCollisionRef.getCenterWS() + simd::float3{0, 0.75, 0});
        player->setVelocity(playerVel);
    }
    else {
        collisionPushBackVel = simd::float3{0,0,0};
    }
    
    if(collidedWithFloor) {
        force -= gravityAcceleration;
    }
    
    
   // player->setVelocity(player->getVelocity() * simd::float3{0.95, 1, 0.95});
    
    player->setForce(force);

    
    player->setVelocity(player->getVelocity() + player->getForce() * deltaTime);
    player->setPosition(player->getPosition() + player->getVelocity() * deltaTime);
}


void MTLEngine::bindShadowMapFrustumWithMainCamera(float zAlphaStart, float zAlphaEnd, Camera& shadowCam) {
    // TODO: should be uniform so we can modify in runtime (fragment shader needs this value too)
    const float3 lightDir = {1, -1, 0.25};
    
    std::array<float3, 8> frustumVertices = camera.calculateFrustumVertices(zAlphaStart, zAlphaEnd);
    
    // TODO:
    // go with the axis aligned method, taking min/max of all frustum vertices.
    // an oriented shadow orthographic projection, will start omitting
    // significant structures in the shadow calculation as the camera turns.
    //
    // With an axis-aligned box, the accuracy is independent of camera orientation
    float minX = std::numeric_limits<float>::max();
    float maxX = std::numeric_limits<float>::lowest();
    float minY = std::numeric_limits<float>::max();
    float maxY = std::numeric_limits<float>::lowest();
    float minZ = std::numeric_limits<float>::max();
    float maxZ = std::numeric_limits<float>::lowest();
    
    float3 center = {0,0,0};
    for(auto it = std::begin(frustumVertices); it != std::end(frustumVertices); ++it) {
        const float3 fv = *it;
        center = center + fv;
    }
    center = center / (float) frustumVertices.size();
    shadowCam.setPosition(center);
    
    // transform frustum verices to light-space, not world.
    // The "most-left" without lightViewMat would be in world space,
    // but we want to orient the frustum wrt the light direction
    float4x4 lightViewMat = shadowCam.calculateViewMatrix();
    
    for(auto it = std::begin(frustumVertices); it != std::end(frustumVertices); ++it) {
        const float3 fv = *it;
        const float4 tfv = lightViewMat * make_float4(fv.x, fv.y, fv.z, 1.0f);
        
        
        if(tfv.x < minX) {
            minX = tfv.x;
        }
        if(tfv.x > maxX) {
            maxX = tfv.x;
        }
        if(tfv.y < minY) {
            minY = tfv.y;
        }
        if(tfv.y > maxY) {
            maxY = tfv.y;
        }
        if(tfv.z < minZ) {
            minZ = tfv.z;
        }
        if(tfv.z > maxZ) {
            maxZ = tfv.z;
        }
    }
    
    const float inflateFactor = 1.25f;
    
    // TODO: make sure ortho frustum contains entire chunk height, we're estimating right now
    const float inflateFactorZ = 10.f;

    
    shadowCam.setPosition(center);
    shadowCam.setOrthoLRBTNF(minX * inflateFactor,
                             maxX * inflateFactor,
                             minY * inflateFactor,
                             maxY * inflateFactor,
                             minZ * inflateFactorZ,
                             maxZ * inflateFactorZ);
    
    shadowCam.setForwardVectorDirect(lightDir);
}

void MTLEngine::updateUniforms() {
 
    auto syncCameraWithBuffer = [](const Camera& cam, MTL::Buffer* buffer) {
        float3 camPos = cam.getPosition();
        
        CameraData cd = {
            make_float4(camPos.x, camPos.y, camPos.z, 1.0f),
            make_float4(cam.getNearZ(), cam.getFarZ(), 0, 0),
            cam.calculateViewMatrix(),
            cam.calculateProjectionMatrix(),
            cam.calculateNormalMatrix(),
            inverse(cam.calculateProjectionMatrix()),
            inverse(cam.calculateViewMatrix())
        };
        
        memcpy(buffer->contents(), &cd, sizeof(cd));
    };
    
    float aspect = (metalLayer.frame.size.width / metalLayer.frame.size.height);
    camera.setAspectRatio(aspect);
    debugCamera.setAspectRatio(aspect);
    
    // sync camera matrices
    syncCameraWithBuffer(camera, cameraUB);
    //syncCameraWithBuffer(debugCamera, debugTransformationUB);
    
    for(int i = 0; i < shadowLayerInfos.size(); i++) {
        syncCameraWithBuffer(shadowMapCameras[i], shadowCameraUBs[i]);
    }
    
    {
        const float3 cpos = camera.getPosition();
        TransformationData td;
        td.model = matrix4x4_translation(cpos.x, cpos.y, cpos.z) * matrix4x4_scale(5,5,5);
        td.view = camera.calculateViewMatrix();
        td.perspective = camera.calculateProjectionMatrix();
        
        memcpy(skyboxMVPUB->contents(), &td, sizeof(td));
    }

    RenderState rs;
    rs.useSSAO = enableSSAO;
    rs.useShadowMap = enableShadowMap;
    memcpy(renderStateUB->contents(), &rs, sizeof(rs));
}

void MTLEngine::updateVisibleChunkIndices() {
    // std::cout << fmt::format("curChunk: {}", DebugUtils::stringify_int3(curChunk)) << std::endl;
    const auto oldChunkRenderersSize = chunkRenderers.size();
    
    std::vector<std::shared_ptr<ChunkRenderer>> unseenChunkRenderers;
    std::vector<Int3D> unseenChunks;
    for(const auto[xyz, renderer]: chunkRenderers) {
        // std::cout << fmt::format("xyz: {}", DebugUtils::stringify_tupleInt3(xyz)) << std::endl;
        int x = xyz.x;
        int z = xyz.z;
        if(x < curChunk.x - renderDistance || x > curChunk.x + renderDistance ||
           z < curChunk.z - renderDistance || z > curChunk.z + renderDistance
           ) {
            unseenChunkRenderers.push_back(renderer);
            unseenChunks.push_back(xyz);
        }
    }
    
    /* debug
     
    std::vector<std::tuple<int,int,int>> newlySeenChunks;
    for(int x = curChunk.x - renderDistance ; x <= curChunk.x + renderDistance; x++) {
        for(int z = curChunk.z - renderDistance; z <= curChunk.z + renderDistance; z++) {
            std::tuple<int, int, int> xyz = std::make_tuple(x, 0, z);
            
            if(!chunkRenderers.contains(xyz)) {
                newlySeenChunks.push_back(xyz);
            }
        }
    }
    
    for(auto c: unseenChunks) {
        std::cout << fmt::format("unseen: {}", DebugUtils::stringify_tupleInt3(c)) << std::endl;
    }
    
    for(auto c: newlySeenChunks) {
        std::cout << fmt::format("newly seen: {}", DebugUtils::stringify_tupleInt3(c)) << std::endl;
    }
    
    assert(unseenChunks.size() == newlySeenChunks.size());
     
    */
    
    // for all seen chunks,
    int curUnseenIndex = 0;
    for(int x = curChunk.x - renderDistance ; x <= curChunk.x + renderDistance; x++) {
        for(int z = curChunk.z - renderDistance; z <= curChunk.z + renderDistance; z++) {
            Int3D xyz(x, 0, z);
            
            if(!chunkRenderers.contains(xyz)) {
                assert(curUnseenIndex >= 0 && curUnseenIndex < (int) unseenChunkRenderers.size());
                chunkRenderers.insert({xyz, unseenChunkRenderers[curUnseenIndex]});
                chunkRenderers[xyz]->markDirty();
                curUnseenIndex++;
            }
        }
    }
    
    for(const auto c : unseenChunks) {
        chunkRenderers.erase(c);
    }
    
    assert(chunkRenderers.size() == oldChunkRenderersSize);
    
    
    // sort by dist (furthers -> nearest)
    sortedVisibleChunks.clear();
    
    struct Local {
        Int3D pos;
        float dist;
    };
    
    std::vector<Local> allVisibleChunks;
    float3 cc = curChunk.to_float3();
    
    for(const auto [key, val] : chunkRenderers) {
        Local l;
        l.pos = key;
        l.dist = distance(cc, key.to_float3());
        allVisibleChunks.push_back(l);
    }
    
    struct
    {
        bool operator()(Local a, Local b) const { return a.dist > b.dist; }
    }
    furthestFromCurChunk;
    
    std::sort(allVisibleChunks.begin(), allVisibleChunks.end(), furthestFromCurChunk);
    
    for(const auto l : allVisibleChunks) {
        sortedVisibleChunks.push_back(l.pos);
    }
    
}

Int3D MTLEngine::calculateCurrentChunk(const float3 pos) const {
    // return make_int3((int) pos.x / (int) chunkDims.x, (int) pos.y / (int) chunkDims.y, (int) pos.z / (int) chunkDims.z);
    int x = (int) pos.x / (int) chunkDims.x;
    int y = 0;
    int z = (int) pos.z / (int) chunkDims.z;
    
    if(pos.x < 0) {
        --x;
    }
    if(pos.z < 0) {
        --z;
    }
    return Int3D(x,y,z);
}

void MTLEngine::frameBufferSizeCallback(GLFWwindow* window, int width, int height) {
    MTLEngine* engine = (MTLEngine*)glfwGetWindowUserPointer(window);
    engine->resizeFrameBuffer(width, height);
}

void MTLEngine::glfwKeyCallback(GLFWwindow* window, int key, int scancode, int action, int mods) {
    MTLEngine* engine = (MTLEngine*)glfwGetWindowUserPointer(window);
    engine->handleKeyInput(key, scancode, action, mods);
}

void MTLEngine::glfwMousePosCallback(GLFWwindow* window, double xpos, double ypos) {
    MTLEngine* engine = (MTLEngine*)glfwGetWindowUserPointer(window);
    engine->handleMousePos(xpos, ypos);
}

void MTLEngine::resizeFrameBuffer(int width, int height) {
    std::cout << "Resizing to: " << width << ", " << height << std::endl;
    metalLayer.drawableSize = CGSizeMake(width, height);
    
    if(msaaRenderTarget) {
        msaaRenderTarget->release();
        msaaRenderTarget = nullptr;
    }
    if(depthRenderTarget) {
        depthRenderTarget->release();
        depthRenderTarget = nullptr;
    }
    
    createDepthAndMSAATextures();
    metalDrawable = (__bridge CA::MetalDrawable*)[metalLayer nextDrawable];
    updateRenderPassDescriptor();
}

void MTLEngine::handleKeyInput(int key, int scancode, int action, int mods) {
    
    static std::map<int, EKey> keyMapping {
        {GLFW_KEY_W, EKey::W},
        {GLFW_KEY_A, EKey::A},
        {GLFW_KEY_S, EKey::S},
        {GLFW_KEY_D, EKey::D},
        {GLFW_KEY_Q, EKey::Q},
        {GLFW_KEY_E, EKey::E},
        
        {GLFW_KEY_I, EKey::I},
        {GLFW_KEY_J, EKey::J},
        {GLFW_KEY_K, EKey::K},
        {GLFW_KEY_L, EKey::L},
        {GLFW_KEY_U, EKey::U},
        {GLFW_KEY_O, EKey::O},
        
        {GLFW_KEY_V, EKey::V},
        {GLFW_KEY_B, EKey::B},
        {GLFW_KEY_N, EKey::N},
        {GLFW_KEY_M, EKey::M},
        
        {GLFW_KEY_LEFT, EKey::Left},
        {GLFW_KEY_RIGHT, EKey::Right},
        {GLFW_KEY_UP, EKey::Up},
        {GLFW_KEY_DOWN, EKey::Down},
        {GLFW_KEY_SPACE, EKey::Space},
        
        {GLFW_KEY_LEFT_SHIFT, EKey::LeftShift},
        {GLFW_KEY_RIGHT_SHIFT, EKey::RightShift},
        {GLFW_KEY_ESCAPE, EKey::Escape}
    };
    
    if(!keyMapping.contains(key)) {
        return;
    }
    
    if(action == GLFW_PRESS || action == GLFW_REPEAT) {
        keydownArr[keyMapping[key]] = true;
    }
    else if(action == GLFW_RELEASE){
        keydownArr[keyMapping[key]] = false;
    }
    
    //std::cout << "W: " << keydownArr[0] << " A: " << keydownArr[1] << " S: " << keydownArr[2] << " D: " << keydownArr[3] << std::endl;
}

void MTLEngine::handleMousePos(double xpos, double ypos) {
    if(isInitialMousePos) {
        isInitialMousePos = false;
        curMousePos = make_float2(xpos, ypos);
        prevMousePos = curMousePos;
    }
    else{
        curMousePos = make_float2(xpos, ypos);
    }
}

int MTLEngine::addLine(float3 p1, float3 p2, float thickness, float3 color) {
    if(curLineIndex >= lines.size()) {
       // if(lines.size() >= 800) {
        //    std::cout << "Max lines reached." << std::endl;
        //    return -1;
        //}
        lines.resize(lines.size() * 2);
        //std::cout << "Resizing line array. " << std::endl;
        //lineDataUB->release();
        
        //lineDataUB = metalDevice->newBuffer(lines.size() * sizeof(LineData), MTL::ResourceStorageModeShared);
        
        linesDirty = true;
    }
    
    int index = curLineIndex++;
    
    //std::cout << "Adding line: " << index << std::endl;
    
    // add vertices to make a quad with the specified color to the range lineVertexData[index : index + 5]
    float3 dir = normalize(p2 - p1);

    // add the transform that will transform the quad to stretch from p1 to p2
    float3 center = (p1 + p2) / 2.0f;
    float lineLen = length(p2 - p1);
    
    LineData ld;
    ld.axis = normalize(p2 - p1);
    
    float3 unitX {1,0,0};
    float3 zeroVec {0,0,0};
    
    quatf rotQ(unitX, dir);
    float4x4 rotMat = matrix4x4_identity();
    if(!simd_equal(rotQ.vector.xyz, zeroVec) && !simd_equal(unitX, dir)) {
        rotMat = matrix4x4_rotation(rotQ.angle(), rotQ.axis());
    }
    ld.transform = matrix4x4_translation(center) * rotMat * matrix4x4_scale(lineLen, thickness, 1.0f);
    ld.color = color;
    ld.visible = false;
    
    lines[index] = ld;
    
    linesDirty = true;
    
    return index;
}

void MTLEngine::setLineTransform(int index, float3 p1, float3 p2, float thickness) {
    // add vertices to make a quad with the specified color to the range lineVertexData[index : index + 5]
    float3 dir = normalize(p2 - p1);

    // add the transform that will transform the quad to stretch from p1 to p2
    float3 center = (p1 + p2) / 2.0f;
    float lineLen = length(p2 - p1);
    
    LineData& ld = lines[index];
    ld.axis = normalize(p2 - p1);
    
    float3 unitX {1,0,0};
    float3 zeroVec {0,0,0};
    
    quatf rotQ(unitX, dir);
    float4x4 rotMat = matrix4x4_identity();
    if(!simd_equal(rotQ.vector.xyz, zeroVec) && !simd_equal(unitX, dir)) {
        rotMat = matrix4x4_rotation(rotQ.angle(), rotQ.axis());
    }
    ld.transform = matrix4x4_translation(center) * rotMat * matrix4x4_scale(lineLen, thickness, 1.0f);
    
    linesDirty = true;
}

void MTLEngine::setLineColor(int index, simd::float3 color) {
    LineData& ld = lines[index];
    
    if(!simd_equal(color, ld.color)) {
        ld.color = color;
        linesDirty = true;
    }
}

void MTLEngine::setLineVisibility(int index, bool isVisible) {
    LineData& ld = lines[index];
    
    if(isVisible != ld.visible) {
        ld.visible = isVisible;
        linesDirty = true;
    }
}

void MTLEngine::commitLines() {
    visibleLines.clear();
    
    int numVisible = 0;
    for(LineData& ld : lines) {
        if(ld.visible) {
            visibleLines.push_back(ld);
            numVisible++;
        }
    }
    
    if(numVisible > lineDataUBSize) {
        lineDataUBSize = numVisible * 2;
        
        lineDataUB->release();
        
        lineDataUB = metalDevice->newBuffer(lineDataUBSize * sizeof(LineData), MTL::ResourceStorageModeShared);
    }
    
    memcpy(lineDataUB->contents(), visibleLines.data(), visibleLines.size() * sizeof(LineData));
}

void MTLEngine::addPointLight(float3 posWS, float3 color) {
    if(curPointLightIndex >= pointLights.size()) {
        return;
    }
    std::lock_guard<std::mutex> guard(pointLightArrMutex);
    int index = curPointLightIndex++;
    
    
    float constant  = 1.0;
    float linear    = 0.22;
    float quadratic = 0.2;
    
    float4 lightColor = make_float4(color.x, color.y, color.z, 1.0f);
        
    float lightMax  = std::fmaxf(std::fmaxf(lightColor.r, lightColor.g), lightColor.b);
    float radius    =
      (-linear +  std::sqrtf(linear * linear - 4 * quadratic * (constant - (256.0 / 5.0) * lightMax)))
      / (2 * quadratic);
        
    LightVolumeData newLight;
    newLight.localToWorld = matrix4x4_translation(posWS.x, posWS.y, posWS.z) * matrix4x4_scale(radius, radius, radius);
    newLight.color = lightColor;
    
    pointLights[index] = newLight;

    memcpy(lightVolumeInstanceUB->contents(), pointLights.data(), pointLights.size() * sizeof(LightVolumeData));
}



void MTLEngine::guiNodeHierarchy(AssimpNode root, bool shouldPop) {
    const auto nodes = playerNodeManager.getNodes();
    const auto bones = playerNodeManager.getBones();
    
    bool hasChildren = root.children.size() > 0;
    
    if(hasChildren) {
        ImGui::TreePush(root.name.c_str());
    }
    
    ImGui::Text("%s [%d] (%s)", root.name.c_str(), root.id, root.parent == -1? "root" : nodes[root.parent].name.c_str());
    int bid = playerNodeManager.getBoneId(root.name);
    if(bid != -1) {
        ImGui::Text("Bone %d", bid);
    }
    
    bool isAnimated = animator.nodesBeingAnimated.contains(root.id);
    if(isAnimated) {
        ImGui::Text("Animated!");
    }
    
    {
        const auto m = root.relativeTransform.columns;
        ImGui::Text("(%f,%f,%f,%f)\n(%f,%f,%f,%f)\n(%f,%f,%f,%f)\n(%f,%f,%f,%f)\n ",
                         m[0][0], m[0][1], m[0][2], m[0][3],
                        m[1][0], m[1][1], m[1][2], m[1][3],
                        m[2][0], m[2][1], m[2][2], m[2][3],
                        m[3][0], m[3][1], m[3][2], m[3][3]);
    }
    
    /*
    int bid = playerNodeManager.getBoneId(root.name);
    if(bid != -1) {
        const auto m = inverse(bones[bid].offsetMat).columns;
        ImGui::Text("\n(%f,%f,%f,%f)\n(%f,%f,%f,%f)\n(%f,%f,%f,%f)\n(%f,%f,%f,%f)\n ",
                         m[0][0], m[0][1], m[0][2], m[0][3],
                        m[1][0], m[1][1], m[1][2], m[1][3],
                        m[2][0], m[2][1], m[2][2], m[2][3],
                        m[3][0], m[3][1], m[3][2], m[3][3]);
    }
    */
    
    for(int i = 0 ; i < root.children.size(); i++) {
        bool childShouldPop = i == root.children.size() - 1;
        int cid = root.children[i];
        guiNodeHierarchy(nodes[cid], childShouldPop);
    }
    
    if(shouldPop) {
        ImGui::TreePop();
    }
}
