# Multi-Provider UI Enhancement + Rebranding

## TL;DR

> **Quick Summary**: 메뉴바 앱에 OpenRouter/OpenCode Provider 추가, Provider별 Assets 아이콘 적용, Submenu로 상세 정보 표시, 메뉴바 아이콘을 SF Symbol gauge.medium으로 변경, **앱 브랜딩을 'OpencodeProvidersMonitor'로 변경**
> 
> **Deliverables**:
> - OpenRouterProvider (API 기반, pay-as-you-go)
> - OpenCodeProvider (API 기반, API 없으면 비활성화)
> - Provider별 Assets.xcassets 아이콘 적용
> - 메뉴바 아이콘 SF Symbol `gauge.medium` 변경
> - Provider별 Submenu 디테일 표시
> - GitHub Copilot Quota + Pay-as-you-go 이중 표시
> - **앱 리브랜딩: CopilotMonitor → OpencodeProvidersMonitor**
> - XCTest 추가 + 기존 테스트 불일치 수정
> 
> **Estimated Effort**: Medium-Large
> **Parallel Execution**: YES - 4 waves
> **Critical Path**: Task 1 → Task 3 → Task 6 → Task 9

---

## Context

### Original Request
1. 각 벤더 마우스 올리면 일별/주간한도/리셋시간 등 모든 디테일을 볼 수 있어야함
2. Pay-as-you-go 에 GitHub Copilot, OpenCode, OpenRouter 가 표시되어야함 (auth 파일에 키가 있음)
3. 각 프로바이더 아이콘은 Assets.xcassets 폴더에 있는걸로 사용해야함
4. 메뉴바에 아이콘은 현재 코파일럿 아이콘인데 이건 공용 아이콘으로 변경되어야함

### Interview Summary
**Key Discussions**:
- 메뉴바 아이콘: SF Symbol `gauge.medium` 사용
- Provider 아이콘: Assets.xcassets 사용 (OpenRouter는 SF Symbol `arrow.triangle.branch`로 대체)
- Hover UI: Submenu 확장 방식
- OpenRouter: API 기반 (`/api/v1/credits`, `/api/v1/key`)
- OpenCode: API 우선 탐색, API 없으면 Provider 비활성화 (WebView 로그인 플로우 없음)
- GitHub Copilot: Quota + Pay-as-you-go 둘 다 표시 - **한도는 API에서 동적으로 (userPremiumRequestEntitlement)**
- Submenu 포맷: **SF Symbol (calendar) + 숫자** (예: 📅 0.5 / 2.3 / 15.2)
- ProviderUsage 모델: **확장 필요** (.payAsYouGo에 dailyUsage, weeklyUsage, monthlyUsage 추가)

**Research Findings**:
- OpenRouter API 응답 확인:
  - `/api/v1/credits`: `{ data: { total_credits, total_usage } }`
  - `/api/v1/key`: `{ data: { limit, limit_remaining, usage_daily, usage_weekly, usage_monthly, limit_reset } }`
- OpenCode: API 탐색 필요 → API 없으면 Provider 비활성화 (WebView/DOM 사용 안 함)
- Assets 아이콘: CopilotIcon, ClaudeIcon, CodexIcon, GeminiIcon, OpencodeIcon 존재

### Metis Review
**Identified Gaps** (addressed):
- OpenRouter 아이콘 미존재 → SF Symbol 사용으로 결정
- GitHub Copilot 분류 모호 → Quota + Pay-as-you-go 이중 표시로 결정
- Tooltip UX 미정 → Submenu 방식으로 결정

---

## Technical Design Decisions (Momus-Required)

### 1. auth.json 스키마 확장 설계

**현재 구조** (`~/.local/share/opencode/auth.json`):
```json
{
  "openai": { "type": "oauth", "refresh": "...", "access": "...", "expires": 123, "accountId": "..." },
  "anthropic": { "type": "oauth", "refresh": "...", "access": "...", "expires": 123 },
  "github-copilot": { "type": "oauth", "refresh": "...", "access": "...", "expires": 0 },
  "openrouter": { "type": "api", "key": "sk-or-v1-..." },
  "opencode": { "type": "api", "key": "sk-..." }
}
```

**확장 방안**: `OpenCodeAuth` 구조체에 API 키 타입 추가

```swift
// Services/TokenManager.swift 확장
struct OpenCodeAuth: Codable {
    // 기존 OAuth 구조
    struct OAuth: Codable {
        let type: String  // "oauth"
        let access: String
        let refresh: String
        let expires: Int64
        let accountId: String?
    }
    
    // 신규: API Key 구조
    struct APIKey: Codable {
        let type: String  // "api"
        let key: String
    }
    
    // 기존 OAuth 필드 (유지)
    let anthropic: OAuth?
    let openai: OAuth?
    let githubCopilot: OAuth?
    
    // 신규 API Key 필드
    let openrouter: APIKey?
    let opencode: APIKey?
    
    enum CodingKeys: String, CodingKey {
        case anthropic, openai, openrouter, opencode
        case githubCopilot = "github-copilot"
    }
}

// 신규 메서드 추가
func getOpenRouterAPIKey() -> String? {
    guard let auth = readOpenCodeAuth() else { return nil }
    return auth.openrouter?.key
}

func getOpenCodeAPIKey() -> String? {
    guard let auth = readOpenCodeAuth() else { return nil }
    return auth.opencode?.key
}
```

### 2. ProviderUsage 확장 및 DetailedUsage 전달 설계

**현재 모델**:
```swift
case payAsYouGo(utilization: Double, resetsAt: Date?)
```

**확장 방안 결정**: 방안 (A) - ProviderProtocol 반환 타입을 `ProviderResult`로 변경

```swift
// Models/ProviderResult.swift (신규 파일)
struct ProviderResult {
    let usage: ProviderUsage
    let details: DetailedUsage?  // Optional 상세 정보
}

struct DetailedUsage: Codable {
    // 사용량 (Usage)
    let dailyUsage: Double?       // 오늘 사용량 ($)
    let weeklyUsage: Double?      // 이번 주 사용량 ($)
    let monthlyUsage: Double?     // 이번 달 사용량 ($)
    
    // 크레딧 (Credits)
    let totalCredits: Double?     // 총 충전 크레딧 ($)
    let remainingCredits: Double? // 남은 크레딧 ($)
    
    // 한도 (Limit) - 원요구사항: "일별/주간한도" 포함
    let limit: Double?            // 설정된 한도 ($)
    let limitRemaining: Double?   // 남은 한도 ($)
    let resetPeriod: String?      // 리셋 주기 ("weekly", "monthly")
}
```

**수정 파일 목록**:
1. `Models/ProviderResult.swift` - 신규 생성
2. `Models/ProviderProtocol.swift` - `fetch() -> ProviderResult` 로 변경
3. `Providers/*.swift` (모든 Provider) - 반환 타입 변경
4. `Services/ProviderManager.swift` - 캐시 타입 변경 + 관련 함수 수정
5. `App/StatusBarController.swift` - `providerResults` 타입 변경

**ProviderManager.swift 상세 수정 목록** (`Services/ProviderManager.swift`):

| 함수/변수 | 현재 타입 | 변경 후 타입 |
|----------|----------|-------------|
| `cachedResults` (line 33) | `[ProviderIdentifier: ProviderUsage]` | `[ProviderIdentifier: ProviderResult]` |
| `fetchAll()` (line 47) | `-> [ProviderIdentifier: ProviderUsage]` | `-> [ProviderIdentifier: ProviderResult]` |
| `results` 로컬 변수 (line 50) | `[ProviderIdentifier: ProviderUsage]` | `[ProviderIdentifier: ProviderResult]` |
| `calculateTotalOverageCost(from:)` (line 101) | `from: [ProviderIdentifier: ProviderUsage]` | `from: [ProviderIdentifier: ProviderResult]` 내부에서 `result.usage` 접근 |
| `getQuotaAlerts(from:)` (line 111) | `from: [ProviderIdentifier: ProviderUsage]` | `from: [ProviderIdentifier: ProviderResult]` 내부에서 `result.usage` 접근 |
| `fetchWithTimeout(provider:)` (line 155) | `-> ProviderUsage` | `-> ProviderResult` |
| `updateCache(identifier:usage:)` (line 184) | `usage: ProviderUsage` | `result: ProviderResult` |
| `getCache(identifier:)` (line 195) | `-> ProviderUsage?` | `-> ProviderResult?` |

**StatusBarController.swift `providerResults` 타입** (line 423):
- 현재: `private var providerResults: [ProviderIdentifier: ProviderUsage] = [:]`
- 변경: `private var providerResults: [ProviderIdentifier: ProviderResult] = [:]`

**데이터 흐름**:
```
OpenRouterProvider.fetch()
  → ProviderResult(usage: .payAsYouGo(...), details: DetailedUsage(daily: 0.5, ...))
  → ProviderManager.fetchAll()
  → StatusBarController.providerResults
  → updateMultiProviderMenu()
  → Submenu에 details.dailyUsage, details.weeklyUsage 표시
```

**OpenRouter API 스키마 (검증됨 - 2024-01-30 curl 테스트)**:

```json
// GET https://openrouter.ai/api/v1/credits
// Header: Authorization: Bearer <api_key>
{
  "data": {
    "total_credits": 6685.0,     // Double - 총 충전 크레딧 ($)
    "total_usage": 6548.72       // Double - 총 사용금액 ($)
  }
}

// GET https://openrouter.ai/api/v1/key
// Header: Authorization: Bearer <api_key>
{
  "data": {
    "limit": 100.0,              // Double? - 일간/주간 한도 ($), null 가능
    "limit_remaining": 99.99,    // Double? - 남은 한도 ($)
    "limit_reset": "weekly",     // String? - 리셋 주기 ("weekly", "monthly", null)
                                 // ⚠️ Date가 아닌 String! Date 변환 안 함
    "usage_daily": 0.004,        // Double - 오늘 사용량 ($)
    "usage_weekly": 0.5,         // Double - 이번 주 사용량 ($)
    "usage_monthly": 37.41       // Double - 이번 달 사용량 ($)
  }
}
```

**Swift 디코딩 타입**:
- 모든 숫자는 `Double` (API가 JSON number 반환)
- `limit`, `limit_remaining`, `limit_reset`은 Optional (null 가능)
- ⚠️ `NSNumber` 처리: API가 Double 반환하므로 `JSONDecoder`로 직접 `Double`로 디코딩 가능

**utilization 계산 공식** (OpenRouter용):
```swift
// OpenRouter의 utilization = (사용금액 / 총크레딧) * 100
// ⚠️ Edge Case: division by zero 방지
let utilization: Double
if total_credits > 0 {
    utilization = (total_usage / total_credits) * 100
} else {
    // total_credits == 0 (신규 계정, 크레딧 미충전)
    utilization = 0.0  // 0% 표시
}
// resetsAt = nil (크레딧 기반, 리셋 없음 - limit_reset은 period 문자열)
```

**Edge Case 처리 (division by zero)**:
| 상황 | total_credits | total_usage | utilization | 표시 |
|------|--------------|-------------|-------------|------|
| 정상 | 6685.0 | 6548.72 | 97.96% | `OpenRouter 98.0%` |
| 신규 계정 | 0.0 | 0.0 | 0.0% | `OpenRouter 0.0%` |
| 크레딧 0 | 0.0 | N/A | 0.0% | `OpenRouter 0.0%` |
| null 응답 | nil | - | Error | `authenticationFailed` throw → 숨김 |

### Pay-as-you-go 메인 라인 표시 규칙 (확정)

**결정**: 기존 앱 동작 유지 - **항상 퍼센트(%)로 표시**

| Provider | 메인 라인 표시 | 계산식 |
|----------|---------------|--------|
| Codex | `Codex         45.2%` | 기존 utilization 그대로 |
| OpenRouter | `OpenRouter    97.0%` | `(total_usage / total_credits) * 100` |
| OpenCode | `OpenCode      XX.X%` | API 응답에 따라 결정 |
| Copilot Add-on | `Copilot Add-on    $X.XX` | **예외**: 추가 요금이므로 달러 표시 |

**근거**: 
- 기존 `createPayAsYouGoMenuItem()`이 `%.1f%%` 포맷 사용 (`StatusBarController.swift`)
- 일관성 유지 - 모든 pay-as-you-go는 퍼센트로 통일
- Copilot Add-on만 예외 (netBilledAmount는 초과 요금이므로 달러가 자연스러움)

**Submenu에서 달러 상세 표시**:
- 메인 라인: 퍼센트 (%)
- Submenu: 달러 ($) 상세 정보 (Daily/Weekly/Monthly/Credits)

**기존 Provider 호환성**:
- 기존 Provider (Claude, Codex, GeminiCLI)는 `details: nil` 반환
- `ProviderUsage` enum 자체는 변경 없음 (Codable 호환 유지)

### 3. OpenCodeProvider 전략 (API 우선, 없으면 비활성화)

**AGENTS.md 규칙 준수**:
> "Get the data from API only, not from DOM" 규칙을 따름.
> WebView 스크래핑/DOM 파싱 사용 안 함.

**결정된 방향**: API가 없으면 Provider 비활성화

**⚠️ "비활성화" 구현 방식 (단일 정답 - 등록 후 throw)**:

OpenCodeProvider는 **항상 ProviderManager에 등록**되지만, fetch() 시 에러를 throw하여 결과에서 제외됩니다.

