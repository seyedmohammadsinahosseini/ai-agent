#pragma once
// pty_session.hpp
//
// Cross-platform pseudo-terminal command execution.
//
// - On Windows (the real product target): implemented with the Windows
//   Pseudo Console API (ConPTY: CreatePseudoConsole + CreateProcess with an
//   extended STARTUPINFOEX attribute list). This is the same mechanism
//   Windows Terminal itself uses.
// - On Linux/macOS (used only to develop/test this project outside Windows):
//   implemented with POSIX forkpty so the same behavior ("run a command,
//   stream its output live, and be able to kill it") can be exercised
//   without a Windows machine.
//
// Both implementations expose the same three static methods so the rest of
// the engine (risk_classifier.hpp, bindings.cpp) never needs to know which
// platform it's running on.

#include <string>
#include <functional>
#include <stdexcept>
#include <cstring>
#include <thread>
#include <mutex>
#include <unordered_map>
#include <memory>

#if defined(_WIN32)
    // ==================== Windows (ConPTY) ====================
    #include <windows.h>
    #include <vector>
    #include <atomic>
#else
    // ==================== POSIX (Linux/macOS dev/test builds) ====================
    #include <pty.h>
    #include <unistd.h>
    #include <sys/wait.h>
    #include <fcntl.h>
    #include <cerrno>
    #include <csignal>
#endif

namespace aiterm {

struct ExecResult {
    std::string output;
    int exit_code = -1;
};

#if defined(_WIN32)
// ============================================================================
//  WINDOWS IMPLEMENTATION (ConPTY)
// ============================================================================

namespace win_detail {

struct PtyProcess {
    HPCON hpc = nullptr;
    HANDLE hProcess = nullptr;
    HANDLE hThread = nullptr;
    HANDLE hPipeIn = nullptr;   // write end (our side) -> ConPTY input
    HANDLE hPipeOut = nullptr;  // read end (our side) <- ConPTY output
    std::atomic<bool> killed{false};
};

inline std::mutex& registryMutex() {
    static std::mutex m;
    return m;
}
inline std::unordered_map<int64_t, std::shared_ptr<PtyProcess>>& registry() {
    static std::unordered_map<int64_t, std::shared_ptr<PtyProcess>> r;
    return r;
}

inline std::wstring toWide(const std::string& s) {
    if (s.empty()) return std::wstring();
    int len = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), nullptr, 0);
    std::wstring result(len, 0);
    MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), &result[0], len);
    return result;
}

inline std::string toUtf8(const wchar_t* buf, DWORD len) {
    if (len == 0) return std::string();
    int size = WideCharToMultiByte(CP_UTF8, 0, buf, (int)len, nullptr, 0, nullptr, nullptr);
    std::string result(size, 0);
    WideCharToMultiByte(CP_UTF8, 0, buf, (int)len, &result[0], size, nullptr, nullptr);
    return result;
}

