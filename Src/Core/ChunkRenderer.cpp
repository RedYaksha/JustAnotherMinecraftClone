#include "ChunkRenderer.hpp"

std::map<Int3D, ChunkRenderData> ChunkRenderer::cachedChunkBuffers = std::map<Int3D, ChunkRenderData>();

std::map<Int3D, ChunkRenderData> ChunkRenderer::cachedTransparentChunkBuffers = std::map<Int3D, ChunkRenderData>();


void ChunkRenderer::render(const Chunk& chunk, MTL::RenderCommandEncoder* renderCommandEncoder, MTL::Device* metalDevice, int index) {
    if(!vertexBuffer || dirty) {
        Int3D chunkIndex = chunk.getIndex();
        
        if(cachedChunkBuffers.contains(chunkIndex)) {
            ChunkRenderData rd = cachedChunkBuffers[chunkIndex];
            vertexBuffer = rd.buffer;
            numVertices = rd.numVertices;
            dirty = false;
        }
    }
    
    renderCommandEncoder->setVertexBuffer(vertexBuffer, 0, 0);
    
    
    MTL::PrimitiveType typeTriangle = MTL::PrimitiveTypeTriangle;
    NS::UInteger vertexStart = 0;
    NS::UInteger vertexCount = numVertices;
    renderCommandEncoder->drawPrimitives(typeTriangle, vertexStart, vertexCount);
}

void ChunkRenderer::renderTransparent(const Chunk& chunk, MTL::RenderCommandEncoder* renderCommandEncoder) {
    if(transparentDirty || !transparentRenderData.buffer) {
        Int3D chunkIndex = chunk.getIndex();
        
        if(cachedTransparentChunkBuffers.contains(chunkIndex)) {
            transparentRenderData = cachedTransparentChunkBuffers[chunkIndex];
            transparentDirty = false;
        }
    }
    
    if(transparentDirty || !transparentRenderData.buffer || transparentRenderData.numVertices == 0) {
        return;
    }
    
    renderCommandEncoder->setVertexBuffer(transparentRenderData.buffer, 0, 0);

    MTL::PrimitiveType typeTriangle = MTL::PrimitiveTypeTriangle;
    NS::UInteger vertexStart = 0;
    NS::UInteger vertexCount = transparentRenderData.numVertices;
    renderCommandEncoder->drawPrimitives(typeTriangle, vertexStart, vertexCount);
}
