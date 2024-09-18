cmake_minimum_required(VERSION 3.24)
project(JustAnotherMinecraftClone)

set(THIRD_PARTY_DIR ${PROJECT_SOURCE_DIR}/ThirdParty)

add_subdirectory(${THIRD_PARTY_DIR}/zlib)
add_subdirectory(${THIRD_PARTY_DIR}/assimp)

# todo - glfw from source 

add_subdirectory(Src/Shaders/Metal)
add_subdirectory(Src)

add_dependencies(${PROJECT_NAME} MetalLibrary)