// Launches `command` (via cmd.exe /C so normal shell syntax works) attached
// to a fresh ConPTY, optionally starting inside `working_dir`.
inline std::shared_ptr<PtyProcess> launch(const std::string& command, const std::string& working_dir) {
    auto proc = std::make_shared<PtyProcess>();

    HANDLE inputReadSide = nullptr, inputWriteSide = nullptr;
    HANDLE outputReadSide = nullptr, outputWriteSide = nullptr;

    if (!CreatePipe(&inputReadSide, &inputWriteSide, nullptr, 0))
        throw std::runtime_error("CreatePipe (input) failed");
    if (!CreatePipe(&outputReadSide, &outputWriteSide, nullptr, 0)) {
        CloseHandle(inputReadSide); CloseHandle(inputWriteSide);
        throw std::runtime_error("CreatePipe (output) failed");
    }

    COORD size{ 120, 32 };
    HRESULT hr = CreatePseudoConsole(size, inputReadSide, outputWriteSide, 0, &proc->hpc);

    // The ConPTY duplicates these handles internally; our copies of the ends
    // it now owns can be closed once it starts, keeping our side of the pipe
    // handles for the parent process's own I/O.
    CloseHandle(inputReadSide);
    CloseHandle(outputWriteSide);

    if (FAILED(hr)) {
        CloseHandle(inputWriteSide);
        CloseHandle(outputReadSide);
        throw std::runtime_error("CreatePseudoConsole failed");
    }

    proc->hPipeIn = inputWriteSide;
    proc->hPipeOut = outputReadSide;

    // Build the STARTUPINFOEX with the pseudo console attribute.
    STARTUPINFOEXW siEx{};
    siEx.StartupInfo.cb = sizeof(STARTUPINFOEXW);

    SIZE_T attrListSize = 0;
    InitializeProcThreadAttributeList(nullptr, 1, 0, &attrListSize);
    std::vector<uint8_t> attrListBuffer(attrListSize);
    siEx.lpAttributeList = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(attrListBuffer.data());

    if (!InitializeProcThreadAttributeList(siEx.lpAttributeList, 1, 0, &attrListSize)) {
        ClosePseudoConsole(proc->hpc);
        throw std::runtime_error("InitializeProcThreadAttributeList failed");
    }
    if (!UpdateProcThreadAttribute(siEx.lpAttributeList, 0,
                                    PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
                                    proc->hpc, sizeof(HPCON), nullptr, nullptr)) {
        DeleteProcThreadAttributeList(siEx.lpAttributeList);
        ClosePseudoConsole(proc->hpc);
        throw std::runtime_error("UpdateProcThreadAttribute failed");
    }

    // Run through cmd.exe /C so the user's normal shell syntax (&&, pipes,
    // PowerShell invocations, etc.) works exactly like typing into a real
    // terminal. Callers that want PowerShell semantics should prefix their
    // command with `powershell -NoProfile -Command "..."` (the AI layer does
    // this via the suggested command string itself).
    std::wstring cmdLine = L"cmd.exe /C \"" + toWide(command) + L"\"";
    std::vector<wchar_t> cmdLineBuf(cmdLine.begin(), cmdLine.end());
    cmdLineBuf.push_back(L'\0');

    PROCESS_INFORMATION pi{};
    std::wstring wWorkingDir = working_dir.empty() ? L"" : toWide(working_dir);

    BOOL ok = CreateProcessW(
        nullptr, cmdLineBuf.data(), nullptr, nullptr, FALSE,
        EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
        nullptr,
        wWorkingDir.empty() ? nullptr : wWorkingDir.c_str(),
        &siEx.StartupInfo, &pi);

    DeleteProcThreadAttributeList(siEx.lpAttributeList);

    if (!ok) {
        ClosePseudoConsole(proc->hpc);
        throw std::runtime_error("CreateProcessW failed");
    }

    proc->hProcess = pi.hProcess;
    proc->hThread = pi.hThread;
    return proc;
}

inline void cleanup(const std::shared_ptr<PtyProcess>& proc) {
    if (proc->hpc) ClosePseudoConsole(proc->hpc);
    if (proc->hPipeIn) CloseHandle(proc->hPipeIn);
    if (proc->hPipeOut) CloseHandle(proc->hPipeOut);
    if (proc->hThread) CloseHandle(proc->hThread);
    if (proc->hProcess) CloseHandle(proc->hProcess);
}

} // namespace win_detail

class PtySession {
public:
    static ExecResult run(const std::string& command,
                           std::function<void(const std::string&)> on_chunk = nullptr,
                           int timeout_seconds = 30) {
        return run_in_dir(command, "", on_chunk, timeout_seconds);
    }

    static ExecResult run_in_dir(const std::string& command, const std::string& working_dir,
                                  std::function<void(const std::string&)> on_chunk = nullptr,
                                  int timeout_seconds = 30) {
        ExecResult result;
        auto proc = win_detail::launch(command, working_dir);

        std::string buffer;
        char readBuf[4096];
        DWORD bytesRead = 0;
        DWORD startTick = GetTickCount();

        while (true) {
            DWORD avail = 0;
            if (!PeekNamedPipe(proc->hPipeOut, nullptr, 0, nullptr, &avail, nullptr)) break;
            if (avail > 0) {
                if (!ReadFile(proc->hPipeOut, readBuf, sizeof(readBuf), &bytesRead, nullptr) || bytesRead == 0) break;
                std::string chunkStr(readBuf, bytesRead);
                buffer += chunkStr;
                if (on_chunk) on_chunk(chunkStr);
            } else {
                DWORD waitResult = WaitForSingleObject(proc->hProcess, 20);
                if (waitResult == WAIT_OBJECT_0) {
                    // Drain any remaining buffered output before exiting.
                    if (PeekNamedPipe(proc->hPipeOut, nullptr, 0, nullptr, &avail, nullptr) && avail > 0) continue;
                    break;
                }
            }
            if ((GetTickCount() - startTick) / 1000 > (DWORD)timeout_seconds) {
                TerminateProcess(proc->hProcess, 1);
                buffer += "\n[timeout: command killed after " + std::to_string(timeout_seconds) + "s]";
                break;
            }
        }

        DWORD exitCode = 0;
        WaitForSingleObject(proc->hProcess, 2000);
        GetExitCodeProcess(proc->hProcess, &exitCode);
        win_detail::cleanup(proc);

        result.output = buffer;
        result.exit_code = (int)exitCode;
        return result;
    }

