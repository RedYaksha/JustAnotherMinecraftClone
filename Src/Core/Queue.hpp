#pragma once
#include <queue>

// A simple thread-safe queue;
template <typename T>
class Queue {
public:


private:
    std::queue<T> queue;
};
