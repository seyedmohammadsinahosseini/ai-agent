cmake_minimum_required(VERSION 3.15)
project(aiterm_engine LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if (WIN32)
    # Prevent Windows SDK min/max macros from corrupting standard-library calls
    # in pybind11 or engine headers, regardless of include order.
    add_compile_definitions(NOMINMAX WIN32_LEAN_AND_MEAN)
endif()

set(PYBIND11_FINDPYTHON ON)
find_package(Python COMPONENTS Interpreter Development REQUIRED)
find_package(pybind11 REQUIRED)

pybind11_add_module(aiterm_engine bindings.cpp)

if (WIN32)
    target_compile_definitions(aiterm_engine PRIVATE AITERM_WINDOWS=1)
endif()

include(CTest)
if (BUILD_TESTING)
    add_executable(risk_classifier_test tests/risk_classifier_test.cpp)
    target_include_directories(risk_classifier_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    add_test(NAME risk_classifier_test COMMAND risk_classifier_test)

    add_executable(pty_session_test tests/pty_session_test.cpp)
    target_include_directories(pty_session_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    find_package(Threads REQUIRED)
    target_link_libraries(pty_session_test PRIVATE Threads::Threads)
    if (UNIX AND NOT APPLE)
        target_link_libraries(pty_session_test PRIVATE util)
    endif()
    add_test(NAME pty_session_test COMMAND pty_session_test)
endif()