    static void start_async(int64_t execution_id,
                             const std::string& command,
                             std::function<void(const std::string&)> on_chunk,
                             std::function<void(int)> on_done,
                             int timeout_seconds = 120) {
        start_async_in_dir(execution_id, command, "", on_chunk, on_done, timeout_seconds);
    }

    static void start_async_in_dir(int64_t execution_id,
                                    const std::string& command,
                                    const std::string& working_dir,
                                    std::function<void(const std::string&)> on_chunk,
                                    std::function<void(int)> on_done,
                                    int timeout_seconds = 120) {
        auto proc = win_detail::launch(command, working_dir);
        {
            std::lock_guard<std::mutex> lock(win_detail::registryMutex());
            win_detail::registry()[execution_id] = proc;
        }

        std::thread([execution_id, proc, timeout_seconds, on_chunk, on_done]() {
            char readBuf[4096];
            DWORD bytesRead = 0;
            DWORD startTick = GetTickCount();

            while (true) {
                DWORD avail = 0;
                if (!PeekNamedPipe(proc->hPipeOut, nullptr, 0, nullptr, &avail, nullptr)) break;
                if (avail > 0) {
                    if (!ReadFile(proc->hPipeOut, readBuf, sizeof(readBuf), &bytesRead, nullptr) || bytesRead == 0) break;
                    if (on_chunk) on_chunk(std::string(readBuf, bytesRead));
                } else {
                    DWORD waitResult = WaitForSingleObject(proc->hProcess, 20);
                    if (waitResult == WAIT_OBJECT_0) {
                        if (PeekNamedPipe(proc->hPipeOut, nullptr, 0, nullptr, &avail, nullptr) && avail > 0) continue;
                        break;
                    }
                }
                if (proc->killed.load()) {
                    if (on_chunk) on_chunk("\n[stopped by user]\n");
                    TerminateProcess(proc->hProcess, 1);
                    break;
                }
                if ((GetTickCount() - startTick) / 1000 > (DWORD)timeout_seconds) {
                    TerminateProcess(proc->hProcess, 1);
                    if (on_chunk) on_chunk("\n[timeout: command killed after " + std::to_string(timeout_seconds) + "s]\n");
                    break;
                }
            }

            DWORD exitCode = 0;
            WaitForSingleObject(proc->hProcess, 2000);
            GetExitCodeProcess(proc->hProcess, &exitCode);
            win_detail::cleanup(proc);

            {
                std::lock_guard<std::mutex> lock(win_detail::registryMutex());
                win_detail::registry().erase(execution_id);
            }
            if (on_done) on_done((int)exitCode);
        }).detach();
    }

    static bool kill_execution(int64_t execution_id) {
        std::shared_ptr<win_detail::PtyProcess> proc;
        {
            std::lock_guard<std::mutex> lock(win_detail::registryMutex());
            auto it = win_detail::registry().find(execution_id);
            if (it == win_detail::registry().end()) return false;
            proc = it->second;
        }
        proc->killed.store(true);
        return true;
    }
};

#else
// ============================================================================
//  POSIX IMPLEMENTATION (development/testing only, e.g. Linux/macOS)
// ============================================================================

class PtySession {
public:
    // ---- Blocking execution (simple, for short/internal calls) ----
    static ExecResult run(const std::string& command,
                           std::function<void(const std::string&)> on_chunk = nullptr,
                           int timeout_seconds = 30) {
        return run_in_dir(command, "", on_chunk, timeout_seconds);
    }

    static ExecResult run_in_dir(const std::string& command, const std::string& working_dir,
                                  std::function<void(const std::string&)> on_chunk = nullptr,
                                  int timeout_seconds = 30) {
        ExecResult result;
        int master_fd = -1;
        pid_t pid = forkpty(&master_fd, nullptr, nullptr, nullptr);

        if (pid < 0) {
            throw std::runtime_error("forkpty failed: " + std::string(strerror(errno)));
        }

        if (pid == 0) {
            if (!working_dir.empty()) {
                if (chdir(working_dir.c_str()) != 0) _exit(126);
            }
            execl("/bin/sh", "sh", "-c", command.c_str(), (char*)nullptr);
            _exit(127);
        }

        std::string buffer;
        char chunk[4096];
        fcntl(master_fd, F_SETFL, O_NONBLOCK);

        time_t start = time(nullptr);
        int status = 0;
        bool child_done = false;

        while (true) {
            ssize_t n = read(master_fd, chunk, sizeof(chunk) - 1);
            if (n > 0) {
                chunk[n] = '\0';
                buffer += chunk;
                if (on_chunk) on_chunk(std::string(chunk, n));
            } else if (n == 0) {
                break;
            } else {
                if (errno != EAGAIN && errno != EWOULDBLOCK) break;
            }

            pid_t wp = waitpid(pid, &status, WNOHANG);
            if (wp == pid) { child_done = true; }
            if (child_done && n <= 0) break;

            if (time(nullptr) - start > timeout_seconds) {
                kill(pid, SIGKILL);
                waitpid(pid, &status, 0);
                buffer += "\n[timeout: command killed after " + std::to_string(timeout_seconds) + "s]";
                break;
            }
            usleep(10000);
        }

        close(master_fd);
        if (!child_done) waitpid(pid, &status, 0);

        result.output = buffer;
        result.exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
        return result;
    }

