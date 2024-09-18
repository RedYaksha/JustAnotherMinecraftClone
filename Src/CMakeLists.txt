cmake_minimum_required(VERSION 3.24)

set (CMAKE_CXX_STANDARD 20)

set(CMAKE_EXPORT_COMPILE_COMMANDS 1)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
file(COPY ${PROJECT_SOURCE_DIR}/Assets DESTINATION ${CMAKE_BINARY_DIR}/bin)

set( SOURCE_FILES
	Core/Mesh/Animator.cpp
	Core/Mesh/AssimpNodeManager.cpp
	Core/Camera.cpp
	Core/Texture.cpp
	MtlImplementation.cpp
	Gameplay/Player.cpp
	WorldGeneration/PerlinNoiseGenerator.cpp	
	Engine.mm
	main.mm
	Core/ChunkRenderer.cpp

	${THIRD_PARTY_DIR}/Apple/AAPLMathUtilities.cpp
	${THIRD_PARTY_DIR}/stb/stbi_image.cpp

	${THIRD_PARTY_DIR}/imgui/imgui.cpp
	${THIRD_PARTY_DIR}/imgui/imgui_impl_metal.mm
	${THIRD_PARTY_DIR}/imgui/imgui_impl_glfw.cpp
	${THIRD_PARTY_DIR}/imgui/imgui_tables.cpp
	${THIRD_PARTY_DIR}/imgui/imgui_draw.cpp
	${THIRD_PARTY_DIR}/imgui/imgui_widgets.cpp
    )

add_executable(${PROJECT_NAME} ${SOURCE_FILES})

    
target_include_directories(
    ${PROJECT_NAME} PRIVATE ${PROJECT_SOURCE_DIR}/Src
			    ${THIRD_PARTY_DIR}
			    ${THIRD_PARTY_DIR}/stb
			    ${THIRD_PARTY_DIR}/assimp/include
			    ${THIRD_PARTY_DIR}/Apple
			    ${THIRD_PARTY_DIR}/metal-cpp
			    ${THIRD_PARTY_DIR}/stb
			    ${THIRD_PARTY_DIR}/glfw-3.4/include
			    ${THIRD_PARTY_DIR}/imgui
			    ${THIRD_PARTY_DIR}/concurrentqueue
)

target_link_libraries(
    ${PROJECT_NAME} 
		    assimp
		    "-framework Metal"
		    "-framework MetalKit"
		    "-framework AppKit"
		    "-framework Foundation"
		    "-framework QuartzCore"
		    "-framework AppKit"
		    "-framework IOKit"
		    ${THIRD_PARTY_DIR}/glfw-3.4/lib-universal/libglfw3.a
)

