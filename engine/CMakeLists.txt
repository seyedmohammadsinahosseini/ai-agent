cmake_minimum_required(VERSION 3.15)
project(aiterm_engine LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(pybind11 REQUIRED)

pybind11_add_module(aiterm_engine bindings.cpp)

if (WIN32)
    target_compile_definitions(aiterm_engine PRIVATE AITERM_WINDOWS=1)
endif()