```swift
// ProviderManager.swift - OpenCodeProvider 등록 (항상)
private let providers: [ProviderProtocol] = [
    ClaudeProvider(),
    CodexProvider(),
    GeminiCLIProvider(),
    OpenRouterProvider(),  // 항상 등록
    OpenCodeProvider()     // 항상 등록
]

// OpenCodeProvider.fetch() - API 없으면 throw
func fetch() async throws -> ProviderResult {
    guard let apiKey = tokenManager.getOpenCodeAPIKey() else {
        throw ProviderError.authenticationFailed("API key not found")
    }
    
    // API 호출 시도
    let response = try await callAPI()
    if response.status == 404 {
        throw ProviderError.authenticationFailed("API not available (404)")
    }
    // 성공 시 ProviderResult 반환
}

// ProviderManager.fetchAll() - throw된 Provider는 결과에서 자동 제외
// (Task 5/6의 "캐시 무시" 로직에 따라 authenticationFailed는 캐시도 안 씀)
```

**이 방식의 장점**:
- 코드 일관성: 모든 Provider가 동일 패턴 (등록 → fetch → 성공/실패)
- 동적 처리: API가 나중에 추가되면 즉시 동작 (재시작 불필요)
- 테스트 용이: Provider 자체의 throw 동작을 테스트 가능

**플로우 설계**:
1. **Provider 등록**: ProviderManager에 항상 등록 (조건부 등록 아님)
2. **fetch() 호출**: API 키 체크 → API 호출 → 응답 처리
3. **API 미존재 시**: `throw ProviderError.authenticationFailed()` → 결과에서 제외
4. **DOM 파싱 없음**: WebView 창 띄우거나 HTML 파싱하지 않음

**UI 플로우**:
- **API 성공 시**: 메뉴에 OpenCode 표시 (잔액 + 사용량)
- **API 실패/미존재 시**: 메뉴에서 OpenCode 숨김 (에러 표시 없음, 캐시도 안 씀)
- **WebView 로그인 플로우 없음**

**구현 시 탐색 순서**:
```bash
# 1. 잔액 API 탐색
curl -s https://api.opencode.ai/v1/credits \
  -H "Authorization: Bearer $(jq -r '.opencode.key' ~/.local/share/opencode/auth.json)"

# 2. 사용량 API 탐색
curl -s https://api.opencode.ai/v1/usage \
  -H "Authorization: Bearer $(jq -r '.opencode.key' ~/.local/share/opencode/auth.json)"

# 3. 404/401 반환 시: API 미존재로 판단 → Provider 비활성화
```

**Acceptance Criteria**:
- API 발견 시: Provider 정상 표시
- API 미발견 시: Provider 숨김 (메뉴에 표시 안 됨)
- 에러 로그: `Logger.debug("OpenCode API not available, provider disabled")`

### 4. Copilot 이중 표시 삽입 지점

**현재 코드 분석** (`StatusBarController.swift:963-1044`):
```swift
private func updateMultiProviderMenu() {
    // providerResults를 순회하며 .payAsYouGo / .quotaBased 분리
    for (identifier, usage) in providerResults {
        if case .payAsYouGo(let utilization, _) = usage {
            // Pay-as-you-go 섹션에 추가
        }
    }
    for (identifier, usage) in providerResults {
        if case .quotaBased(...) = usage {
            // Quota Status 섹션에 추가
        }
    }
}
```

**Copilot 이중 표시 구현 방안**:

```swift
// 1. Copilot은 providerResults에서 제외하고 별도 처리
// 2. currentUsage (CopilotUsage)에서 데이터 추출

// Pay-as-you-go 섹션에 Copilot Add-on 추가:
if let copilotUsage = currentUsage, copilotUsage.netBilledAmount > 0 {
    let addOnItem = createPayAsYouGoMenuItem(
        identifier: .copilot,
        utilization: /* addOnCost 표시 */,
        customTitle: String(format: "Copilot Add-on    $%.2f", copilotUsage.netBilledAmount)
    )
    addOnItem.tag = 999
    menu.insertItem(addOnItem, at: insertIndex)
    insertIndex += 1
}

// Quota 섹션에 Copilot Quota 추가 (기존 CopilotUsageView와 별도):
if let copilotUsage = currentUsage {
    let limit = copilotUsage.userPremiumRequestEntitlement  // API에서 동적 가져옴, non-optional Int
    let used = copilotUsage.usedRequests
    let percentage = limit > 0 ? (Double(limit - used) / Double(limit)) * 100 : 0
    let quotaItem = createQuotaMenuItem(identifier: .copilot, percentage: percentage)
    quotaItem.tag = 999
    menu.insertItem(quotaItem, at: insertIndex)
    insertIndex += 1
}
```

**데이터 소스**:
- `currentUsage: CopilotUsage?` - StatusBarController에 이미 존재
- `netBilledAmount` - 추가 요금 (>0 일 때만 Pay-as-you-go 표시)
- `userPremiumRequestEntitlement` - 동적 한도 (하드코딩 금지)
- `usedRequests` - 사용량

### 5. 파일 참조 규칙 및 정정

**⚠️ 파일 경로 표기 규칙**:
- 모든 파일 경로는 `CopilotMonitor/CopilotMonitor/` 기준 상대 경로로 표기
- 예: `App/StatusBarController.swift:72` = `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift:72`
- 단축 표기 시에도 서브디렉토리 포함: `App/`, `Models/`, `Providers/`, `Services/`, `Views/`

| 플랜 참조 | 실제 위치 (풀패스) | 비고 |
|----------|----------|------|
| `ProviderProtocol.swift:24-28` | `CopilotMonitor/CopilotMonitor/Models/ProviderProtocol.swift:12-35` | ProviderIdentifier enum |
| `TokenManager.swift:8-31` | `CopilotMonitor/CopilotMonitor/Services/TokenManager.swift:8-31` | OpenCodeAuth struct ✓ |
| `TokenManager.swift:124-141` | `CopilotMonitor/CopilotMonitor/Services/TokenManager.swift:124-141` | getXXXAccessToken() ✓ |
| `StatusBarController.swift:480` | `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift:480` | statusBarIconView 초기화 |
| `StatusBarController.swift:1065-1078` | `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift:1065-1078` | iconForProvider() ✓ |
| `updateMultiProviderMenu()` | `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift:963-1044` | 메뉴 업데이트 로직 |
| `AppDelegate.swift:72` | `CopilotMonitor/CopilotMonitor/App/AppDelegate.swift:72` | "GitHub 로그인" UI 텍스트 |
| `ProviderManager.swift:69-80` | `CopilotMonitor/CopilotMonitor/Services/ProviderManager.swift:69-80` | 캐시 fallback 로직 |

---

## Work Objectives

### Core Objective
macOS 메뉴바 앱에 OpenRouter/OpenCode Provider를 추가하고, 모든 Provider에 대해 Assets 아이콘과 Submenu 디테일 표시 기능을 구현한다.

### Design Clarifications (Momus Review Round 12)

#### 1. ProviderIdentifier rawValue 명시

**새 case의 rawValue (snake_case 패턴 준수)**:
```swift
enum ProviderIdentifier: String, CaseIterable {
    case copilot        // rawValue = "copilot"
    case claude         // rawValue = "claude"
    case codex          // rawValue = "codex"
    case geminiCLI = "gemini_cli"  // explicit snake_case
    case openRouter = "open_router"  // ⚠️ 신규: snake_case
    case openCode = "open_code"      // ⚠️ 신규: snake_case
}
```

**영향**: UserDefaults 키 생성 시 `provider.\(identifier.rawValue).enabled` 패턴 사용
- `provider.open_router.enabled`
- `provider.open_code.enabled`

#### 2. Copilot Submenu 예외 명시

**원 요구사항**: "각 벤더 마우스 올리면 일별/주간한도/리셋시간 등 모든 디테일을 볼 수 있어야함"

**Copilot 예외 처리 (명시적 대체)**:
- Copilot은 hover-submenu 요구사항에서 **예외**
- **대체**: 기존 `CopilotUsageView` (메뉴 상단 전용 뷰)가 동등한 상세 정보 제공
  - 일별 사용량, 월간 한도, 리셋 시간, 추가 요금 등 모두 표시
- **근거**: Copilot은 다른 Provider보다 훨씬 상세한 전용 UI 보유
- **결과**: Copilot의 `ProviderResult.details`는 `nil` 반환 → Submenu 없음

#### 3. Task 7 구조적 문제 해결: `guard !providerResults.isEmpty`

**현재 코드 (StatusBarController.swift:976)**:
```swift
guard !providerResults.isEmpty else { return }
```

**문제**: 다른 Provider가 없으면 Copilot 항목도 표시 안 됨

**해결 방안 (Task 7에서 구현)**:
```swift
private func updateMultiProviderMenu() {
    // ... 기존 아이템 제거 코드 ...
    
    // ⚠️ guard 조건 변경: providerResults OR currentUsage 중 하나라도 있으면 진행
    let hasCopilotData = currentUsage != nil
    guard !providerResults.isEmpty || hasCopilotData else { return }
    
    // ... 섹션 헤더 및 아이템 생성 ...
}
```

**섹션 표시 규칙 (완전 정의)**:

| 조건 | Pay-as-you-go 섹션 | Quota 섹션 |
|------|-------------------|------------|
| providerResults 비어있음 + Copilot 없음 | 함수 조기 return | 함수 조기 return |
| providerResults 비어있음 + Copilot Add-on만 | **Copilot Add-on 표시** | "No providers" 표시 |
| providerResults 비어있음 + Copilot Quota만 | "No providers" 표시 | **Copilot Quota 표시** |
| providerResults 비어있음 + Copilot 둘 다 | **Copilot Add-on 표시** | **Copilot Quota 표시** |
| providerResults 있음 | 혼합 표시 | 혼합 표시 |

**`hasPayAsYouGo` / `hasQuota` 플래그 업데이트 규칙**:
```swift
// Pay-as-you-go 섹션
var hasPayAsYouGo = false

// 1. Copilot Add-on 먼저 체크 (providerResults와 독립적)
if let copilotUsage = currentUsage, copilotUsage.netBilledAmount > 0 {
    // Copilot Add-on 아이템 추가
    hasPayAsYouGo = true  // ⚠️ 플래그 업데이트!
}

// 2. 다른 Provider 순회
for (identifier, result) in providerResults {
    if case .payAsYouGo(...) = result.usage {
        hasPayAsYouGo = true
        // 아이템 추가
    }
}

// 3. "No providers" 표시 여부
if !hasPayAsYouGo {
    // "No providers" placeholder
}
```

**동일 패턴을 Quota 섹션에도 적용**.

### Concrete Deliverables
- `Providers/OpenRouterProvider.swift` - API 기반 Provider
- `Providers/OpenCodeProvider.swift` - API 기반 Provider (API 없으면 비활성화)
- `Models/ProviderProtocol.swift` - 새 ProviderIdentifier 추가
- `Models/ProviderResult.swift` - DetailedUsage 포함 반환 타입
- `Services/TokenManager.swift` - OpenRouter/OpenCode API 키 리더 추가
- `App/StatusBarController.swift` - 메뉴바 아이콘 변경 (StatusBarIconView) 및 Submenu 로직
- `CopilotMonitorTests/OpenRouterProviderTests.swift` - 테스트
- `CopilotMonitorTests/Fixtures/openrouter_*.json` - 테스트 픽스처

### Definition of Done
- [ ] `xcodebuild test -scheme CopilotMonitor` 모든 테스트 통과
- [ ] 앱 실행 시 메뉴바에 `gauge.medium` 아이콘 표시
- [ ] OpenRouter API 키 존재 시 메뉴에 OpenRouter 항목 표시
- [ ] 각 Provider 마우스 호버 시 Submenu로 상세 정보 표시
- [ ] Provider 아이콘이 Assets.xcassets 이미지 사용 (OpenRouter 제외)

### Must Have
- OpenRouter Provider API 기반 구현
- Provider별 Submenu 디테일 (일별/주간/월간 사용량, 리셋시간)
- Assets.xcassets 아이콘 사용
- 메뉴바 SF Symbol `gauge.medium`
- XCTest 추가

### Must NOT Have (Guardrails)
- 기존 CopilotProvider **비즈니스 로직** 변경 (이미 동작 중)
  - ⚠️ 단, Task 6에서 `fetch() -> ProviderResult` 반환 타입 변경 시 **래핑만** 허용:
    ```swift
    // CopilotProvider.swift - 최소 변경만 허용
    func fetch() async throws -> ProviderResult {
        let usage = try await existingFetchLogic()  // 기존 로직 유지
        return ProviderResult(usage: usage, details: nil)  // 래핑만
    }
    ```
- 새 Provider에 대한 WebView 인증 플로우 추가 (기존 auth.json 사용)
- 모델별 사용량 분석 (aggregate만)
- 새로운 Settings UI 패널 추가
- Usage History/Prediction 기능 추가 (Copilot 전용 기능)
- Color 속성으로 텍스트 강조 (AGENTS.md 규칙)
- Emoji 아이콘 사용 (SF Symbols만)

---

## Verification Strategy (MANDATORY)

### Test Decision
- **Infrastructure exists**: YES (XCTest + JSON fixtures)
- **User wants tests**: YES
- **Framework**: XCTest

### Test Structure
각 새 Provider에 대해:
1. JSON fixture 파일 생성
2. Response 디코딩 테스트
3. Usage 계산 로직 테스트
4. Edge case 테스트 (null 값, 인증 실패 등)

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 0 (Preflight - 선행 필수):
└── Task 0: 기존 테스트 불일치 수정

Wave 1 (After Wave 0):
├── Task 1: ProviderIdentifier 및 TokenManager 확장
└── Task 2: 메뉴바 아이콘 SF Symbol 변경

Wave 2 (After Wave 1):
├── Task 3: OpenRouterProvider 구현
├── Task 4: Provider 아이콘 Assets 전환
└── Task 5: OpenCodeProvider 구현

Wave 3 (After Wave 2):
├── Task 6: Submenu 디테일 표시 + ProviderResult 아키텍처 변경
├── Task 7: GitHub Copilot 이중 표시 (Quota + Pay-as-you-go)
└── Task 8: 테스트 및 리팩토링

Wave 4 (After Wave 3):
└── Task 9: 앱 리브랜딩 (OpencodeProvidersMonitor)

