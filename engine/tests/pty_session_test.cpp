#include <iostream>
#include <string>
#include <functional>
#include <stdexcept>
#include <cstring>
#include <thread>
#include <mutex>
#include <unordered_map>
#include <memory>

// Simulate the function-like min macro exposed by windows.h after standard
// headers were already included. Engine code must not invoke that macro.
#define min(a, b) windows_min_macro_must_not_expand_here
#include "../pty_session.hpp"
#undef min

int main() {
#if defined(_WIN32)
    const std::string command = "Write-Output pty-ok";
#else
    const std::string command = "printf pty-ok";
#endif

    auto result = aiterm::PtySession::run(command, nullptr, 10);
    if (result.exit_code != 0 || result.output.find("pty-ok") == std::string::npos) {
        std::cerr << "PTY smoke command failed; exit=" << result.exit_code
                  << " output=" << result.output << "\n";
        return 1;
    }
    std::cout << "pty_session_test: passed\n";
    return 0;
}
