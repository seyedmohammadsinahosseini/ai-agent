#include <iostream>
#include <string>
#include "../pty_session.hpp"

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
