#pragma once
#include <string>
#include <vector>
#include <regex>
#include <algorithm>
#include <cctype>

namespace aiterm {

enum class RiskLevel {
    SAFE = 0,       // explicitly recognized read-only command
    CONFIRM = 1,    // state change or unknown command; needs one-click confirmation
    DANGEROUS = 2,  // high-impact/indirect execution; needs typed confirmation
    BLOCKED = 3     // never executed, even with confirmation
};

struct ClassificationResult {
    RiskLevel level;
    std::string reason;
    std::string human_reason;
};

// Deterministic defense-in-depth independent of the AI model. This classifier
// is intentionally allowlist-oriented: an unknown command is CONFIRM, never
// SAFE. Only commands matched by safe_patterns_ may auto-run.
class RiskClassifier {
public:
    RiskClassifier() { buildRules(); }

    ClassificationResult classify(const std::string& command) const {
        std::string normalized = toLower(trim(command));
        if (normalized.empty()) {
            return {RiskLevel::BLOCKED, "empty command", "An empty command cannot be executed."};
        }

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
                return {RiskLevel::CONFIRM, "matched confirmation pattern: " + rule.name, rule.human_msg};
            }
        }
        for (const auto& rule : safe_patterns_) {
            if (std::regex_match(normalized, rule.pattern)) {
                return {RiskLevel::SAFE, "matched read-only pattern: " + rule.name, rule.human_msg};
            }
        }

        return {
            RiskLevel::CONFIRM,
            "no explicit safe pattern matched",
            "This command is not on the read-only allowlist, so it will not run without your confirmation."
        };
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
    std::vector<Rule> safe_patterns_;

