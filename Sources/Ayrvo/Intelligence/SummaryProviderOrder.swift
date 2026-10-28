enum SummaryProviderOrder {
    static func providers(preferred: AIProvider, cloudReady: Bool, preferCloudOnly: Bool) -> [AIProvider] {
        guard preferred != .apple else { return [.apple, .claude, .codex] }
        let fallback: AIProvider = preferred == .codex ? .claude : .codex
        guard cloudReady else { return [.apple, preferred, fallback] }
        return preferCloudOnly ? [preferred, fallback] : [preferred, .apple, fallback]
    }
}
