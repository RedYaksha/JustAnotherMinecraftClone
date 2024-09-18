//
//  VoxelTypes.hpp
//  MetalTutorial
//
//  Created by Ronnin Padilla on 8/22/24.
//
#include <simd/simd.h>
#include <array>
#include <string>
#include "Gameplay/Physics/PhysicsCoreTypes.hpp"
#include "EngineInterface.hpp"
#include "Core/Drawables.hpp"
#include "simd/simd.h"

struct Int3D {
    typedef int IndexType;
public:
    Int3D()
    : x(-1), y(-1), z(-1) {}
    
    Int3D(IndexType x, IndexType y, IndexType z)
    : x(x), y(y), z(z)
    {}
    
    bool operator==(const Int3D& other) const {
        return (
                x == other.x &&
                y == other.y &&
                z == other.z
        );
    }
    
    Int3D operator+(const Int3D& other) const {
        return Int3D(x + other.x, y + other.y, z + other.z);
    }
    
    Int3D operator-(const Int3D& other) const {
        return Int3D(x - other.x, y - other.y, z - other.z);
    }
    
    Int3D operator*(const Int3D& other) const {
        return Int3D(x * other.x, y * other.y, z * other.z);
    }
    
    Int3D operator*(const int s) const {
        return Int3D(x * s, y * s, z * s);
    }
    
    // https://stackoverflow.com/a/9789782
    // need strict orderering for .contains() to work
    bool operator<(const Int3D& other) const {
        if(x < other.x) return true; else if(x > other.x) return false;
        else if(y < other.y) return true; else if(y > other.y) return false;
        else if(z < other.z) return true; else if(z > other.z) return false;
        return false;
    }
    
    Int3D delta(IndexType dx, IndexType dy, IndexType dz) const {
        return Int3D(x + dx, y + dy, z + dz);
    }
    
    simd::int3 to_int3() const {
        return simd::make_int3(x, y, z);
    }
    
    simd::float3 to_float3() const {
        return simd::make_float3(x,y,z);
    }
    
    std::array<Int3D, 4> getNeighbors() const {
        return {
            delta(1, 0, 0),
            delta(-1, 0, 0),
            delta(0, 0, 1),
            delta(0, 0, -1),
        };
    }
    
    std::array<Int3D, 6> getAllNeighbors() const {
        return {
            delta(1, 0, 0),
            delta(-1, 0, 0),
            delta(0, 0, 1),
            delta(0, 0, -1),
            delta(0, -1, 0),
            delta(0, 1, 0),
        };
    }
  
    IndexType x;
    IndexType y;
    IndexType z;
};

template <>
struct std::hash<Int3D>
{
  std::size_t operator()(const Int3D& k) const
  {
    using std::size_t;
    using std::hash;
    using std::string;

    // Compute individual hash values for first,
    // second and third and combine them using XOR
    // and bit shifting:

    return ((hash<int>()(k.x)
             ^ (hash<int>()(k.y) << 1)) >> 1)
             ^ (hash<int>()(k.z) << 1);
  }
    
};

enum class EVoxelType : char {
    None = 0,
    Grass = 1,
    Stone = 2,
    Dirt = 3,
    Water = 4,
    Lamp = 5,
};

struct VoxelAtlasEntry {
    
    VoxelAtlasEntry() = default;
    VoxelAtlasEntry(int ind)
    : front(ind), back(ind), left(ind), right(ind), top(ind), bottom(ind)
    {}
    VoxelAtlasEntry(int front, int back, int left, int right, int top, int bottom)
    : front(front), back(back), left(left), right(right), top(top), bottom(bottom)
    {}
    VoxelAtlasEntry(int fb, int lr, int tb)
    : front(fb), back(fb), left(lr), right(lr), top(tb), bottom(tb)
    {}
    VoxelAtlasEntry(int top, int other)
    : front(other), back(other), left(other), right(other), top(top), bottom(other)
    {}
    
