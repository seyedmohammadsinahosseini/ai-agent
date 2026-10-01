#include <cassert>
#include <iostream>
#include <string>
#include "../risk_classifier.hpp"

using aiterm::RiskClassifier;
using aiterm::RiskLevel;

static void expect(const RiskClassifier& classifier, const std::string& command, RiskLevel level) {
    auto result = classifier.classify(command);
    if (result.level != level) {
        std::cerr << "Unexpected classification for: " << command << "\n"
                  << "Reason: " << result.reason << "\n";
        std::abort();
    }
}

int main() {
    RiskClassifier classifier;

    // Only explicit read-only commands auto-run.
    expect(classifier, "Get-ChildItem", RiskLevel::SAFE);
    expect(classifier, "git status", RiskLevel::SAFE);
    expect(classifier, "Get-Content notes.txt", RiskLevel::SAFE);

    // Unknown and state-changing commands never silently auto-run.
    expect(classifier, "my-custom-tool --do-work", RiskLevel::CONFIRM);
    expect(classifier, "Set-Content notes.txt hello", RiskLevel::CONFIRM);
    expect(classifier, "echo hello > notes.txt", RiskLevel::CONFIRM);
    expect(classifier, "Get-Content (Join-Path . notes.txt)", RiskLevel::CONFIRM);
    expect(classifier, "pip install requests", RiskLevel::CONFIRM);

    // Indirect/privileged execution requires typed confirmation.
    expect(classifier, "python -c \"import os; os.remove('x')\"", RiskLevel::DANGEROUS);
    expect(classifier, "powershell -EncodedCommand ZQBjAGgAbwA=", RiskLevel::DANGEROUS);
    expect(classifier, "Get-Content $(Remove-Item secret.txt)", RiskLevel::DANGEROUS);
    expect(classifier, "Remove-Item -Force -Recurse old", RiskLevel::DANGEROUS);
    expect(classifier, "shutdown /r /t 0", RiskLevel::DANGEROUS);

    // Catastrophic system operations remain permanently blocked.
    expect(classifier, "format C:", RiskLevel::BLOCKED);
    expect(classifier, "diskpart", RiskLevel::BLOCKED);
    expect(classifier, "vssadmin delete shadows /all", RiskLevel::BLOCKED);

    std::cout << "risk_classifier_test: all checks passed\n";
    return 0;
}
