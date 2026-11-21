# adomatic-mcp — Ad-o-matic MCP Server

Zero-dependency Model Context Protocol (MCP) server for **Ad-o-matic** (`https://ad-o-matic.com`), an autonomous 1-line peer-to-peer (P2P) mobile app cross-promotion network for Android (Jetpack Compose), iOS (SwiftUI), Flutter, React Native, and WebView/Hybrid HTML apps.

- **No API keys, no signup forms, no ad spend, and no tracking SDKs.**
- **Free 1-Line Integration:** Drop a single source file into your mobile app (`HouseAdBanner.kt`, `HouseAdBanner.swift`, `HouseAdBanner.dart`, `HouseAdBanner.tsx`, or `ad-widget.js`) and enter live P2P rotation automatically once published after the 7-day Self-Preview Test Period.

## Quick MCP Setup

### Option A — Remote Streamable HTTP (Recommended, Zero Install)

```json
{
  "mcpServers": {
    "adomatic": {
      "type": "http",
      "url": "https://ad-o-matic.com/mcp"
    }
  }
}
```

### Option B — Remote Stdio Proxy or Local Zero-Dependency Node Bridge (Node.js 18+)

```json
{
  "mcpServers": {
    "adomatic": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://ad-o-matic.com/mcp"]
    }
  }
}
```

Or run the local bridge directly from [`sdk/adomatic-mcp.js`](../sdk/adomatic-mcp.js):

```json
{
  "mcpServers": {
    "adomatic": {
      "command": "node",
      "args": ["sdk/adomatic-mcp.js"]
    }
  }
}
```

## Available MCP Tools

1. `adomatic_get_integration` — Returns the ready-to-paste 1-line snippet and optional full zero-dependency SDK source (`HouseAdBanner.kt` / `HouseAdBanner.swift` / `HouseAdBanner.dart` / `HouseAdBanner.tsx` / `ad-widget.js`) tailored to your app's `targetAudience`.
2. `adomatic_onboard_app` — Pre-registers an Android, iOS, Flutter, React Native, or WebView app for free P2P cross-promotion.
3. `adomatic_verify_integration` — Checks integration status, 7-day Self-Preview progress, matched audience segments, and Genesis Member checklist.
4. `adomatic_network_status` — Queries live Genesis Member availability (first 50 verified published apps earn permanent founding priority, max 3 per developer) and network stats.

## Documentation & Machine Specs

- Website: https://ad-o-matic.com
- Public SDK Repository: https://github.com/ad-o-matic/ad-o-matic-sdk
- AI Agent Skill: https://ad-o-matic.com/SKILL.md
- OpenAPI 3.1 Spec: https://ad-o-matic.com/openapi.json
- LLM Context: https://ad-o-matic.com/llms.txt and https://ad-o-matic.com/llms-full.txt