    static std::string toLower(std::string s) {
        std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c){ return std::tolower(c); });
        return s;
    }
    static std::string trim(const std::string& s) {
        size_t a = s.find_first_not_of(" \t\r\n");
        if (a == std::string::npos) return "";
        size_t b = s.find_last_not_of(" \t\r\n");
        return s.substr(a, b - a + 1);
    }

    void buildRules() {
        const std::string blocked_msg = "This command can cause unrecoverable system-wide damage and is permanently blocked.";

        // ---- BLOCKED: catastrophic/system-protection operations ----
        blocked_patterns_.push_back({"format_drive", std::regex(R"(\bformat(\.com)?\s+[a-z]:)"),
            "This command would format an entire drive and erase its data."});
        blocked_patterns_.push_back({"disk_partition_wipe", std::regex(R"(\bdiskpart\b|\bclean\s+all\b|\b(clear-disk|initialize-disk|remove-partition)\b)"),
            "This command can erase or replace disk partitioning."});
        blocked_patterns_.push_back({"disable_defender", std::regex(R"(disable-windowsdefender|set-mppreference[^\r\n]*disablerealtimemonitoring\s+\$true|sc(\.exe)?\s+(stop|config)\s+windefend)"),
            "This command disables Windows Defender protection."});
        blocked_patterns_.push_back({"disable_firewall", std::regex(R"(netsh\s+advfirewall\s+set\s+allprofiles\s+state\s+off)"),
            "This command turns off Windows Firewall for every profile."});
        blocked_patterns_.push_back({"boot_tamper", std::regex(R"(\bbcdedit(\.exe)?\s+/(set|delete|deletevalue)|\bbootrec(\.exe)?\b)"),
            "This command changes boot configuration and could make the computer unbootable."});
        blocked_patterns_.push_back({"recovery_destruction", std::regex(R"(vssadmin(\.exe)?\s+delete\s+shadows|wmic(\.exe)?\s+shadowcopy\s+delete|wbadmin(\.exe)?\s+delete)"),
            "This command destroys recovery data or backups."});
        blocked_patterns_.push_back({"raw_device_write", std::regex(R"((\\\\\.\\physicaldrive|/dev/(sd[a-z]|nvme[0-9]))|\bdd\s+[^\r\n]*\bof=/dev/)"), blocked_msg});

        // ---- DANGEROUS: high impact, obfuscated, privileged, or indirect ----
        dangerous_patterns_.push_back({"recursive_delete", std::regex(R"(\b(remove-item|rm)\b[^\r\n]*(-recurse|-r\b)|\b(rd|rmdir)\b[^\r\n]*/s\b)"),
            "This command recursively deletes files or folders."});
        dangerous_patterns_.push_back({"system_path_delete", std::regex(R"(\b(remove-item|rm|del|rd|rmdir)\b[^\r\n]*(windows|program files|system32|/etc|/usr|/root))"),
            "This command targets files in a system directory."});
        dangerous_patterns_.push_back({"registry_change", std::regex(R"(\b(reg(\.exe)?\s+(add|delete)|remove-item(property)?\s+[^\r\n]*(hklm:|hkcu:)|new-item(property)?\s+[^\r\n]*(hklm:|hkcu:)))"),
            "This command changes the Windows Registry."});
        dangerous_patterns_.push_back({"shutdown_restart", std::regex(R"(\bshutdown(\.exe)?\b|\brestart-computer\b|\bstop-computer\b)"),
            "This command shuts down or restarts the computer."});
        dangerous_patterns_.push_back({"credential_access", std::regex(R"(mimikatz|sekurlsa|dump[^\r\n]*(password|credential)|cmdkey(\.exe)?\s+/list|security\s+find-generic-password)"),
            "This command may reveal credentials or other confidential data."});
        dangerous_patterns_.push_back({"remote_download_execute", std::regex(R"((invoke-webrequest|invoke-restmethod|\birm\b|\biwr\b|curl|wget)[^\r\n]*(\||invoke-expression|\biex\b|start-process|\bsh\b|\bbash\b))"),
            "This command downloads remote content and executes or pipes it immediately."});
        dangerous_patterns_.push_back({"encoded_or_dynamic_execution", std::regex(R"((-encodedcommand|-enc\b|frombase64string|invoke-expression|\biex\b|downloadstring|reflection\.assembly|\badd-type\b|\$\(|`))"),
            "This command uses encoded or dynamic code execution that is difficult to inspect."});
        dangerous_patterns_.push_back({"inline_interpreter", std::regex(R"(\b(python[0-9.]*|node|ruby|perl|php)\s+(-c|-e|-r)\b)"),
            "This command runs inline program code, which can hide unrelated system changes."});
        dangerous_patterns_.push_back({"privilege_or_persistence", std::regex(R"(start-process[^\r\n]*-verb\s+runas|\brunas(\.exe)?\b|\bsudo\b|schtasks(\.exe)?\s+/create|new-service|sc(\.exe)?\s+create|net(\.exe)?\s+(user|localgroup)[^\r\n]*/add)"),
            "This command elevates privileges, creates persistence, or changes accounts/services."});
        dangerous_patterns_.push_back({"permission_takeover", std::regex(R"(\btakeown(\.exe)?\b|\bicacls(\.exe)?\b[^\r\n]*/(grant|setowner|reset)|\bchmod\s+(-r\s+)?777\b|\bchown\b)"),
            "This command makes broad ownership or permission changes."});
        dangerous_patterns_.push_back({"firewall_rule", std::regex(R"(netsh\s+advfirewall\s+firewall\s+(add|set|delete)\s+rule|new-netfirewallrule|set-netfirewallprofile)"),
            "This command changes firewall rules or network protection."});

        // ---- CONFIRM: explicit writes and shell composition ----
        confirm_patterns_.push_back({"shell_composition", std::regex(R"((&&|\|\||;|(^|[^>])>(?!>)|>>|<|\|))"),
            "This command chains operations, uses a pipeline, or redirects data, so it requires review."});
        confirm_patterns_.push_back({"nested_expression", std::regex(R"([(){}])"),
            "This command contains a nested expression or script block and cannot be auto-run."});
        confirm_patterns_.push_back({"delete", std::regex(R"(\b(remove-item|del|erase|rm|rd|rmdir|unlink)\b)"),
            "This command deletes one or more files or folders."});
        confirm_patterns_.push_back({"write_file", std::regex(R"(\b(set-content|add-content|out-file|new-item|copy-item|cp|copy|mkdir|md|touch|tee)\b)"),
            "This command creates or changes files or folders."});
        confirm_patterns_.push_back({"install_software", std::regex(R"(\b(winget|choco|scoop|pip[0-9]*|npm|yarn|pnpm|apt|apt-get|dnf|yum|brew)\s+(install|add|upgrade|update|remove|uninstall)\b)"),
            "This command installs, updates, or removes software/packages."});
        confirm_patterns_.push_back({"move_or_rename", std::regex(R"(^\s*(move-item|move|mv|ren|rename-item)\b)"),
            "This command moves or renames a file or folder."});
        confirm_patterns_.push_back({"network_download", std::regex(R"(\b(invoke-webrequest|invoke-restmethod|iwr|irm|curl|wget)\b)"),
            "This command transfers data over the network."});
        confirm_patterns_.push_back({"process_change", std::regex(R"(\b(stop-process|start-process|taskkill|kill|killall)\b)"),
            "This command starts or stops another process."});
        confirm_patterns_.push_back({"environment_change", std::regex(R"(setenvironmentvariable|\bsetx(\.exe)?\b|\bexport\s+[a-z_][a-z0-9_]*=)"),
            "This command changes an environment variable."});
        confirm_patterns_.push_back({"source_control_change", std::regex(R"(\bgit\s+(add|commit|push|pull|merge|rebase|reset|checkout|switch|restore|clean|stash|tag|branch\s+(-d|-d\b))\b)"),
            "This command changes the working tree, history, or a remote repository."});

        // ---- SAFE: complete-command read-only allowlist ----
        const std::string read_only_msg = "This command is explicitly recognized as read-only.";
        safe_patterns_.push_back({"filesystem_read", std::regex(R"(^\s*(get-childitem|dir|ls|tree|pwd|get-location)(\s+[^;&|<>`]*)?$)"), read_only_msg});
        safe_patterns_.push_back({"file_read", std::regex(R"(^\s*(get-content|get-item|get-filehash|test-path|cat|type|more|head|tail|wc|du|df)(\s+[^;&|<>`]*)?$)"), read_only_msg});
        safe_patterns_.push_back({"text_search", std::regex(R"(^\s*(select-string|measure-object|grep|findstr)(\s+[^;&|<>`]*)?$)"), read_only_msg});
        safe_patterns_.push_back({"system_read", std::regex(R"(^\s*(whoami|hostname|get-process|get-service|get-date|get-command|where|where\.exe|which|ping|tracert|traceroute|nslookup)(\s+[^;&|<>`]*)?$)"), read_only_msg});
        safe_patterns_.push_back({"version_query", std::regex(R"(^\s*(python|python3|node|npm|pip|pip3|git|cmake|flutter|dart)\s+(--version|version)\s*$)"), read_only_msg});
        safe_patterns_.push_back({"git_read", std::regex(R"(^\s*git\s+(status|log|show|diff)(\s+[^;&|<>`]*)?$)"), read_only_msg});
        safe_patterns_.push_back({"clock_read", std::regex(R"(^\s*(date|time)\s+/t\s*$)"), read_only_msg});
    }
};

} // namespace aiterm