    int front;
    int back;
    int left;
    int right;
    int top;
    int bottom;
};

class Chunk {
    
public:
    Chunk(IEngine* engine)
    : engine(engine)
    {}
    
    void setPosition(Int3D inPosition) {
        position = inPosition;
    }
    
    void setDimensions(Int3D inDims) {
        dims = {inDims.x, inDims.y, inDims.z};
        
        const float volume = inDims.x * inDims.y * inDims.z;
        
        voxels.clear();
        voxels.resize(volume, EVoxelType::None);
        
        collisionGrid.clear();
        collisionGrid.resize(volume, std::vector<CollisionEntity*>());
    }
    
    void setIndex(Int3D inIndex) { index = inIndex; }
    void setIndex(int x, int y, int z) { index = Int3D(x,y,z); }
    
    EVoxelType getVoxel(Int3D coords) const {
        return voxels[coordsToRawIndex(coords)];
    }
    
    void setVoxel(Int3D coords, EVoxelType inType) {
	int rawInd = coordsToRawIndex(coords);
	if(rawInd != -1) {
	    voxels[coordsToRawIndex(coords)] = inType;
	}
    }
    
    void setVoxelLightColor(Int3D coords, simd::float3 color) {
        voxelLightColor[coords] = color;
    }

    void clearCollisionRects() {
        const float volume = dims.x * dims.y * dims.z;

	collisionRects.clear();
	collisionGrid.clear();
        collisionGrid.resize(volume, std::vector<CollisionEntity*>());
    }
    
    // positionsLS - positions local to this chunk
    void addCollisionRect(std::array<simd::float3, 4> positionsLS, simd::float3 normal) {
        // create a new CollisionRect using world space positions
        std::array<simd::float3, 4> positionsWS = positionsLS;
        for(auto& p : positionsWS) {
            p += position.to_float3();
        }
        
        CollisionRect* cRect = new CollisionRect(positionsWS, normal);
        collisionRects.push_back(cRect);
        
        cRect->setId((int) collisionIdToDebugRect.size());
        
        simd::float3 red {1,1,1};
        simd::float3 green {0,1,0};
        simd::float3 blue {0,0,1};
        
        simd::float3 color = red;
        if(cRect->normal == EAxis::Y) {
           // color = green;
        }
        else if(cRect->normal == EAxis::Z) {
           // color = blue;
        }
        
        //DebugRect* dr = new DebugRect(engine, *cRect, color);
        //collisionIdToDebugRect.insert({cRect->getId(), dr});
        // dr->setVisibility(true);
        
        // for each vertex in local space, find each voxel it's in,
        // - add reference to CollisionRect in the collisionGrid for the area
        //   the vertices span over
        float maxFloat = std::numeric_limits<float>::max();
        float minFloat = std::numeric_limits<float>::lowest();
        
        simd::float3 minPos { maxFloat, maxFloat, maxFloat };
        simd::float3 maxPos { minFloat, minFloat, minFloat };
        
        for(const simd::float3& p : positionsLS) {
            minPos.x = std::min(p.x, minPos.x);
            maxPos.x = std::max(p.x, maxPos.x);
            minPos.y = std::min(p.y, minPos.y);
            maxPos.y = std::max(p.y, maxPos.y);
            minPos.z = std::min(p.z, minPos.z);
            maxPos.z = std::max(p.z, maxPos.z);
        }
        
        //std::cout << "addCollisionRect -- " << std::endl;
        //std::cout << "    minPos: " << minPos.x << ", " << minPos.y << ", " << minPos.z << std::endl;
        //std::cout << "    maxPos: " << maxPos.x << ", " << maxPos.y << ", " << maxPos.z << std::endl;
        
        for(int x = minPos.x; x <= maxPos.x; x++) {
            for(int y = minPos.y; y <= maxPos.y; y++) {
                for(int z = minPos.z; z <= maxPos.z; z++) {
                    // clamp indices [0, dim - 1]
                    int xInd = std::max(std::min(x, dims.x - 1), 0);
                    int yInd = std::max(std::min(y, dims.y - 1), 0);
                    int zInd = std::max(std::min(z, dims.z - 1), 0);
                    
                    int ind = coordsToRawIndex({xInd,yInd,zInd});
                    assert(ind != -1);
                    collisionGrid[ind].push_back(cRect);
                }
            }
        }
    }
    
