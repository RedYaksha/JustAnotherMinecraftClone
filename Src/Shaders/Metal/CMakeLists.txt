cmake_minimum_required(VERSION 3.24)

list(APPEND MetalSourceFileNames "Deferred" "DeferredMesh" "GaussianBlur" "Lines" "PostProcess" "SSAO" "Shadow" "Skybox")

list(TRANSFORM MetalSourceFileNames APPEND ".metal" OUTPUT_VARIABLE MetalSources)
list(TRANSFORM MetalSourceFileNames APPEND ".ir" OUTPUT_VARIABLE MetalIRs)
list(TRANSFORM MetalIRs PREPEND ${CMAKE_CURRENT_BINARY_DIR}/ OUTPUT_VARIABLE MetalIRsFullPath)

set(METAL_SOURCE_DIR ${PROJECT_SOURCE_DIR}/Src/Shaders/Metal)


# compile each .metal source file into intermediate representation (.ir)
foreach(X IN LISTS MetalSourceFileNames)

    add_custom_command(
	OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/${X}.ir"

	COMMAND xcrun -sdk macosx metal 
		    -o "${CMAKE_CURRENT_BINARY_DIR}/${X}.ir" 
		    -c "${CMAKE_CURRENT_SOURCE_DIR}/${X}.metal"

		    # metal shader include search paths
		    -I ${PROJECT_SOURCE_DIR}/Src

	WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
	COMMENT "Compiling Metal Shader: ${X}.metal"
	VERBATIM
    )
endforeach()


set(METALLIB_FILE ${CMAKE_BINARY_DIR}/bin/JAMC.metallib)

# combine all (.ir) files into 1 .metallib which will be used in the final program
add_custom_command(
    OUTPUT ${METALLIB_FILE}

    COMMAND xcrun -sdk macosx metallib
		-o ${METALLIB_FILE}
		${MetalIRsFullPath}

    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"

    DEPENDS ${MetalIRsFullPath}

    COMMENT "Creating Metal Lib"
    VERBATIM
)

add_custom_target(MetalLibrary DEPENDS ${METALLIB_FILE})
