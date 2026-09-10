# Java 程式碼品質規範

供重構階段嚴格遵守。涵蓋 SOLID、Step Definition 組織、Meta 清理、日誌實踐、程式架構、程式碼品質。

---

## 1. SOLID 設計原則

### S — 單一職責

每個類別/方法只負責一件事。

```java
// ❌ Service 做太多事
@Service
public class AssignmentService {
    public void submitAssignment(Long userId, String content) {
        checkPermission(userId);
        repository.save(...);
        sendEmail(userId);
    }
}

// ✅ 職責分離
@Service
public class AssignmentService {
    @Autowired private AssignmentRepository assignmentRepository;
    @Autowired private PermissionValidator permissionValidator;
    @Autowired private NotificationService notificationService;

    public void submitAssignment(Long userId, String content) {
        permissionValidator.validate(userId);
        assignmentRepository.save(new Assignment(userId, content));
        notificationService.notify(userId);
    }
}
```

### O — 開放封閉

透過介面和策略模式擴展。

```java
public interface PaymentStrategy {
    void pay(Order order);
}

@Service
public class CreditCardPayment implements PaymentStrategy { ... }

// 新增只需實作介面
@Service
public class LinePay implements PaymentStrategy { ... }
```

### L — 里氏替換

子類別可安全替換父類別。

### I — 介面隔離

不強迫實作不需要的方法。按職責分離介面。

```java
// ❌ 過大介面
public interface UserService {
    void createUser(); void updateUser(); void sendEmail(); void generateReport();
}

// ✅ 分離
public interface UserCrudService { void createUser(); void updateUser(); }
public interface EmailService { void sendEmail(); }
```

### D — 依賴反轉

Service 透過 `@Autowired` 或建構子注入 Repository。

```java
// 建構子注入（推薦）
@Service
public class OrderService {
    private final OrderRepository orderRepository;
    private final ProductRepository productRepository;

    public OrderService(OrderRepository orderRepository, ProductRepository productRepository) {
        this.orderRepository = orderRepository;
        this.productRepository = productRepository;
    }
}
```

---

## 2. Step Definition 組織規範

### 組織原則

- 一個 Step Pattern 對應一個 Java class
- 使用 package 分類（`aggregate_given`, `commands`, `query` 等）
- 語意化類別名稱（如 `LessonProgressGivenSteps`）

### 目錄結構

```
src/test/java/com/wsa/platform/steps/
├── lesson/                          # {subdomain}
│   ├── aggregate_given/
│   │   └── LessonProgressGivenSteps.java
│   ├── commands/
│   │   └── UpdateVideoProgressSteps.java
│   ├── query/
│   │   └── GetLessonProgressSteps.java
│   ├── aggregate_then/
│   │   └── LessonProgressThenSteps.java
│   └── readmodel_then/
│       └── ProgressResultSteps.java
├── common_then/
│   └── CommonThen.java
└── helpers/
    ├── StatusMapping.java
    └── ScenarioContextHelper.java
```

### Spring Component Scanning

```java
@CucumberContextConfiguration
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ComponentScan(basePackages = {"com.wsa.platform.steps", "com.wsa.platform.cucumber"})
public class CucumberSpringConfiguration { }
```

### 共用邏輯

```java
// StatusMapping.java
public class StatusMapping {
    private static final Map<String, String> STATUS_MAPPING = Map.of(
        "進行中", "IN_PROGRESS", "已完成", "COMPLETED", "未開始", "NOT_STARTED"
    );
    public static String mapStatus(String chineseStatus) {
        return STATUS_MAPPING.getOrDefault(chineseStatus, chineseStatus);
    }
}
```

---

## 3. Meta 註記清理

### 刪除

- `// TODO: [事件風暴部位: ...]`
- `// TODO: 參考 xxx-Handler.md 實作`
- `// [生成參考 Prompt: ...]`

### 保留

- 必要的業務邏輯註解
- JavaDoc 文檔註解

### 範例

```java
// 重構前
public void userHasLessonProgress(...) {
    // TODO: [事件風暴部位: Aggregate - LessonProgress]
    // TODO: 參考 Aggregate-Given-Handler.md 實作
    String userId = scenarioContext.getId(userName);
    ...
}

// 重構後（移除 TODO，保留業務註解）
public void userHasLessonProgress(...) {
    String userId = scenarioContext.getId(userName);
    String dbStatus = StatusMapping.mapStatus(status); // 中文 → enum
    ...
}
```

---

## 4. 日誌實踐

### 框架

使用 Lombok `@Slf4j` 自動注入 SLF4J Logger。

