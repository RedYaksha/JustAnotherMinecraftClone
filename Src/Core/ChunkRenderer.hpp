#pragma once
#include <map>
#include "Metal/Metal.hpp"
#import "Voxel/VoxelTypes.hpp"

struct ChunkRenderData {
    MTL::Buffer* buffer;
    int numVertices;
};

class ChunkRenderer {
    
public:
    static std::map<Int3D, ChunkRenderData> cachedChunkBuffers;
    static std::map<Int3D, ChunkRenderData> cachedTransparentChunkBuffers;
    
    ChunkRenderer(): vertexBuffer(nullptr), dirty(true), numVertices(-1) {}
    
    void render(const Chunk& chunk, MTL::RenderCommandEncoder* renderCommandEncoder, MTL::Device* metalDevice, int index);
    void renderTransparent(const Chunk& chunk, MTL::RenderCommandEncoder* renderCommandEncoder);
    void markDirty() {
        dirty = true;
        transparentDirty = true;
    }
    bool isDirty() const { return dirty; }
    
private:
    MTL::Buffer* vertexBuffer;
    ChunkRenderData transparentRenderData;
    bool dirty;
    bool transparentDirty;
    int numVertices;
};