Critical Path: Task 0 → Task 1 → Task 3 → Task 6 → Task 9
Parallel Speedup: ~35% faster than sequential
```

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 0 | None | ALL | None (선행 필수) |
| 1 | 0 | 3, 5 | 2 |
| 2 | 0 | 6 | 1 |
| 3 | 1 | 6, 8 | 4, 5 |
| 4 | 0 | 6 | 3, 5 |
| 5 | 1 | 6, 8 | 3, 4 |
| 6 | 2, 3, 4 | 8, 9 | 7 |
| 7 | 3 | 8, 9 | 6 |
| 8 | 3, 5, 6, 7 | None | 9 |
| 9 | 6, 7 | None | 8 |

### Agent Dispatch Summary

| Wave | Tasks | Recommended Agents |
|------|-------|-------------------|
| 0 | 0 | quick category (테스트 수정) |
| 1 | 1, 2 | quick category, parallel background |
| 2 | 3, 4, 5 | unspecified-high category |
| 3 | 6, 7, 8 | visual-engineering for UI, quick for tests |
| 4 | 9 | unspecified-low category (텍스트 치환 위주) |

---

## TODOs

- [x] 0. Preflight: 기존 테스트 불일치 수정

  **What to do**:
  - 현재 main 브랜치에서 `xcodebuild test` 실행하여 기존 상태 확인
  - `CodexProviderTests.swift`와 `CodexProvider.swift` 사이의 타입 불일치 수정:
    - **문제**: `CodexProviderTests.swift:22-24`는 `provider.type == .payAsYouGo` 기대
    - **실제**: `CodexProvider.swift:8`은 `let type: ProviderType = .quotaBased`
    - **⚠️ 정답 소스 결정: 코드 구현(CodexProvider.swift)이 정답**
      - 근거: Codex는 quota 소진 후 추가 과금 모델 → `.quotaBased`가 의미상 맞음
      - README.md는 오래된 정보 → 나중에 업데이트 (이 Task 범위 외)
    - **수정 대상**: 테스트 파일 수정 (Provider 구현이 정답)
      ```swift
      // CodexProviderTests.swift:22-24 변경
      XCTAssertEqual(provider.type, .quotaBased)  // .payAsYouGo → .quotaBased
      ```
  - 모든 기존 테스트가 통과하는지 확인
  
  **⚠️ README.md 불일치 처리**:
  - README.md:30-33, 163-170에서 Codex를 "Pay-as-you-go"로 설명
  - **이 Task에서는 수정하지 않음** (Task 9 리브랜딩에서 README 전체 업데이트 예정)
  - 단, Task 9에서 README의 Provider 분류를 코드와 일치시킬 것

  **Must NOT do**:
  - 새 기능 관련 변경 (이 Task는 기존 코드만 수정)
  - 테스트 삭제 (수정만)
  - Provider 구현 변경 (테스트만 수정)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: 기존 불일치 수정, 단순 작업
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 0 (선행 필수)
  - **Blocks**: ALL Tasks (테스트 기반 확보)
  - **Blocked By**: None

  **References**:
  
  - `CopilotMonitorTests/CodexProviderTests.swift:22-24` - 테스트 기대값
  - `Providers/CodexProvider.swift:8` - 실제 타입 정의
  
  **WHY This Task Exists**:
  - Task 8의 DoD "전체 테스트 통과"가 현재 상태에서는 달성 불가능
  - 이 불일치를 먼저 수정해야 새 기능 테스트를 추가할 수 있음

  **Acceptance Criteria**:
  
  **Automated Verification (using Bash)**:
  ```bash
  # 모든 기존 테스트 통과 확인
  xcodebuild test -project CopilotMonitor/CopilotMonitor.xcodeproj \
    -scheme CopilotMonitor -destination 'platform=macOS' 2>&1 | grep -E "Test.*passed|FAILED"
  # Assert: All tests passed, no FAILED
  ```

  **Commit**: YES
  - Message: `fix(test): align CodexProvider type with test expectations`
  - Files: `Providers/CodexProvider.swift` 또는 `CopilotMonitorTests/CodexProviderTests.swift`
  - Pre-commit: `xcodebuild test`

---

- [ ] 1. ProviderIdentifier 및 TokenManager 확장 (컴파일 가능한 최소 변경)

  **What to do**:
  - `ProviderIdentifier` enum에 `.openRouter`, `.openCode` case 추가
    - **⚠️ rawValue 명시 필수** (snake_case 패턴):
      ```swift
      case openRouter = "open_router"  // NOT "openRouter"
      case openCode = "open_code"      // NOT "openCode"
      ```
    - 근거: 기존 `.geminiCLI = "gemini_cli"` 패턴과 일관성
    - 영향: UserDefaults 키 `provider.open_router.enabled` 형식
  - `ProviderIdentifier.displayName` 계산 속성 확장
  - `TokenManager`에 `getOpenRouterAPIKey()` 메서드 추가
  - `TokenManager`에 `getOpenCodeAPIKey()` 메서드 추가
  - `OpenCodeAuth` 구조체에 `APIKey` 내부 struct 추가 및 `openrouter`, `opencode` 필드 추가
  - **Technical Design Decisions 섹션의 "1. auth.json 스키마 확장 설계" 참조**
  
  **⚠️ 컴파일 브레이크 방지 (필수)**:
  - `StatusBarController.swift:1065+ iconForProvider()` switch에 `.openRouter`, `.openCode` case 추가
    ```swift
    case .openRouter:
        return NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "OpenRouter")
    case .openCode:
        return NSImage(named: "OpencodeIcon")
    ```
  - `MultiProviderStatusBarIconView.swift:133+ drawProviderAlert()` switch에 새 case 추가
    ```swift
    case .openRouter, .openCode:
        // SF Symbol 또는 Assets 아이콘 사용
    ```

  **Must NOT do**:
  - 기존 OAuth struct 변경
  - 기존 anthropic/openai/githubCopilot 필드 변경

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: 단순 enum 추가 및 구조체 확장, 복잡도 낮음
  - **Skills**: []
    - 특별한 skill 필요 없음
  - **Skills Evaluated but Omitted**:
    - `git-master`: 커밋은 마지막에 일괄 처리

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 2)
  - **Blocks**: Tasks 3, 5
  - **Blocked By**: None

  **References**:
  
  **Pattern References**:
  - `Models/ProviderProtocol.swift` - `enum ProviderIdentifier: String, CaseIterable` (line 12-35)
    - 현재 case: `.copilot`, `.claude`, `.codex`, `.geminiCLI`
    - `displayName` computed property (line 23-34)
  
  **API/Type References**:
  - `Services/TokenManager.swift` - `struct OpenCodeAuth: Codable` (line 8-31)
    - 현재: `OAuth` nested struct만 있음
    - 추가할 것: `APIKey` nested struct (`type: String`, `key: String`)
  - `Services/TokenManager.swift` - `getAnthropicAccessToken()` 등 (line 124-141)
    - 동일 패턴으로 `getOpenRouterAPIKey()`, `getOpenCodeAPIKey()` 추가
  
  **⚠️ 컴파일 브레이크 방지용 추가 수정 (필수)**:
  - `App/StatusBarController.swift` - `iconForProvider(_:)` (line 1065-1078)
    - 현재 switch는 4 case만 있음 → `.openRouter`, `.openCode` 추가 필수
  - `Views/MultiProviderStatusBarIconView.swift` - `drawProviderAlert()` (line 133+)
    - 현재 switch는 4 case만 있음 → `.openRouter`, `.openCode` 추가 필수
  
  **Documentation References**:
  - 실제 auth.json 구조 (검증됨):
    ```json
    {
      "openai": { "type": "oauth", "refresh": "...", "access": "...", "expires": 123 },
      "openrouter": { "type": "api", "key": "sk-or-v1-..." },
      "opencode": { "type": "api", "key": "sk-..." }
    }
    ```
  - Technical Design Decisions 섹션 참조: auth.json 스키마 확장 설계
  
  **WHY Each Reference Matters**:
  - `ProviderIdentifier` enum은 `CaseIterable`이므로 새 case 추가 시 전체 Provider 목록에 자동 포함
  - `OpenCodeAuth`의 `CodingKeys`에 새 필드 추가 필요 (camelCase)
  - `APIKey` struct는 `OAuth` struct와 다른 필드 구조 (`key` vs `access/refresh`)

  **Acceptance Criteria**:
  
  **Automated Verification (using Bash)**:
  ```bash
  # Build succeeds with new ProviderIdentifier cases
  xcodebuild -project CopilotMonitor/CopilotMonitor.xcodeproj \
    -scheme CopilotMonitor -configuration Debug build 2>&1 | grep -E "(BUILD|error:)"
  # Assert: BUILD SUCCEEDED
  
  # Verify new cases exist
  grep -n "case openRouter" CopilotMonitor/CopilotMonitor/Models/ProviderProtocol.swift
  # Assert: Line number returned (case exists)
  
  grep -n "case openCode" CopilotMonitor/CopilotMonitor/Models/ProviderProtocol.swift
  # Assert: Line number returned (case exists)
  
  # Verify APIKey struct added
  grep -n "struct APIKey" CopilotMonitor/CopilotMonitor/Services/TokenManager.swift
  # Assert: Line number returned
  
  # Verify new accessor methods
  grep -n "func getOpenRouterAPIKey" CopilotMonitor/CopilotMonitor/Services/TokenManager.swift
  # Assert: Line number returned
  ```

  **Commit**: YES - groups with Task 2
  - Message: `feat(provider): add OpenRouter and OpenCode provider identifiers`
  - Files: `Models/ProviderProtocol.swift`, `Services/TokenManager.swift`
  - Pre-commit: `xcodebuild build`

---

- [ ] 2. 메뉴바 아이콘 SF Symbol gauge.medium 변경

  **What to do**:
  - `StatusBarController.swift`의 `StatusBarIconView` 클래스 (line 59-158) 수정
  - `drawCopilotIcon()` 메서드 (line 130-145)를 SF Symbol `gauge.medium` 렌더링으로 변경
  - `draw()` 메서드 (line 114-128)에서 호출하는 아이콘 렌더링 로직 수정

  **색상 변경 로직 명확화**:
  - **`drawCircularProgress()` 현재 구현** (line 147-176): 모든 요소가 **`NSColor.white` 고정**
    - Line 152: `NSColor.white.withAlphaComponent(0.2)` - 배경 링
    - Line 159: `NSColor.white.withAlphaComponent(0.6)` - 채워진 진행률
    - Line 168: `NSColor.white.withAlphaComponent(0.6)` - 대체 진행률
    - Line 176: `NSColor.white` - 메인 진행률 링
    - **⚠️ 현재 percentage 기반 색상 변경 없음** (green→yellow→orange→red 아님)
  - **아이콘 자체**: SF Symbol은 흰색(template mode)으로 렌더링 - 색상 변경 없음
  - **변경 대상**: `drawCopilotIcon()` 메서드만 (CopilotIcon → SF Symbol)
  - **Progress ring은 그대로 유지** (현재 흰색 고정, 색상 로직 추가는 scope 외)

  **Must NOT do**:
  - 기존 progress bar 색상 로직 변경 (`drawCircularProgress` 유지)
  - StatusBarIconView의 전체 레이아웃 변경
  - `intrinsicContentSize` 계산 로직 변경 (width 계산 유지)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: 단일 아이콘 변경, 기존 로직 유지
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - `frontend-ui-ux`: macOS AppKit 특화, web UI 아님

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 1)
  - **Blocks**: Task 6
  - **Blocked By**: None

  **References**:
  
  **Pattern References**:
  - `App/StatusBarController.swift:59-158` - StatusBarIconView 클래스 전체 정의 (메뉴바 아이콘 뷰)
  - `App/StatusBarController.swift:114-128` - draw() 메서드: 아이콘 + 진행률 + 텍스트 렌더링
  - `App/StatusBarController.swift:130-145` - drawCopilotIcon() 메서드: **수정 대상** - 현재 CopilotIcon 렌더링
  - `App/StatusBarController.swift:66-86` - intrinsicContentSize: baseIconWidth 계산 (16px 아이콘 기준)
  
  **API/Type References**:
  - `NSImage(systemSymbolName:accessibilityDescription:)` - SF Symbol 로드 방법
  - `NSImage.withSymbolConfiguration()` - SF Symbol 크기/weight 설정
  
  **External References**:
  - SF Symbols 앱에서 `gauge.medium` 확인 (macOS 13+에서 사용 가능)
  
  **WHY Each Reference Matters**:
  - `StatusBarIconView` (NOT MultiProviderStatusBarIconView)가 실제 메뉴바 아이콘을 그리는 클래스
  - `drawCopilotIcon()`를 수정해야 SF Symbol로 변경됨
  - `MultiProviderStatusBarIconView`는 Alert용 별도 뷰 (메뉴바 아이콘 아님)

  **Acceptance Criteria**:
  
  **Automated Verification (using Bash)**:
  ```bash
  # Build and run app
  pkill -x CopilotMonitor 2>/dev/null || true
  xcodebuild -project CopilotMonitor/CopilotMonitor.xcodeproj \
    -scheme CopilotMonitor -configuration Debug build
  open ~/Library/Developer/Xcode/DerivedData/CopilotMonitor-*/Build/Products/Debug/CopilotMonitor.app
  sleep 3
  
  # Verify SF Symbol is used in StatusBarIconView
  grep -n "gauge.medium" CopilotMonitor/CopilotMonitor/App/StatusBarController.swift
  # Assert: At least one match found in StatusBarIconView section (lines 59-158)
  
  # Verify old Copilot icon reference removed from StatusBarIconView draw method
  grep -A5 "func drawCopilotIcon" CopilotMonitor/CopilotMonitor/App/StatusBarController.swift | grep -c "CopilotIcon" || echo "0"
  # Assert: Returns 0 (CopilotIcon replaced with SF Symbol)
  ```
  
  **Manual Visual Verification**:
  - 앱 실행 후 메뉴바에 게이지 모양 아이콘 확인

  **Commit**: YES - groups with Task 1
  - Message: `feat(ui): change menu bar icon to SF Symbol gauge.medium`
  - Files: `App/StatusBarController.swift`
  - Pre-commit: `xcodebuild build`

---

- [x] 3. OpenRouterProvider 구현

  **What to do**:
  - `Providers/OpenRouterProvider.swift` 파일 생성
  - `ProviderProtocol` 구현
  - `/api/v1/credits` 및 `/api/v1/key` API 호출
  - Response 디코딩 구조체 정의:
    ```swift
    struct OpenRouterCreditsResponse: Codable {
        struct Data: Codable {
            let total_credits: Double
            let total_usage: Double
        }
        let data: Data
    }
    
    struct OpenRouterKeyResponse: Codable {
        struct Data: Codable {
            let limit: Double?
            let limit_remaining: Double?
            let limit_reset: String?
            let usage_daily: Double
            let usage_weekly: Double
            let usage_monthly: Double
        }
        let data: Data
    }
    ```
  - `ProviderUsage.payAsYouGo` 반환 (remaining credits 기반)
  - `ProviderManager`에 OpenRouterProvider 등록

  **Must NOT do**:
  - 모델별 사용량 분석 구현 (aggregate만)
  - 캐싱 로직 추가 (다른 Provider도 없음)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: 새 Provider 구현, API 통합, 여러 파일 수정 필요
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - `playwright`: API 테스트는 curl로 충분

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 4, 5)
  - **Blocks**: Tasks 6, 7, 8
  - **Blocked By**: Task 1

  **References**:
  
  **Pattern References**:
  - `Providers/CodexProvider.swift:26-78` - API 기반 Provider fetch() 구현 패턴
  - `Providers/CodexProvider.swift:10-24` - Response 구조체 정의 패턴
  - `Providers/ClaudeProvider.swift:6-8` - identifier, type 설정 패턴
  
  **API/Type References**:
  - `Models/ProviderUsage.swift:4-5` - `.payAsYouGo(utilization:resetsAt:)` 사용법
  - `Models/ProviderProtocol.swift:41-48` - ProviderProtocol 인터페이스
  
  **External References**:
  - OpenRouter API 응답 (실제 테스트됨):
    ```json
    // GET /api/v1/credits
    { "data": { "total_credits": 6685, "total_usage": 6548.72 } }
    
    // GET /api/v1/key  
    { "data": { 
        "limit": 100, "limit_remaining": 99.99, "limit_reset": "weekly",
        "usage_daily": 0, "usage_weekly": 0.004, "usage_monthly": 37.41
      } 
    }
    ```
  - Auth: `Authorization: Bearer <api_key>` 헤더
  
  **OpenRouter API → DetailedUsage 매핑 (명확화)**:
  
  | API 필드 | DetailedUsage 필드 | 변환 |
  |----------|-------------------|------|
  | `usage_daily` | `dailyUsage` | 그대로 Double |
  | `usage_weekly` | `weeklyUsage` | 그대로 Double |
  | `usage_monthly` | `monthlyUsage` | 그대로 Double |
  | `total_credits` | `totalCredits` | 그대로 Double |
  | `total_credits - total_usage` | `remainingCredits` | 계산 |
  | `limit` | `limit` | 그대로 Double? |
  | `limit_remaining` | `limitRemaining` | 그대로 Double? |
  | `limit_reset` | `resetPeriod` | 그대로 String? |
  
  **OpenRouterProvider.fetch() 구현 스니펫**:
  ```swift
  func fetch() async throws -> ProviderResult {
      // 1. /api/v1/credits 호출
      let creditsResponse = try await fetchCredits()
      
      // 2. /api/v1/key 호출
      let keyResponse = try await fetchKey()
      
      // 3. utilization 계산 (퍼센트) - ⚠️ division by zero 방지
      let utilization: Double
      if creditsResponse.data.total_credits > 0 {
          utilization = (creditsResponse.data.total_usage / creditsResponse.data.total_credits) * 100
      } else {
          // 신규 계정 또는 크레딧 미충전
          utilization = 0.0
      }
      
      // 4. DetailedUsage 생성
      let details = DetailedUsage(
          dailyUsage: keyResponse.data.usage_daily,
          weeklyUsage: keyResponse.data.usage_weekly,
          monthlyUsage: keyResponse.data.usage_monthly,
          totalCredits: creditsResponse.data.total_credits,
          remainingCredits: creditsResponse.data.total_credits - creditsResponse.data.total_usage,
          limit: keyResponse.data.limit,
          limitRemaining: keyResponse.data.limit_remaining,
          resetPeriod: keyResponse.data.limit_reset
      )
      
      // 5. ProviderResult 반환
      return ProviderResult(
          usage: .payAsYouGo(utilization: utilization, resetsAt: nil),
          details: details
      )
  }
  ```
  
  **Edge Case 테스트 (Task 8에 포함)**:
  ```swift
  func testUtilizationWithZeroCredits() {
      // Given: total_credits = 0
      let fixture = loadFixture("openrouter_zero_credits.json")
      // When: calculate utilization
      // Then: utilization = 0.0 (not NaN, not crash)
  }
  ```
  
  **WHY Each Reference Matters**:
  - CodexProvider가 API 기반 Provider의 가장 좋은 참조 예시
  - ProviderUsage.payAsYouGo 선택 이유: OpenRouter는 크레딧 기반 (quota 아님)

  **Acceptance Criteria**:
  
  **Automated Verification (using Bash)**:
  ```bash
  # 1. Build succeeds
  xcodebuild -project CopilotMonitor/CopilotMonitor.xcodeproj \
    -scheme CopilotMonitor -configuration Debug build 2>&1 | grep -E "BUILD"
  # Assert: BUILD SUCCEEDED
  
  # 2. Provider file exists with correct structure
  grep -c "class OpenRouterProvider: ProviderProtocol" \
    CopilotMonitor/CopilotMonitor/Providers/OpenRouterProvider.swift
  # Assert: Returns 1
  
  # 3. API endpoint is correct
  grep -c "openrouter.ai/api/v1" \
    CopilotMonitor/CopilotMonitor/Providers/OpenRouterProvider.swift
  # Assert: Returns 2 (credits + key endpoints)
  
  # 4. Real API test (requires network)
  curl -s https://openrouter.ai/api/v1/credits \
    -H "Authorization: Bearer $(jq -r '.openrouter.key' ~/.local/share/opencode/auth.json)" \
    | jq -e '.data.total_credits'
  # Assert: Returns number (API works)
  ```

  **Commit**: YES
  - Message: `feat(provider): implement OpenRouterProvider with credits/key API`
  - Files: `Providers/OpenRouterProvider.swift`, `Services/ProviderManager.swift`
  - Pre-commit: `xcodebuild build`

---

- [x] 4. Provider 아이콘 Assets.xcassets 전환

  **What to do**:
  - `StatusBarController.iconForProvider()` 메서드 수정 (line 1065-1078)
  - SF Symbols 대신 Assets.xcassets 이미지 사용:
    - `.copilot` → `NSImage(named: "CopilotIcon")`
    - `.claude` → `NSImage(named: "ClaudeIcon")`
    - `.codex` → `NSImage(named: "CodexIcon")`
    - `.geminiCLI` → `NSImage(named: "GeminiIcon")`
    - `.openCode` → `NSImage(named: "OpencodeIcon")`
    - `.openRouter` → SF Symbol `arrow.triangle.branch` (Assets에 없음)
  - 아이콘 크기 조정 (16x16 또는 메뉴 아이템 표준 크기)

  **Must NOT do**:
  - 새로운 아이콘 디자인
  - 아이콘 tinting 로직 변경 (기존 유지)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: 단순 아이콘 소스 변경
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - `frontend-ui-ux`: AppKit NSImage 변경은 단순 작업

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 3, 5)
  - **Blocks**: Task 6
  - **Blocked By**: None (하지만 Task 1 이후 실행 권장)

  **References**:
  
  **Pattern References**:
  - `App/StatusBarController.swift:1065-1078` - 현재 iconForProvider() 구현
  - `App/StatusBarController.swift:1080-1089` - tintedImage() - 기존 tinting 로직 유지
  
  **API/Type References**:
  - `NSImage(named:)` - Assets.xcassets 이미지 로드 방법
  
  **Documentation References**:
  - Assets.xcassets 구조:
    - CopilotIcon.imageset/copilot-icon.pdf
    - ClaudeIcon.imageset/claude-icon.pdf
    - CodexIcon.imageset/codex-icon.pdf
    - GeminiIcon.imageset/gemini-icon.pdf
    - OpencodeIcon.imageset/opencode-icon.pdf
  
  **WHY Each Reference Matters**:
  - iconForProvider() 메서드가 모든 Provider 아이콘의 중앙 관리 지점
  - tintedImage()는 경고 상태 (< 20% quota) 표시에 사용되므로 유지 필요

  **Acceptance Criteria**:
  
  **Automated Verification (using Bash)**:
  ```bash
  # Verify SF Symbols removed from iconForProvider (except OpenRouter)
  grep -A20 "func iconForProvider" CopilotMonitor/CopilotMonitor/App/StatusBarController.swift \
    | grep -c "systemSymbolName"
  # Assert: Returns 1 (only OpenRouter uses SF Symbol)
  
  # Verify Assets usage
  grep -A20 "func iconForProvider" CopilotMonitor/CopilotMonitor/App/StatusBarController.swift \
    | grep -c 'NSImage(named:'
  # Assert: Returns 5 (Copilot, Claude, Codex, Gemini, OpenCode)
  
  # Build succeeds
  xcodebuild -project CopilotMonitor/CopilotMonitor.xcodeproj \
    -scheme CopilotMonitor -configuration Debug build 2>&1 | grep "BUILD"
  # Assert: BUILD SUCCEEDED
  ```

  **Commit**: YES
  - Message: `feat(ui): switch provider icons to Assets.xcassets images`
  - Files: `App/StatusBarController.swift`
  - Pre-commit: `xcodebuild build`

---

- [x] 5. OpenCodeProvider 구현

  **What to do**:
  - `Providers/OpenCodeProvider.swift` 파일 생성
  - `ProviderProtocol` 구현
  - **우선 API 탐색**: `https://api.opencode.ai/` 엔드포인트 확인
    - API 있으면: HTTP 요청으로 잔액/사용량 조회
    - API 없으면: Provider 비활성화 (WebView 로그인 플로우 없음)
  - API 키: `TokenManager.getOpenCodeAPIKey()` 사용
  - `ProviderUsage.payAsYouGo` 반환
  - API 키 없으면 Provider skip (not error)
  - `ProviderManager`에 등록
  - **가져올 정보**: 잔액($XX.XX), 이번 달 사용량 (가능한 경우)

  **Must NOT do**:
  - 새로운 WebView 인증 플로우 구현 (기존 auth.json 활용)
  - WebView 창 띄우기 (사용자 인터랙션 금지)
  - 복잡한 DOM 파싱
  - **Technical Design Decisions 섹션의 "3. OpenCodeProvider WebView 플로우" 참조**

  **최종 동작 결정**:
  - API 존재 시: Provider 정상 등록, 메뉴에 표시
  - **API 미존재 시: Provider를 메뉴에서 숨김 (비활성화)**
  - "Coming Soon" 표시 없음 - 단순히 메뉴에서 제외
  - WebView/DOM 파싱 절대 사용 안 함

  **"비활성화" 구체적 정의 (API 에러 핸들링)**:
  
  실제 `ProviderError` enum (`Models/ProviderProtocol.swift:52-78`):
  ```swift
  enum ProviderError: LocalizedError {
      case authenticationFailed(String)  // ⚠️ 연관값 있음!
      case networkError(String)
      case decodingError(String)
      case providerError(String)
      case unsupported(String)
  }
  ```
  
  | 상황 | 에러 코드 | 동작 |
  |------|----------|------|
  | API 키 미존재 | - | `throw ProviderError.authenticationFailed("API key not found")` → 숨김 (캐시 무시) |
  | API 401 Unauthorized | 401 | `throw ProviderError.authenticationFailed("401 Unauthorized")` → 숨김 (캐시 무시) |
  | API 404 Not Found | 404 | `throw ProviderError.authenticationFailed("API not found (404)")` → 숨김 (캐시 무시) |
  | API 5xx / Timeout | 5xx, timeout | `throw ProviderError.networkError("Server error")` → 캐시 fallback |
  | API 200 OK | 200 | 정상 응답 → Provider 메뉴에 표시 |
  
  **⚠️ "숨김 보장" 통합 규칙**:
  - `authenticationFailed` 에러는 모두 캐시 무시 → 진짜 숨김
  - OpenRouter도 동일 규칙 적용 (API 키 없으면 authenticationFailed)
  - 404는 "API 미존재"로 간주 → authenticationFailed 사용 (캐시 무시)
  
  **로깅 패턴** (현재 코드베이스와 일치):
  ```swift
  // 파일 상단에 private logger 정의 (기존 패턴)
  private let logger = Logger(subsystem: "com.copilotmonitor", category: "OpenCodeProvider")
  
  // 사용 예시
  logger.debug("OpenCode API not available")
  logger.error("Failed to fetch: \(error.localizedDescription)")
  ```
  
  **ProviderManager.fetchAll() 동작** (`ProviderManager.swift:47-99`):
  ```swift
  // 현재 구현: Provider가 throw하면 results에서 자동 제외
  for provider in enabledProviders {
      do {
          let result = try await fetchWithTimeout(provider: provider)
          results[provider.identifier] = result
      } catch {
          // 에러 발생 시 해당 Provider는 results에 포함 안 됨
          // → StatusBarController.updateMultiProviderMenu()에서 자동으로 표시 안 됨
          Logger.error("Provider \(provider.identifier) failed: \(error)")
      }
  }
  ```
  
  **결과**: Provider가 에러를 throw하면 `providerResults` dictionary에서 제외 → 메뉴에서 자연스럽게 숨겨짐

  **⚠️ 캐시 Fallback 동작과의 충돌 해결**:
  
  현재 `ProviderManager.fetchAll()` (line 69-79)은 에러 시 캐시 fallback을 사용:
  ```swift
  } catch {
      // Try to use cached value as fallback
      let cached = await self.getCache(identifier: provider.identifier)
      if cached != nil {
          logger.warning("Using cached value for \(provider.identifier.displayName)")
      }
      return (provider.identifier, cached)  // 캐시가 있으면 반환!
  }
  ```
  
  **문제**: API 키 제거/API 미존재 시에도 과거 성공 캐시가 있으면 계속 표시됨
  
  **해결 방안 (OpenCodeProvider 전용)**:
  ```swift
  // OpenCodeProvider.fetch()에서 인증 실패 시 캐시 무효화
  func fetch() async throws -> ProviderResult {
      guard let apiKey = tokenManager.getOpenCodeAPIKey() else {
          // 키 없으면 캐시 무효화 신호 → ProviderError.authenticationFailed throw
          // ⚠️ 이 에러는 ProviderManager에서 캐시 fallback을 사용하지 않도록 특별 처리 필요
throw ProviderError.authenticationFailed("API key not found")
      }
      
      // API 호출...
      // 404/401 응답 시에도 authenticationFailed throw
  }
  ```
  
  **ProviderManager 수정 (Task 6에서 함께 처리)**:
  ```swift
  } catch let error as ProviderError {
      switch error {
      case .authenticationFailed(let message):
          // 인증 실패는 캐시 fallback 사용 안 함 → 진짜 숨김
          logger.warning("\(provider.identifier.displayName) auth failed: \(message), not using cache")
          return (provider.identifier, nil)  // 캐시 무시
      default:
          // 그 외 에러는 캐시 fallback
          let cached = await self.getCache(identifier: provider.identifier)
          if cached != nil {
              logger.warning("Using cached value for \(provider.identifier.displayName)")
          }
          return (provider.identifier, cached)
      }
  } catch {
      // 알 수 없는 에러도 캐시 fallback
      let cached = await self.getCache(identifier: provider.identifier)
      return (provider.identifier, cached)
  }
  ```
  
  **"숨김 보장(캐시 무시)" 적용 범위 결정: API-key 기반 Provider만**
  
  | Provider | 유형 | authenticationFailed 시 캐시 |
  |----------|------|---------------------------|
  | OpenRouter | API-key | ❌ 무시 (숨김) |
  | OpenCode | API-key | ❌ 무시 (숨김) |
  | Claude | OAuth | ✅ fallback (토큰 만료 시 캐시 표시) |
  | Codex | OAuth | ✅ fallback |
  | GeminiCLI | OAuth | ✅ fallback |
  | Copilot | OAuth/WebView | ✅ fallback |
  
  **결정 근거**:
  - API-key Provider: 키 제거/미존재 = 의도적 비활성화 → 캐시 표시 불필요
  - OAuth Provider: 토큰 만료 = 일시적 문제 → 캐시 표시로 UX 유지
  
  **구현 방법 (ProviderManager 수정)**:
  ```swift
  } catch let error as ProviderError {
      switch error {
      case .authenticationFailed(let message):
          // API-key 기반 Provider만 캐시 무시
          let isAPIKeyProvider = [.openRouter, .openCode].contains(provider.identifier)
          if isAPIKeyProvider {
              logger.warning("\(provider.identifier.displayName) auth failed: \(message), hiding")
              return (provider.identifier, nil)  // 캐시 무시
          } else {
              // OAuth Provider는 캐시 fallback
              let cached = await self.getCache(identifier: provider.identifier)
              return (provider.identifier, cached)
          }
      default:
          let cached = await self.getCache(identifier: provider.identifier)
          return (provider.identifier, cached)
      }
  }
  ```
  
  **기존 Provider에 미치는 영향**:
  - Claude/Codex/GeminiCLI/Copilot: 변경 없음 (기존과 동일하게 캐시 fallback)
  - Acceptance Criteria에 추가: "기존 Provider의 토큰 만료 시 캐시 표시 유지 확인"

  **구현 우선순위**:
  1. API 엔드포인트 탐색 (아래 순서대로 시도)
  2. API 있으면 → HTTP 클라이언트로 구현 (OpenRouterProvider 패턴)
  3. API 없으면 → ProviderManager에서 등록 안 함 (메뉴에서 숨김)

  **OpenCode API 탐색 계획 (확정된 순서)**:
  
  ```bash
  # 탐색 순서 (1→2→3→4 순서로 시도, 첫 200 OK에서 중단)
  API_KEY=$(jq -r '.opencode.key' ~/.local/share/opencode/auth.json)
  
  # 1. 크레딧/잔액 엔드포인트
  curl -s -w "\n%{http_code}" https://api.opencode.ai/v1/credits \
    -H "Authorization: Bearer $API_KEY"
  
  # 2. 사용량 엔드포인트
  curl -s -w "\n%{http_code}" https://api.opencode.ai/v1/usage \
    -H "Authorization: Bearer $API_KEY"
  
  # 3. 계정 정보 엔드포인트
  curl -s -w "\n%{http_code}" https://api.opencode.ai/v1/account \
    -H "Authorization: Bearer $API_KEY"
  
  # 4. 대체 도메인 (opencode.com)
  curl -s -w "\n%{http_code}" https://api.opencode.com/v1/credits \
    -H "Authorization: Bearer $API_KEY"
  ```
  
  **API 발견 시 예상 응답 스키마 (가정)**:
  ```json
  // 가정: OpenRouter와 유사한 구조
  {
    "data": {
      "total_credits": 100.0,    // Double - 총 크레딧
      "used_credits": 45.0,      // Double - 사용한 크레딧
      "remaining_credits": 55.0  // Double - 남은 크레딧
    }
  }
  ```
  
  **API 발견 시 DetailedUsage 매핑**:
  | API 필드 | DetailedUsage 필드 |
  |----------|-------------------|
  | `total_credits` | `totalCredits` |
  | `remaining_credits` | `remainingCredits` |
  | `used_credits` (또는 월별) | `monthlyUsage` (가능한 경우) |
  
  **utilization 계산식** (API 발견 시):
  ```swift
  // used / total * 100
  let utilization = (usedCredits / totalCredits) * 100
  ```
  
  **API 미발견 시 동작**:
  - 모든 엔드포인트가 404/401 반환 → `throw ProviderError.authenticationFailed("API not available")`
  - 5xx 반환 → `throw ProviderError.networkError("Server error")`
  - ProviderManager에서 자동 제외 → 메뉴에 표시 안 됨
  - **로그만 기록**: `logger.debug("OpenCode API not available")`
  
  **API 발견 시 스키마 불확실성 처리 규칙**:
  
  200 OK 응답을 받았으나 스키마가 예상과 다를 때:
  
  | 상황 | 처리 |
  |------|------|
  | 예상 필드(`total_credits` 등) 존재 | 정상 파싱 → Provider 표시 |
  | 필수 필드 누락 | `throw ProviderError.decodingError("Missing required fields")` → 캐시 fallback |
  | JSON 형식 아님 | `throw ProviderError.decodingError("Invalid JSON")` → 캐시 fallback |
  | 완전히 다른 스키마 | `throw ProviderError.authenticationFailed("Unsupported API schema")` → 숨김 |
  
  **필수 필드 정의 (유연 파싱)**:
  - **최소 필수**: `total_credits` 또는 `balance` 또는 `credits` (하나만 있으면 됨)
  - **선택**: `used_credits`, `remaining_credits`, `usage_*`
  
  **파싱 우선순위**:
  ```swift
  // 크레딧 필드 후보 (우선순위대로 시도)
  let totalCredits = data["total_credits"] ?? data["balance"] ?? data["credits"]
  guard let total = totalCredits as? Double else {
      throw ProviderError.authenticationFailed("Unsupported API schema")
  }
  ```
  
  **Task 8 테스트 관련 (API 발견/미발견 분기)**:
  
  **⚠️ OpenCode 테스트 전략 (단일 정답)**:
  
  | 시나리오 | 테스트 | DoD |
  |----------|--------|-----|
  | **API 발견** | fixture + 디코딩 + 계산 테스트 | 테스트 통과 + 메뉴 표시 |
  | **API 미발견** (404/401) | `testAPINotFoundThrowsAuthError` | throw 확인 + 메뉴 미표시 |
  | **API 키 없음** | `testNoAPIKeyThrowsAuthError` | throw 확인 + 메뉴 미표시 |
  
  **API 미발견 시 테스트 (필수)**:
  ```swift
  // OpenCodeProviderTests.swift - API 미발견 케이스
  func testAPINotFoundThrowsAuthenticationFailed() async throws {
      // Given: 404 응답을 반환하는 mock
      let provider = OpenCodeProvider(httpClient: Mock404Client())
      
      // When/Then: authenticationFailed throw
      do {
          _ = try await provider.fetch()
          XCTFail("Should throw authenticationFailed")
      } catch let error as ProviderError {
          if case .authenticationFailed(let message) = error {
              XCTAssertTrue(message.contains("404") || message.contains("not available"))
          } else {
              XCTFail("Wrong error type: \(error)")
          }
      }
  }
  
  func testNoAPIKeyThrowsAuthenticationFailed() async throws {
      // Given: API 키 없는 TokenManager mock
      let provider = OpenCodeProvider(tokenManager: MockEmptyTokenManager())
      
      // When/Then
      do {
          _ = try await provider.fetch()
          XCTFail("Should throw")
      } catch let error as ProviderError {
          if case .authenticationFailed(_) = error {
              // Expected
          } else {
              XCTFail("Wrong error type")
          }
      }
  }
  ```
  
  **CI 환경 호환성**:
  - OpenCode API가 없는 CI에서도 테스트 통과
  - mock 기반 테스트로 실제 API 호출 없음
  - "API 미발견"이 정상 동작임을 테스트로 증명

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: API 탐색 필요, 불확실성 있음
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - `playwright`: API 우선 접근, WebView 사용 안함
    - `dev-browser`: 동일 이유

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 3, 4)
  - **Blocks**: Tasks 6, 8
  - **Blocked By**: Task 1

  **References**:
  
  **Pattern References**:
  - `Providers/CodexProvider.swift` - HTTP API 기반 Provider 패턴 (line 10-78)
    - URLSession.shared.data(for:) 사용
    - Response 디코딩 구조체 정의
    - 인증 헤더 설정
  - `Providers/OpenRouterProvider.swift` (Task 3에서 생성) - 동일 API 키 패턴
  
  **API/Type References**:
  - `TokenManager.getOpenCodeAPIKey()` - API 키 조회 (Task 1에서 추가)
  - `ProviderUsage.payAsYouGo(utilization:resetsAt:)` - 반환 타입
  - `ProviderError.authenticationFailed` - 키 없을 때 에러
  
  **External References (탐색 필요)**:
  - **⚠️ OpenCode API 문서**: 공식 API 문서 미확인 (https://opencode.ai/docs/api 404 반환)
  - **⚠️ OpenCode 대시보드**: 공식 대시보드 URL 미확인 (https://opencode.ai/dashboard 404 반환)
  - **탐색 전략**: 실제 curl 테스트로 API 엔드포인트 존재 여부 확인
  - 테스트 커맨드:
    ```bash
    # API 키로 잔액 조회 시도
    curl -s https://api.opencode.ai/v1/credits \
      -H "Authorization: Bearer $(jq -r '.opencode.key' ~/.local/share/opencode/auth.json)"
    ```
  
  **WHY Each Reference Matters**:
  - CodexProvider가 HTTP API Provider의 가장 좋은 참조
  - API 우선 접근으로 WebView 복잡도 회피
  - 실패 시 graceful degradation (Provider 숨김)

  **Acceptance Criteria**:
  
  **⚠️ DoD 분기 (API 발견/미발견 모두 "완료"로 인정)**:
  
  | 시나리오 | 완료 조건 |
  |----------|----------|
  | **API 발견** | Provider 메뉴 표시 + 테스트 통과 + utilization 계산 정확 |
  | **API 미발견** | Provider 메뉴 미표시 + throw 테스트 통과 + 로그 출력 |
  
  **Automated Verification (using Bash)**:
  ```bash
  # 1. Build succeeds
  xcodebuild -project CopilotMonitor/CopilotMonitor.xcodeproj \
    -scheme CopilotMonitor -configuration Debug build 2>&1 | grep "BUILD"
  # Assert: BUILD SUCCEEDED
  
  # 2. Provider file exists
  test -f CopilotMonitor/CopilotMonitor/Providers/OpenCodeProvider.swift && echo "EXISTS"
  # Assert: EXISTS
  
  # 3. Provider implements protocol
  grep -c "class OpenCodeProvider: ProviderProtocol" \
    CopilotMonitor/CopilotMonitor/Providers/OpenCodeProvider.swift
  # Assert: Returns 1
  
  # 4. API key check exists (graceful handling when key missing)
  grep -c "getOpenCodeAPIKey" \
    CopilotMonitor/CopilotMonitor/Providers/OpenCodeProvider.swift
  # Assert: Returns at least 1
  
  # 5. authenticationFailed throw exists (API 미발견 처리)
  grep -c "authenticationFailed" \
    CopilotMonitor/CopilotMonitor/Providers/OpenCodeProvider.swift
  # Assert: Returns at least 2 (키 없음 + API 404)
  
  # 6. Tests pass (API 발견/미발견 모두)
  xcodebuild test -project CopilotMonitor/CopilotMonitor.xcodeproj \
    -scheme CopilotMonitor -destination 'platform=macOS' 2>&1 \
    | grep -E "OpenCodeProvider.*passed|FAILED"
  # Assert: OpenCodeProvider tests passed (mock 기반)
  ```
  
  **Evidence to Capture**:
  - API 탐색 결과 (200 OK 또는 404/401)
  - 성공 시 응답 JSON 구조

  **Commit**: YES
  - Message: `feat(provider): implement OpenCodeProvider with API integration`
  - Files: `Providers/OpenCodeProvider.swift`, `Services/ProviderManager.swift`
  - Pre-commit: `xcodebuild build`

---

- [x] 6. Submenu 디테일 표시 구현 + ProviderResult 아키텍처 변경

  **What to do**:
  - **ProviderResult 아키텍처 변경** (선행 작업):
    - **Technical Design Decisions 섹션의 "2. ProviderUsage 확장 및 DetailedUsage 전달 설계" 참조**
    
    **⚠️ Compile-Break Prevention: 수정 순서 (엄격히 준수)**
    
    아래 순서를 어기면 중간 단계에서 컴파일 실패. 순서대로 수정 후 각 단계 컴파일 확인.
    
    | 순서 | 파일 | 수정 내용 | 예상 컴파일 에러 (수정 전) | 해결 |
    |-----|------|----------|-------------------------|------|
    | 1 | `Models/ProviderResult.swift` | 신규 생성 (ProviderResult, DetailedUsage) | - | 새 파일 생성 |
    | 2 | `Models/ProviderProtocol.swift` | `fetch() -> ProviderResult` 반환 타입 변경 | "Cannot find type 'ProviderResult'" | 순서 1 완료 후 해결 |
    | 3 | `Providers/*.swift` (6개 파일) | 각 Provider의 `fetch()` 반환 래핑 | "Cannot convert return expression of type 'ProviderUsage'" | 모든 Provider 동시 수정 |
    | 4 | `Services/ProviderManager.swift` | cachedResults, fetchAll() 등 타입 변경 | "Cannot assign value of type 'ProviderResult'" | 순서 3 완료 후 |
    | 5 | `App/StatusBarController.swift` | providerResults 타입 및 접근 변경 | "Value of type 'ProviderResult' has no member 'utilization'" | `.usage` 접근자 추가 |
    
    **순서 3 상세 (모든 Provider 동시 수정)**:
    ```swift
    // 기존 Provider들 - details: nil 래핑만
    func fetch() async throws -> ProviderResult {
        let usage = try await existingFetchLogic()
        return ProviderResult(usage: usage, details: nil)
    }
    
    // OpenRouterProvider - details 포함
    func fetch() async throws -> ProviderResult {
        // ... API 호출 ...
        return ProviderResult(usage: .payAsYouGo(...), details: DetailedUsage(...))
    }
    ```
    
    **순서 5 상세 (.usage 접근자 추가 위치)**:
    - `updateMultiProviderMenu()` 내 `case .payAsYouGo(...)` → `case .payAsYouGo(...) = result.usage`
    - `case .quotaBased(...)` → `case .quotaBased(...) = result.usage`
    - `calculateTotalOverageCost()`, `getQuotaAlerts()` 등 동일 패턴
    
    - `Models/ProviderResult.swift` 신규 생성:
      ```swift
      struct ProviderResult {
          let usage: ProviderUsage
          let details: DetailedUsage?
      }
      
      // ⚠️ 이 정의가 최종 정답 - Technical Design Decisions 섹션과 동일
      struct DetailedUsage: Codable {
          // 사용량 (Usage)
          let dailyUsage: Double?       // 오늘 사용량 ($)
          let weeklyUsage: Double?      // 이번 주 사용량 ($)
          let monthlyUsage: Double?     // 이번 달 사용량 ($)
          
          // 크레딧 (Credits)
          let totalCredits: Double?     // 총 충전 크레딧 ($)
          let remainingCredits: Double? // 남은 크레딧 ($)
          
          // 한도 (Limit) - 원요구사항: "일별/주간한도" 포함
          let limit: Double?            // 설정된 한도 ($)
          let limitRemaining: Double?   // 남은 한도 ($)
          let resetPeriod: String?      // 리셋 주기 ("weekly", "monthly")
      }
      
      extension DetailedUsage {
          var hasAnyValue: Bool {
              return dailyUsage != nil || weeklyUsage != nil || monthlyUsage != nil 
                  || totalCredits != nil || remainingCredits != nil 
                  || limit != nil || limitRemaining != nil || resetPeriod != nil
          }
      }
      ```
    - `Models/ProviderProtocol.swift` 수정: `func fetch() async throws -> ProviderResult`
    - `Providers/*.swift` 모든 Provider 반환 타입 변경:
      - `ClaudeProvider.swift` - `details: nil` 래핑
      - `CodexProvider.swift` - `details: nil` 래핑
      - `GeminiCLIProvider.swift` - `details: nil` 래핑
      - `CopilotProvider.swift` - **비즈니스 로직 유지, 반환만 래핑** (Guardrails 참조)
      - `OpenRouterProvider.swift` - `details: DetailedUsage(...)` 포함
      - `OpenCodeProvider.swift` - `details: DetailedUsage(...)` 포함 (API 있는 경우)
    - `Services/ProviderManager.swift` 캐시 타입 변경: `[ProviderIdentifier: ProviderResult]`
    - `App/StatusBarController.swift` `providerResults` 타입 변경
  - `StatusBarController.updateMultiProviderMenu()`에서 각 Provider 메뉴 항목에 submenu 추가
  - **Submenu 포맷**: SF Symbol + 텍스트
    - `calendar` + "Daily: $0.50"
    - `calendar` + "Weekly: $2.30"
    - `calendar` + "Monthly: $15.20"
    - `clock` + "Resets: weekly" (또는 구체적 날짜)
    - `creditcard` + "Credits: $136.28 remaining"
  - 정보 없는 항목은 표시 안 함 (N/A 대신 숨김)

  **Submenu 표시 규칙 (명확화)**:
  
  | 조건 | Submenu 동작 |
  |------|-------------|
  | `details == nil` | Submenu 없음 (기존 Provider들) |
  | `details != nil` but 모든 필드 nil | Submenu 없음 |
  | `details != nil` and 1개 이상 non-nil | Submenu 표시 (non-nil 필드만) |
  
  **기존 Quota 기반 Provider Submenu 처리**:
  - **Claude, Codex, GeminiCLI**: `details: nil` 반환 → Submenu 없음 (현재 동작 유지)
  - **Copilot**: `details: nil` 반환 → Submenu 없음 (기존 CopilotUsageView가 상세 정보 표시)
  - **OpenRouter, OpenCode**: `details: DetailedUsage(...)` 반환 → Submenu 표시
  
  **구현 로직**:
  ```swift
  // StatusBarController.updateMultiProviderMenu()
  for (identifier, result) in providerResults {
      let menuItem = createProviderMenuItem(identifier, result.usage)
      
      // Submenu 조건부 생성
      if let details = result.details, details.hasAnyValue {
          let submenu = createDetailSubmenu(details)
          menuItem.submenu = submenu
      }
      // details가 nil이거나 모든 값이 nil이면 submenu 없음
      
      menu.addItem(menuItem)
  }
  
  // DetailedUsage extension
  extension DetailedUsage {
      var hasAnyValue: Bool {
          return dailyUsage != nil || weeklyUsage != nil || monthlyUsage != nil 
              || totalCredits != nil || remainingCredits != nil 
              || limit != nil || limitRemaining != nil || resetPeriod != nil
      }
  }
  ```

  **Must NOT do**:
  - 새로운 윈도우/팝업 UI 추가
  - 복잡한 차트나 그래프 구현
  - 기존 `.payAsYouGo` enum case 시그니처 변경 (별도 struct로 확장)

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: UI/UX 구현, 메뉴 구조 변경
  - **Skills**: [`frontend-ui-ux`]
    - frontend-ui-ux: 메뉴 디자인 패턴
  - **Skills Evaluated but Omitted**:
    - `web-design-guidelines`: macOS native, web 아님

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Task 7)
  - **Blocks**: Task 8
  - **Blocked By**: Tasks 2, 3, 4

  **References**:
  
  **Pattern References**:
  - `App/StatusBarController.swift` - `updateMultiProviderMenu()` (line 963-1044)
    - 현재 `private var providerResults: [ProviderIdentifier: ProviderUsage]` (Dictionary 타입)
    - `createPayAsYouGoMenuItem()`, `createQuotaMenuItem()` 메서드
  - `App/StatusBarController.swift` - historySubmenu 생성 (line 497-504)
    - `NSMenu()` 생성 → `addItem()` → `menuItem.submenu = submenu` 패턴
  - `App/StatusBarController.swift` - enabledProvidersMenu submenu (line 558-571)
    - 동적 submenu 항목 생성 패턴
  
  **API/Type References**:
  - `NSMenu.addItem(NSMenuItem)` - 메뉴 아이템 추가
  - `NSMenuItem.submenu: NSMenu?` - 서브메뉴 설정
  - `NSImage(systemSymbolName:accessibilityDescription:)` - SF Symbol 아이콘
  
  **Documentation References**:
  - OpenRouter API 응답 (Task 3에서 사용):
    ```json
    {
      "data": {
        "usage_daily": 0.004,
        "usage_weekly": 0.5,
        "usage_monthly": 37.41,
        "limit": 100,
        "limit_remaining": 99.99,
        "limit_reset": "weekly"
      }
    }
    ```
  - Technical Design Decisions: "2. ProviderUsage 확장 설계"
  
  **WHY Each Reference Matters**:
  - `updateMultiProviderMenu()`가 Provider 메뉴 아이템 생성의 중앙 위치
  - historySubmenu 패턴이 동적 submenu 생성의 검증된 예시
  - DetailedUsage는 Optional이므로 기존 코드 호환성 유지

  **Acceptance Criteria**:
  
  **Automated Verification (using Bash)**:
  ```bash
  # Verify ProviderResult.swift created
  test -f CopilotMonitor/CopilotMonitor/Models/ProviderResult.swift && echo "EXISTS"
  # Assert: EXISTS
  
  # Verify DetailedUsage struct in ProviderResult
  grep -c "struct DetailedUsage" CopilotMonitor/CopilotMonitor/Models/ProviderResult.swift
  # Assert: Returns 1
  
  # Verify ProviderProtocol returns ProviderResult
  grep -c "-> ProviderResult" CopilotMonitor/CopilotMonitor/Models/ProviderProtocol.swift
  # Assert: Returns 1
  
  # Verify submenu creation code exists
  grep -c "\.submenu = " CopilotMonitor/CopilotMonitor/App/StatusBarController.swift
  # Assert: Returns > 3 (existing + new provider submenus)
  
  # Verify detail items exist in menu creation
  grep -E "Daily|Weekly|Monthly|Credits" \
    CopilotMonitor/CopilotMonitor/App/StatusBarController.swift | wc -l
  # Assert: Returns > 0
  
  # Build succeeds
  xcodebuild -project CopilotMonitor/CopilotMonitor.xcodeproj \
    -scheme CopilotMonitor -configuration Debug build 2>&1 | grep "BUILD"
  # Assert: BUILD SUCCEEDED
  ```
  
  **Manual Visual Verification**:
  - 앱 실행 → OpenRouter 항목에 마우스 호버 → Submenu 펼쳐짐 확인
  - Submenu에 Daily/Weekly/Monthly/Credits 정보 표시 확인

  **OpenRouter Submenu 예상 출력 (구체적 문자열)**:
  
  ⚠️ **주의**: 아래 예시의 📅💳📊🔄 이모지는 **문서 표기용**입니다.
  **실제 구현**: `NSMenuItem.image = NSImage(systemSymbolName:...)` 사용, **title에 이모지 미포함**
  
  ```
  ┌─────────────────────────────┐
  │ OpenRouter        97.0% ▸   │  ← 메인 라인: 퍼센트 표시
  ├─────────────────────────────┤
  │ [calendar] Daily: $0.00     │  ← .image = SF Symbol, title = "Daily: $0.00"
  │ [calendar] Weekly: $0.50    │  ← .image = SF Symbol, title = "Weekly: $0.50"
  │ [calendar] Monthly: $37.41  │  ← .image = SF Symbol, title = "Monthly: $37.41"
  │ [creditcard] Credits: $136.28 left  │  ← .image = SF Symbol
  │ [chart.bar] Limit: $99.99 / $100.00 │  ← .image = SF Symbol
  │ [clock.arrow.circlepath] Resets: weekly │  ← .image = SF Symbol
  └─────────────────────────────┘
  ```
  
  **실제 코드 패턴**:
  ```swift
  let item = NSMenuItem(title: "Daily: $0.00", action: nil, keyEquivalent: "")
  item.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Daily")
  // ⚠️ title에 이모지 없음!
  ```
  
  **Submenu 항목 순서 및 조건**:
  | 순서 | 항목 | 조건 | SF Symbol |
  |------|------|------|-----------|
  | 1 | Daily | `dailyUsage != nil` | `calendar` |
  | 2 | Weekly | `weeklyUsage != nil` | `calendar` |
  | 3 | Monthly | `monthlyUsage != nil` | `calendar` |
  | 4 | Credits | `remainingCredits != nil` | `creditcard` |
  | 5 | Limit | `limit != nil && limitRemaining != nil` | `chart.bar` |
  | 6 | Resets | `resetPeriod != nil` | `clock.arrow.circlepath` |
  
  **Submenu 항목 생성 코드 패턴**:
  ```swift
  func createDetailSubmenu(_ details: DetailedUsage) -> NSMenu {
      let submenu = NSMenu()
      
      // Usage 항목
      if let daily = details.dailyUsage {
          let item = NSMenuItem(title: String(format: "Daily: $%.2f", daily), action: nil, keyEquivalent: "")
          item.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Daily")
          submenu.addItem(item)
      }
      if let weekly = details.weeklyUsage {
          let item = NSMenuItem(title: String(format: "Weekly: $%.2f", weekly), action: nil, keyEquivalent: "")
          item.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Weekly")
          submenu.addItem(item)
      }
      if let monthly = details.monthlyUsage {
          let item = NSMenuItem(title: String(format: "Monthly: $%.2f", monthly), action: nil, keyEquivalent: "")
          item.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Monthly")
          submenu.addItem(item)
      }
      
      // Credits 항목
      if let remaining = details.remainingCredits {
          let item = NSMenuItem(title: String(format: "Credits: $%.2f left", remaining), action: nil, keyEquivalent: "")
          item.image = NSImage(systemSymbolName: "creditcard", accessibilityDescription: "Credits")
          submenu.addItem(item)
      }
      
      // Limit 항목 (한도)
      if let limit = details.limit, let remaining = details.limitRemaining {
          let item = NSMenuItem(title: String(format: "Limit: $%.2f / $%.2f", remaining, limit), action: nil, keyEquivalent: "")
          item.image = NSImage(systemSymbolName: "chart.bar", accessibilityDescription: "Limit")
          submenu.addItem(item)
      }
      
      // Reset 항목
      if let period = details.resetPeriod {
          let item = NSMenuItem(title: "Resets: \(period)", action: nil, keyEquivalent: "")
          item.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Reset")
          submenu.addItem(item)
      }
      
      return submenu
  }
  ```

  **"API-key Provider 캐시 무시" 검증 (Task 6 필수)**:
  
  **시나리오 기반 검증**:
  ```bash
  # 1. OpenRouter 정상 동작 확인 (캐시 생성)
  # - 앱 실행 → OpenRouter 메뉴에 표시됨 → 캐시 생성됨
  
  # 2. API 키 제거 시뮬레이션
  # - ~/.local/share/opencode/auth.json에서 openrouter 키 제거
  # - 앱에서 Refresh 실행
  
  # 3. 검증: OpenRouter가 메뉴에서 사라져야 함 (캐시 fallback 안 함)
  # - 로그 확인: "OpenRouter auth failed: API key not found, hiding"
  ```
  
  **Unit Test (Task 8에 포함)**:
  ```swift
  func testAuthFailedDoesNotUseCacheForAPIKeyProvider() async {
      // Given: OpenRouter에 캐시가 있는 상태
      await providerManager.updateCache(identifier: .openRouter, result: mockResult)
      
      // When: OpenRouterProvider.fetch()가 authenticationFailed throw
      // (API 키 없음 시뮬레이션)
      
      // Then: fetchAll() 결과에 OpenRouter가 없어야 함
      let results = await providerManager.fetchAll()
      XCTAssertNil(results[.openRouter])  // 캐시 무시 확인
  }
  ```
  
  **로그 기반 검증**:
  ```bash
  # 앱 로그에서 확인
  log show --predicate 'subsystem == "com.copilotmonitor"' --last 5m \
    | grep -E "auth failed.*hiding|not using cache"
  # Assert: API-key Provider 인증 실패 시 "hiding" 로그 출력
  ```

  **Commit**: YES
  - Message: `feat(ui): add submenu with detailed usage info for each provider`
  - Files: `Models/ProviderResult.swift`, `Models/ProviderProtocol.swift`, `Providers/*.swift`, `Services/ProviderManager.swift`, `App/StatusBarController.swift`
  - Pre-commit: `xcodebuild build`

---

- [ ] 7. GitHub Copilot 이중 표시 (Quota + Pay-as-you-go)

  **What to do**:
  - **Technical Design Decisions 섹션의 "4. Copilot 이중 표시 삽입 지점" 참조**
  - **Design Clarifications 섹션의 "3. Task 7 구조적 문제 해결" 참조**
  
  **⚠️ 핵심 변경: guard 조건 수정 (line 976)**
  
  현재 문제:
  ```swift
  guard !providerResults.isEmpty else { return }  // ← Copilot만 있을 때도 return!
  ```
  
  해결:
  ```swift
  // providerResults OR currentUsage 중 하나라도 있으면 진행
  let hasCopilotData = currentUsage != nil
  guard !providerResults.isEmpty || hasCopilotData else { return }
  ```
  
  - `updateMultiProviderMenu()` 수정하여 Copilot 특별 처리:
    
    **Pay-as-you-go 섹션에 Copilot Add-on 추가 (for-loop 전에!)**:
    ```swift
    var hasPayAsYouGo = false  // 기존 위치
    
    // ⚠️ Copilot Add-on FIRST (providerResults 순회 전에!)
    // currentUsage는 StatusBarController에 이미 존재하는 CopilotUsage
    if let copilotUsage = currentUsage, copilotUsage.netBilledAmount > 0 {
        hasPayAsYouGo = true  // ⚠️ 플래그 업데이트 필수!
        let addOnItem = NSMenuItem(
            title: String(format: "Copilot Add-on    $%.2f", copilotUsage.netBilledAmount),
            action: nil,
            keyEquivalent: ""
        )
        addOnItem.image = iconForProvider(.copilot)
        addOnItem.tag = 999
        menu.insertItem(addOnItem, at: insertIndex)
        insertIndex += 1
    }
    
    // 그 다음 다른 Provider 순회
    for (identifier, result) in providerResults {
        if case .payAsYouGo(let utilization, _) = result.usage {
            hasPayAsYouGo = true
            // ... 아이템 추가 ...
        }
    }
    
    // "No providers" 표시는 hasPayAsYouGo가 false일 때만
    if !hasPayAsYouGo {
        // "No providers" placeholder
    }
    ```
    
    **Quota 섹션에 Copilot Quota 추가**:
    ```swift
    if let copilotUsage = currentUsage {
        let limit = copilotUsage.userPremiumRequestEntitlement  // API에서 동적, non-optional Int
        let used = copilotUsage.usedRequests
        let remaining = limit - used
        let percentage = limit > 0 ? (Double(remaining) / Double(limit)) * 100 : 0
        let quotaItem = createQuotaMenuItem(identifier: .copilot, percentage: percentage)
        quotaItem.tag = 999
        menu.insertItem(quotaItem, at: insertIndex)
        insertIndex += 1
    }
    ```

  **데이터 소스**:
  - `currentUsage: CopilotUsage?` - `StatusBarController`에 이미 존재 (line 398 근처)
  - `netBilledAmount: Double` - 추가 요금 (>0 일 때만 Pay-as-you-go 표시)
  - `userPremiumRequestEntitlement: Int` - 동적 한도 (API에서 가져옴, non-optional, 하드코딩 금지)
  - `usedRequests: Int` - 사용량

  **Must NOT do**:
  - CopilotProvider 내부 로직 변경
  - 한도 값 하드코딩 (예: 1500 고정) - 반드시 `userPremiumRequestEntitlement` 사용
  - 기존 CopilotUsageView (상단 전용 뷰) 로직 수정

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: 기존 데이터 활용, UI 조건부 표시만
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - `frontend-ui-ux`: 단순 조건부 표시

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Task 6)
  - **Blocks**: Task 8
  - **Blocked By**: Task 3

  **References**:
  
  **Pattern References**:
  - `App/StatusBarController.swift` - `updateMultiProviderMenu()` (line 963-1044)
    - Pay-as-you-go 섹션: line 985-1008
    - Quota 섹션: line 1015-1039
    - Copilot 삽입 위치: 각 섹션의 for-loop 전에 special case 처리
  - `App/StatusBarController.swift` - `createQuotaMenuItem()` (line 1053-1063)
    - 기존 메뉴 아이템 생성 패턴 재사용
  - `App/StatusBarController.swift` - `currentUsage` property (line 398 근처)
    - `var currentUsage: CopilotUsage?` 타입
  
  **API/Type References**:
  - `Models/CopilotUsage.swift`:
    - `netBilledAmount: Double` - 추가 요금 ($)
    - `usedRequests: Int` - 사용한 요청 수
    - `userPremiumRequestEntitlement: Int` - 월간 한도 (API에서 동적, **non-optional**)
  
  **WHY Each Reference Matters**:
  - `updateMultiProviderMenu()`가 Provider 메뉴 생성의 중앙 위치
  - `currentUsage`가 이미 Copilot 데이터를 보유하고 있음
  - `userPremiumRequestEntitlement`로 동적 한도 보장 (하드코딩 방지)

  **Acceptance Criteria**:
  
  **Automated Verification (using Bash)**:
  ```bash
  # Verify netBilledAmount check exists in updateMultiProviderMenu
  grep -A50 "updateMultiProviderMenu" CopilotMonitor/CopilotMonitor/App/StatusBarController.swift \
    | grep -c "netBilledAmount"
  # Assert: Returns > 0
  
  # Verify userPremiumRequestEntitlement used (not hardcoded limit)
  grep -A50 "updateMultiProviderMenu" CopilotMonitor/CopilotMonitor/App/StatusBarController.swift \
    | grep -c "userPremiumRequestEntitlement"
  # Assert: Returns > 0
  
  # Verify no hardcoded 1500 limit
  grep -A50 "updateMultiProviderMenu" CopilotMonitor/CopilotMonitor/App/StatusBarController.swift \
    | grep -c "1500" || echo "0"
  # Assert: Returns 0
  
  # Build succeeds
  xcodebuild -project CopilotMonitor/CopilotMonitor.xcodeproj \
    -scheme CopilotMonitor -configuration Debug build 2>&1 | grep "BUILD"
  # Assert: BUILD SUCCEEDED
  ```

  **Commit**: YES - groups with Task 6
  - Message: `feat(ui): show Copilot in both Quota and Pay-as-you-go sections`
  - Files: `App/StatusBarController.swift`
  - Pre-commit: `xcodebuild build`

