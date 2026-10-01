// Shared small UI-only data types (kept separate from api_client.dart's
// wire-format types so screens don't need to know REST/WS details).

enum AgentMode { plan, build }

extension AgentModeX on AgentMode {
  String get wireValue => this == AgentMode.plan ? 'plan' : 'build';
  String get label => this == AgentMode.plan ? 'Plan' : 'Build';
}

enum RiskLevel { safe, confirm, dangerous, blocked, blockedByMode, blockedByWorkspace, busy }

RiskLevel riskFromString(String? s) {
  switch (s) {
    case 'CONFIRM':
      return RiskLevel.confirm;
    case 'DANGEROUS':
      return RiskLevel.dangerous;
    case 'BLOCKED':
      return RiskLevel.blocked;
    case 'BLOCKED_BY_MODE':
      return RiskLevel.blockedByMode;
    case 'BLOCKED_BY_WORKSPACE':
      return RiskLevel.blockedByWorkspace;
    case 'BUSY':
      return RiskLevel.busy;
    default:
      return RiskLevel.safe;
  }
}