    Int3D getDimensions() const { return dims; }
    Int3D getPosition() const { return position; }
    Int3D getIndex() const { return index; }
    
    simd::float3 getPositionAsFloat3() const { return simd::make_float3(position.x, position.y, position.z); }
    simd::float4 getPositionAsFloat4() const { return simd::make_float4(position.x, position.y, position.z, 0.0f);}
    const std::map<Int3D, simd::float3>& getVoxelLightColorMap() const { return voxelLightColor; }
    const std::vector<CollisionRect*>& getCollisionRects() const { return collisionRects; }

    Int3D getCoordsFromPositionWS(simd::float3 posWS) const {
        simd::float3 posLocal = posWS - getPositionAsFloat3();
        Int3D coords = Int3D {(int) posLocal.x, (int) posLocal.y, (int) posLocal.z};

	return coords;
    }

    simd::float3 getVoxelPositionWS(Int3D coords) {
	return coords.to_float3() + getPositionAsFloat3();
    }
    
    const bool getCollisionEntitiesAtPositionsWS(simd::float3 posWS, int radius, std::vector<CollisionEntity*>& outVec) const {
        std::vector<CollisionEntity*> ret;
        
        Int3D coords = getCoordsFromPositionWS(posWS);
        
        bool collidesWithAny = false;
        
        for(int x = coords.x - radius; x <= coords.x + radius; x++) {
            for(int y = coords.y - radius; y <= coords.y + radius; y++) {
                for(int z = coords.z - radius; z <= coords.z + radius; z++) {
                    int rawInd = coordsToRawIndex({x,y,z});
                    if(rawInd != -1) {
                        collidesWithAny = true;
                        std::vector<CollisionEntity*> queried = collisionGrid[rawInd];
                        ret.insert(ret.end(), queried.begin(), queried.end());
                    }
                }
            }
        }
        
        //std::cout << "returning collisions: " << ret.size() << std::endl;
        outVec = ret;
        return collidesWithAny;
    }
    
    const std::vector<CollisionEntity*>& getCollisionEntitiesAtCoords(Int3D coords) const {
        return collisionGrid[coordsToRawIndex(coords)];
    }
    
    void resetLineColors() {
       for(const auto& [id, dr] : collisionIdToDebugRect) {
       //     dr->setColor(simd::float3{0,0,1});
       }
    }
    
    void setCollisionVisibility(int id, bool val) {
       //collisionIdToDebugRect.at(id)->setVisibility(val);
    }
    
    void highlightCollision(int id) {
       //collisionIdToDebugRect.at(id)->setColor(simd::float3{1,0,0});
    }

    void removeVoxel(Int3D coords) {
	setVoxel(coords, EVoxelType::None);
    }
    
private:
    int coordsToRawIndex(Int3D coords) const {
        if(coords.x < 0 || coords.x >= dims.x ||
           coords.y < 0 || coords.y >= dims.y ||
           coords.z < 0 || coords.z >= dims.z) {
            return -1;
        }
        
        // simplifies to:
        // dims[0] * (z + dims[2] * y) + x
        return (coords.y * dims.x * dims.z) + (coords.x + dims.x * coords.z);
    }
    
    Int3D dims;
    Int3D position;
    std::vector<EVoxelType> voxels;
    Int3D index;
    std::map<Int3D, simd::float3> voxelLightColor;
    
    std::vector< std::vector<CollisionEntity*> > collisionGrid;
    std::vector<CollisionRect*> collisionRects;
    
    IEngine* engine;
    std::map<int, DebugRect*> collisionIdToDebugRect;
};