---

- [ ] 8. 테스트 및 리팩토링

  **What to do**:
  - `CopilotMonitorTests/OpenRouterProviderTests.swift` 생성
  - `CopilotMonitorTests/Fixtures/openrouter_credits_response.json` 생성
  - `CopilotMonitorTests/Fixtures/openrouter_key_response.json` 생성
  - 테스트 케이스:
    - Response 디코딩 테스트
    - 사용량 계산 테스트
    - null/missing 필드 처리 테스트
    - identifier/type 검증 테스트
  - 전체 테스트 실행 및 수정
  - 코드 정리 (불필요한 import 제거, 주석 정리)

  **Must NOT do**:
  - 기존 테스트 케이스 삭제
  - E2E 테스트 추가 (유닛 테스트만)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: 기존 테스트 패턴 따르기, 단순 반복 작업
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - 특별한 skill 필요 없음

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 3 (final)
  - **Blocks**: None
  - **Blocked By**: Tasks 3, 5, 6, 7

  **References**:
  
  **Pattern References**:
  - `CopilotMonitorTests/CodexProviderTests.swift:*` - 테스트 구조 패턴
  - `CopilotMonitorTests/CodexProviderTests.swift:75-85` - loadFixture() 메서드
  - `CopilotMonitorTests/ProviderUsageTests.swift:*` - 픽스처 로딩 테스트
  
  **Test References**:
  - `CopilotMonitorTests/Fixtures/codex_response.json` - JSON 픽스처 형식
  
  **WHY Each Reference Matters**:
  - 기존 테스트 패턴과 일관성 유지 필수
  - loadFixture() 메서드 재사용

  **Acceptance Criteria**:
  
  **Automated Verification (using Bash)**:
  ```bash
  # All tests pass
  xcodebuild test -project CopilotMonitor/CopilotMonitor.xcodeproj \
    -scheme CopilotMonitor -destination 'platform=macOS' 2>&1 | grep -E "Test.*passed|FAILED"
  # Assert: All tests passed, no FAILED
  
  # New test file exists
  test -f CopilotMonitor/CopilotMonitorTests/OpenRouterProviderTests.swift && echo "EXISTS"
  # Assert: EXISTS
  
  # Fixtures exist
  test -f CopilotMonitor/CopilotMonitorTests/Fixtures/openrouter_credits_response.json && echo "EXISTS"
  # Assert: EXISTS
  
  # Test count increased
  grep -c "func test" CopilotMonitor/CopilotMonitorTests/OpenRouterProviderTests.swift
  # Assert: Returns >= 3
  ```

  **Commit**: YES
  - Message: `test(provider): add OpenRouterProvider tests with fixtures`
  - Files: `CopilotMonitorTests/OpenRouterProviderTests.swift`, `CopilotMonitorTests/Fixtures/openrouter_*.json`
  - Pre-commit: `xcodebuild test`