```java
// ❌ 手動宣告
private static final Logger logger = LoggerFactory.getLogger(OrderService.class);

// ✅ Lombok
@Slf4j
@Service
public class OrderService { /* log 變數自動可用 */ }
```

### 等級規則

| 等級 | 用途 | 範例 |
|------|------|------|
| ERROR | 未預期錯誤，含 stack trace | `log.error("Unexpected: {}", ex.getMessage(), ex)` |
| WARN | 認證失敗、權限不足 | `log.warn("Expired JWT for {} {}", method, uri)` |
| INFO | 業務關鍵操作（寫入完成） | `log.info("Order created: orderNumber={}, userId={}", ...)` |
| DEBUG | 詳細流程、查詢結果數量 | `log.debug("Fetching order={} for userId={}", ...)` |

### 各層策略

- **Controller**：`log.info` 記錄請求進入
- **Service**：`log.info` 寫入完成；`log.debug` 查詢結果
- **Security Filter**：`log.warn` 認證失敗

### 格式規則

- 使用 SLF4J 佔位符 `{}`，**不用字串拼接**
- 使用 `key=value` 格式
- 訊息前加事件描述

### 禁止

- ❌ `System.out.println` 或 `e.printStackTrace()`
- ❌ 字串拼接（`"msg " + var`）
- ❌ 在迴圈中用 `log.info`
- ❌ 記錄敏感資訊

### application.yml 配置

```yaml
logging:
  level:
    com.wsa.platform: DEBUG
    org.hibernate.SQL: DEBUG
  pattern:
    console: "%d{yyyy-MM-dd HH:mm:ss.SSS} [%thread] %-5level %logger{36} - %msg%n"
```

---

## 5. 程式架構規範

### 分層

```
src/main/java/com/wsa/platform/
├── api/           # @RestController
├── service/       # @Service
├── repository/    # @Repository (Spring Data JPA)
├── model/         # @Entity (JPA)
├── dto/           # Request/Response DTOs
├── security/      # JwtTokenFilter, CurrentUser
└── Application.java
```

### 各層職責

| 層 | 負責 | 不負責 |
|----|------|--------|
| Controller | 路由、解析 Request、構建 Response | 業務邏輯、資料存取 |
| Service | 業務規則、協調 Repository、拋業務異常 | HTTP 處理、直接用 EntityManager |
| Repository | Spring Data JPA CRUD、自訂查詢 | 業務規則 |

### 依賴注入

Spring Boot 使用 `@Autowired` 或建構子注入。測試透過 Testcontainers 自動切換 DB。

### 常見錯誤

- ❌ 業務邏輯寫在 Controller
- ❌ Service 直接用 `EntityManager`（繞過 Repository）

---

## 6. 程式碼品質

### Early Return

```java
// ❌ 深層巢狀
public void process(Data data) {
    if (data != null) {
        if (data.isValid()) {
            processData(data);
        }
    }
}

// ✅ Guard Clause
public void process(Data data) {
    if (data == null) throw new DataException();
    if (!data.isValid()) throw new ValidationException();
    processData(data);
}
```

### 靜態常數

```java
// ❌ 每次都創建
Map<String, String> mapping = Map.of("A", "狀態A");

// ✅ 類別常數
private static final Map<String, String> STATUS_MAPPING = Map.of("A", "狀態A");
```

### Optional 正確使用

```java
// ❌ 直接 .get()
return orderRepository.findById(orderId).get();

// ✅ orElseThrow
return orderRepository.findById(orderId)
    .orElseThrow(() -> new OrderNotFoundException(orderId));
```

### DRY

重複 3+ 次的邏輯提取共用方法。

```java
private Subscription validateSubscription(Long userId) {
    return subscriptionRepo.findByUserId(userId)
        .orElseThrow(() -> new SubscriptionNotFoundException());
}
```

### 命名

- 方法名表達意圖（`updateVideoProgress` 而非 `process`）
- 布林方法用 `is`/`has`/`can` 開頭

---

## 檢查清單

- [ ] 每個類別/方法只負責一件事（SRP）
- [ ] Service 透過 @Autowired 或建構子注入 Repository（DIP）
- [ ] 一個 Step Pattern 一個 class
- [ ] CucumberSpringConfiguration 已配置 component scanning
- [ ] 所有 TODO/META 標記已清除
- [ ] 所有 Controller/Service/Security 加上 `@Slf4j`
- [ ] 日誌使用 SLF4J `{}` 佔位符 + key=value 格式
- [ ] Controllers/Services/Repositories 在正確的 package
- [ ] 使用 Early Return 減少巢狀
- [ ] 使用 Optional 安全處理可能為空的值
- [ ] 重複資料提升為 `static final` 常數
- [ ] 命名清晰表達用途
