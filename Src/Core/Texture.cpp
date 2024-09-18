#include "Texture.hpp"

Texture::Texture(const char* filepath, MTL::Device* metalDevice, int profile)
: device(metalDevice) {

    if(profile == STBI_rgb) {
        stbi_set_flip_vertically_on_load(false);
    }
    else {
        stbi_set_flip_vertically_on_load(true);
    }
    unsigned char* image = stbi_load(filepath, &width, &height, &channels, (unsigned int) profile);
    
    // assert(image != NULL);
    
    bool is3Channel = false;
    
    // Metal has no texture type support for 3-channels, this is a workaround.
    // just re-creating the image data and adding a dummy 0xFF for the alpha channel
    //
    // NOTE: iterating like this flips the image - that's why we don't set_flip_vertically_on_load
    //       in this case.
    std::vector<unsigned char> tmp;
    if(profile == STBI_rgb) {
        tmp.reserve(width * height * channels);
        for(int j=0 ; j < width * height * channels; j += channels){
            tmp.push_back(image[j]);
            tmp.push_back(image[j + 1]);
            tmp.push_back(image[j + 2]);
            tmp.push_back((char) 0xFF);
        }
        is3Channel = true;
    }

    MTL::TextureDescriptor* textureDescriptor = MTL::TextureDescriptor::alloc()->init();
    textureDescriptor->setPixelFormat(MTL::PixelFormatRGBA8Unorm);
    textureDescriptor->setWidth(width);
    textureDescriptor->setHeight(height);

    texture = device->newTexture(textureDescriptor);

    MTL::Region region = MTL::Region(0, 0, 0, width, height, 1);
    NS::UInteger bytesPerRow = 4 * width;

    texture->replaceRegion(region, 0, is3Channel? tmp.data() : image, bytesPerRow);

    textureDescriptor->release();
    stbi_image_free(image);
}

Texture::~Texture() {
    texture->release();
}