    // ---- Async execution with real Stop support ----
    static void start_async(int64_t execution_id,
                             const std::string& command,
                             std::function<void(const std::string&)> on_chunk,
                             std::function<void(int)> on_done,
                             int timeout_seconds = 120) {
        start_async_in_dir(execution_id, command, "", on_chunk, on_done, timeout_seconds);
    }

    static void start_async_in_dir(int64_t execution_id,
                                    const std::string& command,
                                    const std::string& working_dir,
                                    std::function<void(const std::string&)> on_chunk,
                                    std::function<void(int)> on_done,
                                    int timeout_seconds = 120) {
        int master_fd = -1;
        pid_t pid = forkpty(&master_fd, nullptr, nullptr, nullptr);

        if (pid < 0) {
            throw std::runtime_error("forkpty failed: " + std::string(strerror(errno)));
        }

        if (pid == 0) {
            if (!working_dir.empty()) {
                if (chdir(working_dir.c_str()) != 0) _exit(126);
            }
            execl("/bin/sh", "sh", "-c", command.c_str(), (char*)nullptr);
            _exit(127);
        }

        {
            std::lock_guard<std::mutex> lock(registry_mutex());
            registry()[execution_id] = pid;
        }

        std::thread([execution_id, master_fd, pid, timeout_seconds, on_chunk, on_done]() {
            char chunk[4096];
            fcntl(master_fd, F_SETFL, O_NONBLOCK);
            time_t start = time(nullptr);
            int status = 0;
            bool child_done = false;

            while (true) {
                ssize_t n = read(master_fd, chunk, sizeof(chunk) - 1);
                if (n > 0) {
                    if (on_chunk) on_chunk(std::string(chunk, n));
                } else if (n == 0) {
                    break;
                } else {
                    if (errno != EAGAIN && errno != EWOULDBLOCK) break;
                }

                pid_t wp = waitpid(pid, &status, WNOHANG);
                if (wp == pid) { child_done = true; }
                if (child_done && n <= 0) break;

                if (was_killed(execution_id)) {
                    if (on_chunk) on_chunk("\n[stopped by user]\n");
                    break;
                }

                if (time(nullptr) - start > timeout_seconds) {
                    ::kill(pid, SIGKILL);
                    waitpid(pid, &status, 0);
                    if (on_chunk) on_chunk("\n[timeout: command killed after " + std::to_string(timeout_seconds) + "s]\n");
                    break;
                }
                usleep(10000);
            }

            close(master_fd);
            if (!child_done) {
                waitpid(pid, &status, WNOHANG);
            }

            {
                std::lock_guard<std::mutex> lock(registry_mutex());
                registry().erase(execution_id);
            }

            int exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
            if (on_done) on_done(exit_code);
        }).detach();
    }

    static bool kill_execution(int64_t execution_id) {
        pid_t pid = -1;
        {
            std::lock_guard<std::mutex> lock(registry_mutex());
            auto it = registry().find(execution_id);
            if (it == registry().end()) return false;
            pid = it->second;
        }
        mark_killed(execution_id);
        ::kill(pid, SIGTERM);
        usleep(200000);
        if (::kill(pid, 0) == 0) {
            ::kill(pid, SIGKILL);
        }
        return true;
    }

private:
    static std::mutex& registry_mutex() {
        static std::mutex m;
        return m;
    }
    static std::unordered_map<int64_t, pid_t>& registry() {
        static std::unordered_map<int64_t, pid_t> r;
        return r;
    }
    static std::mutex& killed_mutex() {
        static std::mutex m;
        return m;
    }
    static std::unordered_map<int64_t, bool>& killed_flags() {
        static std::unordered_map<int64_t, bool> f;
        return f;
    }
    static void mark_killed(int64_t id) {
        std::lock_guard<std::mutex> lock(killed_mutex());
        killed_flags()[id] = true;
    }
    static bool was_killed(int64_t id) {
        std::lock_guard<std::mutex> lock(killed_mutex());
        auto it = killed_flags().find(id);
        return it != killed_flags().end() && it->second;
    }
};

#endif

} // namespace aiterm
