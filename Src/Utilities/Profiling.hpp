//
//  Timer.hpp
//  MetalTutorial
//
//  Created by Ronnin Padilla on 8/22/24.
//
#include <string>
#include <chrono>
#include <iostream>

class Timer {
public:
    Timer(std::string contextName, bool shouldAutoPrint=true)
    : contextName(contextName), shouldAutoPrint(shouldAutoPrint) {
        // Step 2: Capture the start time
        start = std::chrono::high_resolution_clock::now();
    }
    
    float getDuration() const {
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);
        return duration.count();
    }
    
    ~Timer() {
        if(!shouldAutoPrint)
            return;
        std::cout << contextName << " completed in " << getDuration() << " ms" << std::endl;
    }
    
private:
    std::chrono::steady_clock::time_point start;
    std::string contextName;
    bool shouldAutoPrint;
};
