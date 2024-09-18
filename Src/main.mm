//
//  main.cpp
//  MetalTutorial
//
//  Created by Ronnin Padilla on 7/19/24.
//
#include "Engine.hpp"

int main(int argc, const char * argv[]) {
    MTLEngine engine;
    engine.init();
    engine.run();
    engine.cleanup();
    
    return 0;
}
