#pragma once
#include <string>
#include <vector>
#include <regex>
#include <algorithm>
#include <cctype>

namespace aiterm {

enum class RiskLevel {
    SAFE = 0,       // auto-execute allowed
    CONFIRM = 1,    // needs a simple one-click user confirmation
    DANGEROUS = 2,  // needs strong/explicit confirmation (e.g. typing a phrase)
    BLOCKED = 3     // never executed, even with confirmation
};

struct ClassificationResult {
    RiskLevel level;
    std::string reason;         // technical reason (for logs)
    std::string human_reason;   // plain-language explanation for the end user
};

// This layer is fully deterministic and independent of the AI model's own
// judgement. Goal: even if the model hallucinates or is manipulated via
// prompt injection, this layer acts as an independent second line of defense.
class RiskClassifier {
public:
    RiskClassifier() { buildRules(); }

    ClassificationResult classify(const std::string& command) const {
        std::string normalized = toLower(trim(command));

        for (const auto& rule : blocked_patterns_) {
            if (std::regex_search(normalized, rule.pattern)) {
                return {RiskLevel::BLOCKED, "matched blocked pattern: " + rule.name, rule.human_msg};
            }
        }

        for (const auto& rule : dangerous_patterns_) {
            if (std::regex_search(normalized, rule.pattern)) {
                return {RiskLevel::DANGEROUS, "matched dangerous pattern: " + rule.name, rule.human_msg};
            }
        }

        for (const auto& rule : confirm_patterns_) {
            if (std::regex_search(normalized, rule.pattern)) {
                return {RiskLevel::CONFIRM, "matched confirm pattern: " + rule.name, rule.human_msg};
            }
        }

        return {RiskLevel::SAFE, "no risky pattern matched", "This command only reads information or makes a harmless, reversible change."};
    }

private:
    struct Rule {
        std::string name;
        std::regex pattern;
        std::string human_msg;
    };

    std::vector<Rule> blocked_patterns_;
    std::vector<Rule> dangerous_patterns_;
    std::vector<Rule> confirm_patterns_;

    static std::string toLower(std::string s) {
        std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c){ return std::tolower(c); });
        return s;
    }
    static std::string trim(const std::string& s) {
        size_t a = s.find_first_not_of(" \t\r\n");
        size_t b = s.find_last_not_of(" \t\r\n");
        if (a == std::string::npos) return "";
        return s.substr(a, b - a + 1);
    }

    void buildRules() {
        // ---- BLOCKED: must never run, even with user confirmation ----
        blocked_patterns_.push_back({
            "format_drive",
            std::regex(R"(\bformat\s+[a-z]:)"),
            "This command would format an entire drive, permanently erasing all data on it."
        });
        blocked_patterns_.push_back({
            "diskpart_clean",
            std::regex(R"(diskpart|clean\s+all)"),
            "This command can wipe disk partitioning entirely."
        });
        blocked_patterns_.push_back({
            "disable_defender",
            std::regex(R"(disable-windowsdefender|set-mppreference.*disablerealtimemonitoring\s+\$true|sc\s+(stop|config)\s+windefend)"),
            "This command disables Windows Defender (your antivirus protection)."
        });
        blocked_patterns_.push_back({
            "disable_firewall",
            std::regex(R"(netsh\s+advfirewall\s+set\s+allprofiles\s+state\s+off)"),
            "This command turns off the Windows Firewall completely."
        });
        blocked_patterns_.push_back({
            "bcdedit_boot_tamper",
            std::regex(R"(bcdedit\s+/(set|delete))"),
            "This command changes Windows boot configuration and could make the system unbootable."
        });

        // ---- DANGEROUS: requires strong/explicit confirmation ----
        dangerous_patterns_.push_back({
            "recursive_delete_system",
            std::regex(R"((remove-item|rd|rmdir|del)\s+.*(-recurse|/s).*(c:\\windows|c:\\program files|c:\\$))"),
            "This command recursively deletes important system files."
        });
        dangerous_patterns_.push_back({
            "recursive_force_delete",
            std::regex(R"((remove-item|rm)\s+.*-recurse.*-force)"),
            "This command permanently deletes files/folders with no way to undo it."
        });
        dangerous_patterns_.push_back({
            "registry_delete",
            std::regex(R"(remove-item\s+.*hklm:|reg\s+delete)"),
            "This command deletes Windows Registry values, which can destabilize the system."
        });
        dangerous_patterns_.push_back({
            "shutdown_restart",
            std::regex(R"(\bshutdown\b|restart-computer)"),
            "This command shuts down or restarts the computer."
        });
        dangerous_patterns_.push_back({
            "credential_dump",
            std::regex(R"(mimikatz|dump.*password|cmdkey\s+/list)"),
            "This command may reveal confidential information such as saved passwords."
        });
        dangerous_patterns_.push_back({
            "open_firewall_port",
            std::regex(R"(netsh\s+advfirewall\s+firewall\s+add\s+rule)"),
            "This command opens a new firewall rule, which could expose the system to network risks."
        });
        dangerous_patterns_.push_back({
            "remote_download_execute",
            std::regex(R"(invoke-webrequest.*\|.*iex|irm.*\|.*iex|curl.*\|\s*sh)"),
            "This command downloads a file from the internet and immediately executes it, which carries malware risk."
        });

        // ---- CONFIRM: reversible state change, needs a simple confirmation ----
        confirm_patterns_.push_back({
            "simple_delete",
            std::regex(R"(^(remove-item|del|rm|rd|rmdir)\b)"),
            "This command deletes one or more files/folders."
        });
        confirm_patterns_.push_back({
            "install_software",
            std::regex(R"(winget\s+install|choco\s+install|pip\s+install|npm\s+install\s+-g)"),
            "This command installs new software/packages on the system."
        });
        confirm_patterns_.push_back({
            "move_or_rename",
            std::regex(R"(^(move-item|move|ren|rename-item)\b)"),
            "This command moves or renames a file/folder."
        });
        confirm_patterns_.push_back({
            "network_download",
            std::regex(R"(invoke-webrequest|curl\s|wget\s)"),
            "This command downloads a file from the internet."
        });
        confirm_patterns_.push_back({
            "process_kill",
            std::regex(R"(stop-process|taskkill)"),
            "This command closes a running application."
        });
        confirm_patterns_.push_back({
            "env_var_change",
            std::regex(R"(\[environment\]::setenvironmentvariable|setx\s)"),
            "This command changes a system environment variable."
        });
    }
};

} // namespace aiterm