---

- [ ] 9. 앱 리브랜딩: OpencodeProvidersMonitor

  **What to do**:
  
  **⚠️ 권장 Rename 방법: Xcode UI 사용 (pbxproj 수동 편집 금지)**
  
  Xcode UI rename이 안전한 이유:
  - 파일 시스템, pbxproj, scheme 파일을 원자적으로 업데이트
  - 상대 경로 참조 자동 수정
  - 빌드 설정(TEST_HOST 등) 자동 업데이트
  
  **Step 1: Xcode UI로 Scheme Rename**
  ```
  Xcode → Product → Scheme → Manage Schemes
  → CopilotMonitor 선택 → 더블클릭 → "OpencodeProvidersMonitor" 입력
  ```
  
  **Step 2: Xcode UI로 Target Rename**
  ```
  Project Navigator → CopilotMonitor 프로젝트 선택
  → TARGETS → CopilotMonitor → Identity → Display Name 변경
  ```
  
  **Step 3: Info.plist 수정 (수동)**
  - `CFBundleName` → `OpencodeProvidersMonitor`
  - `CFBundleDisplayName` → `Opencode Providers Monitor`
  
  **Step 4: Logger subsystem 변경 (⚠️ subsystem만, message는 그대로)**
  - 현재: `Logger(subsystem: "com.copilotmonitor", category: "...")`
  - 변경: `Logger(subsystem: "com.opencodeproviders", category: "...")`
  - **⚠️ 로그 MESSAGE는 변경하지 않음**: 
    - 예: `logger.debug("토큰 만료됨")` → 그대로 유지 (한국어 OK)
    - subsystem만 변경, message 내용은 scope 외
  - **Bundle Identifier는 유지**: `com.copilotmonitor.CopilotMonitor` (현재 값 그대로)
    - 확인 위치: `project.pbxproj:495,520` PRODUCT_BUNDLE_IDENTIFIER
  - 영향 파일 (grep "com.copilotmonitor" 결과, **Logger subsystem 문자열만 변경**):
    - `Services/ProviderManager.swift:4`
    - `App/StatusBarController.swift:7`
    - `Services/AuthManager.swift:5,101`
    - `Services/TokenManager.swift:4`
    - `Providers/ClaudeProvider.swift:4`
    - `Providers/GeminiCLIProvider.swift:4`
    - `Providers/CodexProvider.swift:4`
    - `Providers/CopilotProvider.swift:5`
  
  **Step 5: UI 텍스트 변경**
  - "Copilot Usage" → "AI Usage"
  - 메뉴 항목에서 Copilot 전용 표현 제거/일반화
  
  **Step 6: 한국어 텍스트 영문화 (AGENTS.md 규칙 준수)**
  
  AGENTS.md 규칙:
  - "All of comments in code base, commit message, PR content and title should be written in English."
  - "All user-facing text in the app MUST be in English."
  
  **확인된 한국어 텍스트 목록 (grep "[가-힣]" 결과 - 63개 발견)**:
  
  | 파일 | 유형 | 수량 | 처리 |
  |------|------|------|------|
  | `AppDelegate.swift:72` | **UI (윈도우 타이틀)** | 1 | **필수 영문화**: `"GitHub 로그인"` → `"GitHub Login"` |
  | `AppDelegate.swift:12-13` | 주석 | 2 | 영문화 권장 |
  | `AuthManager.swift:13-142` | 로그 | ~28 | 영문화 권장 (개발 편의상) |
  | `StatusBarController.swift:474-1301` | 로그 | ~20 | 영문화 권장 |
  | `UsagePredictor.swift:46-99` | 주석 | 3 | 영문화 권장 |
  
  **영문화 범위 결정 (단일 정답 - 최종)**:
  
  | 유형 | 처리 | 근거 |
  |------|------|------|
  | **UI 텍스트** | ✅ **필수 영문화** | AGENTS.md: "All user-facing text MUST be in English" |
  | **코드 주석** | ✅ **필수 영문화** | AGENTS.md: "All comments in code base should be in English" |
  | **로그 MESSAGE 문자열** | ❌ **영문화 안 함** | 개발자 전용, 리브랜딩 scope 외 |
  | **Logger SUBSYSTEM 상수** | ✅ **변경** | 앱 브랜딩의 일부 (Step 4에서 처리) |
  
  **⚠️ 로그 관련 명확화 (Momus 지적 해결)**:
  - **Logger subsystem** (`"com.copilotmonitor"` → `"com.opencodeproviders"`): **변경 O**
    - 이유: 앱 식별자, 브랜딩 일부
    - 위치: Step 4에서 처리
  - **Logger message** (예: `logger.debug("인증 실패")`): **변경 X**
    - 이유: 개발자 디버깅용, 이 Task 범위 외
    - 63개 한국어 로그 메시지는 그대로 유지
  
  **이 Task에서 처리할 범위 (최종, 모순 없음)**:
  
  | 대상 | 처리 | 예시 |
  |------|------|------|
  | UI 텍스트 | ✅ **영문화** | `"GitHub 로그인"` → `"GitHub Login"` |
  | 코드 주석 | ✅ **영문화** | `// 토큰 만료 체크` → `// Check token expiration` |
  | 로그 문자열 | ❌ **그대로** | `logger.debug("인증 실패")` → 변경 없음 |
  | Logger subsystem | ✅ **변경** | `"com.copilotmonitor"` → `"com.opencodeproviders"` |
  
  **검색 커맨드**:
  ```bash
  grep -rn "[가-힣]" CopilotMonitor/CopilotMonitor/ --include="*.swift"
  ```
  
  **"Copilot Usage" 문자열 확인**:
  - grep 결과: Swift 코드에 `"Copilot Usage"` 문자열 없음
  - 변경 불필요 (이미 존재하지 않음)
  
  **Step 7: Sparkle SUFeedURL**
  - **결정: 현재 URL 유지** (레포 이름 변경은 Plan 외)
  - GitHub는 레포 rename 시 자동 리다이렉트 지원
  
  **Step 8: README.md 업데이트**
  - 앱 이름 변경
  - 설치 가이드 경로 업데이트
  - **Codex 분류 수정** (README에서 quotaBased로 설명)
  
  **파일 시스템에서 실제로 rename할 항목 (Xcode UI가 자동 처리)**:
  | 대상 | 현재 | 변경 후 | 자동/수동 |
  |-----|------|--------|----------|
  | Scheme 파일 | `CopilotMonitor.xcscheme` | `OpencodeProvidersMonitor.xcscheme` | Xcode 자동 |
  | pbxproj 내 productName | `CopilotMonitor` | `OpencodeProvidersMonitor` | Xcode 자동 |
  | TEST_HOST 경로 | `CopilotMonitor.app` | `OpencodeProvidersMonitor.app` | Xcode 자동 |
  | Info.plist 값 | (위 참조) | (위 참조) | 수동 |
  | Logger subsystem | (위 참조) | (위 참조) | 수동 |
  
  **⚠️ 폴더 이름은 변경하지 않음**:
  - `CopilotMonitor/CopilotMonitor/` 폴더 구조 유지
  - pbxproj의 상대 경로가 복잡하므로 폴더 rename은 리스크 높음
  - 앱 표시 이름(Info.plist)만 변경하면 사용자에게는 새 이름으로 보임

  **Must NOT do**:
  - Bundle Identifier 변경 (기존 사용자 설정 유지)
  - GitHub Repo 이름 변경 (별도 수동 작업)
  - 기존 기능 로직 변경

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: 텍스트 치환 위주, 복잡도 낮음
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - `git-master`: 커밋은 마지막에 일괄 처리

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with Task 8, or after all)
  - **Blocks**: None
  - **Blocked By**: Tasks 6, 7 (UI 텍스트가 확정된 후)

  **References**:
  
  **Pattern References**:
  - `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj` - 프로젝트 이름 위치
  - `CopilotMonitor/CopilotMonitor/Info.plist` - 앱 이름 설정
  - `README.md` - 문서 업데이트 대상
  
  **Text to Replace**:
  - "CopilotMonitor" → "OpencodeProvidersMonitor"
  - "Copilot Monitor" → "Opencode Providers Monitor"
  - "copilotmonitor" → "opencodeproviders" (lowercase)
  - "Copilot Usage" → "AI Usage" 또는 "Provider Usage"
  
  **⚠️ 영문화 범위 (Step 6 상세 - 상단 표와 동일)**:
  - **포함 범위**: 
    - UI 텍스트 (버튼, 메뉴, 다이얼로그, 윈도우 타이틀)
    - 코드 주석 (AGENTS.md: "All comments in code base should be in English")
    - Logger subsystem 상수 (브랜딩)
  - **제외 범위**: 로그 MESSAGE 문자열만 (개발자 디버깅용)
  - **확인된 영문화 대상**:
    - UI: `AppDelegate.swift:72` - `"GitHub 로그인"` → `"GitHub Login"`
    - 주석: `AppDelegate.swift:12-13`, `UsagePredictor.swift:46-99` 등
    - Subsystem: 8개 파일 (Step 4 목록 참조)
  
  **WHY Each Reference Matters**:
  - project.pbxproj에서 타겟 이름, 스킴 이름 등 변경
  - Info.plist에서 사용자에게 보이는 앱 이름 변경
  - 영문화로 AGENTS.md 규칙 준수

  **Acceptance Criteria**:
  
  **Automated Verification (using Bash)**:
  ```bash
  # Verify app name changed in Info.plist
  grep -c "OpencodeProvidersMonitor" CopilotMonitor/CopilotMonitor/Info.plist
  # Assert: Returns > 0
  
  # Verify README updated
  grep -c "Opencode Providers Monitor\|OpencodeProvidersMonitor" README.md
  # Assert: Returns > 0
  
  # Verify old name removed from UI strings (except necessary references)
  grep -r "Copilot Usage" CopilotMonitor/CopilotMonitor/*.swift \
    CopilotMonitor/CopilotMonitor/**/*.swift 2>/dev/null | grep -v "^Binary" | wc -l
  # Assert: Returns 0 (no hardcoded "Copilot Usage" in UI)
  
  # Verify Korean UI text removed (윈도우 타이틀, 버튼, 메뉴 - 로그 제외)
  # 주요 한국어 UI 패턴 검색
  grep -rn "\".*로그인.*\"\|\".*설정.*\"\|\".*완료.*\"\|\".*확인.*\"" \
    CopilotMonitor/CopilotMonitor/App/*.swift 2>/dev/null || echo "No Korean UI found"
  # Assert: "No Korean UI found" (한국어 UI 텍스트 없음)
  
  # Build succeeds with NEW scheme name
  xcodebuild -project CopilotMonitor/CopilotMonitor.xcodeproj \
    -scheme OpencodeProvidersMonitor -configuration Debug build 2>&1 | grep "BUILD"
  # Assert: BUILD SUCCEEDED
  ```

  **Commit**: YES (final commit)
  - Message: `chore(brand): rebrand to OpencodeProvidersMonitor`
  - Files: `*.xcodeproj`, `Info.plist`, `README.md`, `*.swift` (UI 텍스트)
  - Pre-commit: `xcodebuild build`

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 0 | `fix(test): align CodexProviderTests with quotaBased type` | CodexProviderTests.swift | `xcodebuild test -scheme CopilotMonitor` |
| 1, 2 | `feat(provider): add OpenRouter/OpenCode identifiers and change menu bar icon` | ProviderProtocol.swift, TokenManager.swift, StatusBarController.swift, MultiProviderStatusBarIconView.swift | `xcodebuild build -scheme CopilotMonitor` |
| 3 | `feat(provider): implement OpenRouterProvider with credits/key API` | OpenRouterProvider.swift, ProviderManager.swift | `xcodebuild build -scheme CopilotMonitor` |
| 4 | `feat(ui): switch provider icons to Assets.xcassets images` | StatusBarController.swift | `xcodebuild build -scheme CopilotMonitor` |
| 5 | `feat(provider): implement OpenCodeProvider with API integration` | OpenCodeProvider.swift, ProviderManager.swift | `xcodebuild build -scheme CopilotMonitor` |
| 6, 7 | `feat(ui): add submenu details and Copilot dual display` | ProviderResult.swift, ProviderProtocol.swift, Providers/*.swift, ProviderManager.swift, StatusBarController.swift | `xcodebuild build -scheme CopilotMonitor` |
| 8 | `test(provider): add OpenRouterProvider tests with fixtures` | Tests/*.swift, Fixtures/*.json | `xcodebuild test -scheme CopilotMonitor` |
| 9 | `chore(brand): rebrand to OpencodeProvidersMonitor` | *.xcodeproj, Info.plist, README.md, AppDelegate.swift, *.swift | `xcodebuild build -scheme OpencodeProvidersMonitor` ⚠️ 스킴 변경됨 |

---

## Success Criteria

### Verification Commands

**Task 0~8 (리브랜딩 전)**:
```bash
# Full build
xcodebuild -project CopilotMonitor/CopilotMonitor.xcodeproj \
  -scheme CopilotMonitor -configuration Debug build
# Expected: BUILD SUCCEEDED

# Full test
xcodebuild test -project CopilotMonitor/CopilotMonitor.xcodeproj \
  -scheme CopilotMonitor -destination 'platform=macOS'
# Expected: All tests passed
```

**Task 9 이후 (리브랜딩 후)**:
```bash
# Full build (새 스킴)
xcodebuild -project CopilotMonitor/CopilotMonitor.xcodeproj \
  -scheme OpencodeProvidersMonitor -configuration Debug build
# Expected: BUILD SUCCEEDED

# Full test (새 스킴)
xcodebuild test -project CopilotMonitor/CopilotMonitor.xcodeproj \
  -scheme OpencodeProvidersMonitor -destination 'platform=macOS'
# Expected: All tests passed

# Run app and verify visually (리브랜딩 후 이름)
pkill -x OpencodeProvidersMonitor 2>/dev/null || true
# ⚠️ 리브랜딩 후 DerivedData 경로 변경 가능성 있음 - xcodebuild -showBuildSettings로 확인
open ~/Library/Developer/Xcode/DerivedData/CopilotMonitor-*/Build/Products/Debug/OpencodeProvidersMonitor.app \
  || open ~/Library/Developer/Xcode/DerivedData/OpencodeProvidersMonitor-*/Build/Products/Debug/OpencodeProvidersMonitor.app
# Expected: Menu bar shows gauge icon, providers have asset icons, submenus work
```

### Final Checklist
- [ ] 메뉴바 아이콘이 SF Symbol `gauge.medium`
- [ ] OpenRouter가 Pay-as-you-go 섹션에 표시
- [ ] OpenCode가 Pay-as-you-go 섹션에 표시 (API 키 존재 시)
- [ ] Copilot이 Quota + Pay-as-you-go 둘 다 표시
- [ ] 각 Provider 아이콘이 Assets.xcassets 이미지 사용
- [ ] Provider 호버 시 Submenu로 상세 정보 표시
- [ ] 모든 테스트 통과
- [ ] 기존 기능 정상 동작
- [ ] **앱 이름이 OpencodeProvidersMonitor로 변경됨**
- [ ] **UI에서 "Copilot Usage" → "AI Usage" 등으로 변경됨**
- [ ] **README.md가 새 브랜딩으로 업데이트됨**
