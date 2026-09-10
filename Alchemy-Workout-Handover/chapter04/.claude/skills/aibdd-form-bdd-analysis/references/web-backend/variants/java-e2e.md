# Red Variant: java-e2e

## 測試框架

- **語言**：Java 17
- **BDD 框架**：Cucumber 7.15（Cucumber Expressions）
- **HTTP Client**：Spring Boot TestRestTemplate
- **ORM**：JPA（Hibernate）+ Spring Data JPA
- **資料庫**：PostgreSQL 16（透過 Testcontainers 啟動）
- **認證**：JWT Token（自訂 JwtHelper）
- **DI 框架**：Spring Boot 3.2（@Autowired）
- **Assertion**：AssertJ（`assertThat(...).isEqualTo(...)`）
- **JSON 解析**：Jackson ObjectMapper
- **測試執行**：`mvn clean test -Dtest=RunCucumberTest`
- **紅燈失敗原因**：HTTP 404 Not Found（後端 API 尚未實作）

## 檔案結構

```
${JAVA_APP_DIR}/
├── model/                       # JPA Entities（生產環境）
│   ├── {Aggregate}.java
│   └── {EnumType}.java
├── repository/                  # Spring Data JPA Repositories（生產環境）
│   └── {Aggregate}Repository.java
├── service/                     # Services（紅燈不實作）
├── controller/                  # Spring MVC Controllers（紅燈不實作）
└── PlatformApplication.java     # Spring Boot main class

${JAVA_TEST_DIR}/
├── CucumberSpringConfiguration.java  # Cucumber + Spring + Testcontainers 整合
├── ScenarioContext.java              # @ScenarioScope bean，管理測試狀態
├── RunCucumberTest.java              # JUnit Platform runner
└── steps/                            # Step Definitions
    ├── {subdomain}/                  # 按業務領域分（lesson, order, product, role）
    │   ├── aggregate_given/
    │   ├── commands/
    │   ├── query/
    │   ├── aggregate_then/
    │   └── readmodel_then/
    └── common_then/                  # 跨 subdomain 共用（操作成功/失敗）

${JAVA_TEST_FEATURES_DIR}/
└── *.feature                    # Feature files
```

**類別命名**：`{Feature}{StepType}Steps.java`（例：`LessonProgressGivenSteps.java`）

## 程式碼模式

### 依賴注入機制

使用 Spring `@Autowired` 注入所有依賴。Cucumber step classes 不支援建構子注入。

```java
public class VideoProgressSteps {

    @Autowired
    private TestRestTemplate testRestTemplate;

    @Autowired
    private ScenarioContext testContext;

    @Autowired
    private JwtHelper jwtHelper;

    @Autowired
    private LessonProgressRepository lessonProgressRepository;
}
```

ScenarioContext（`@ScenarioScope` bean）管理跨步驟狀態：

```java
@Component
@ScenarioScope
public class ScenarioContext {
    private ResponseEntity<?> lastResponse;
    private final Map<String, Object> ids = new HashMap<>();
    private final Map<String, Object> memo = new HashMap<>();

    public ResponseEntity<?> getLastResponse() { return lastResponse; }
    public void setLastResponse(ResponseEntity<?> response) { this.lastResponse = response; }
    public void putId(String key, Object id) { ids.put(key, id); }
    public <T> T getId(String key) { return (T) ids.get(key); }
}
```

### Step Definition 範例

使用 Cucumber Expressions 參數類型：
- `{string}` — 字串（引號內的文字）
- `{int}` — 整數
- `{long}` — 長整數
- `{float}` / `{double}` — 浮點數

```java
@Given("用戶 {string} 在課程 {int} 的進度為 {int}%，狀態為 {string}")
public void 用戶在課程的進度為狀態為(String userName, int lessonId, int progress, String status) {
    // ...
}
```

### Handler 實作範例

#### Aggregate-Given（建立前置資料 — 寫入 DB）

```java
import com.wsa.platform.model.CartItem;
import com.wsa.platform.repository.CartItemRepository;
import com.wsa.platform.steps.ScenarioContext;
import io.cucumber.java.en.Given;
import org.springframework.beans.factory.annotation.Autowired;

public class CartItemSteps {

    @Autowired
    private CartItemRepository cartItemRepository;

    @Autowired
    private ScenarioContext testContext;

    @Given("用戶 {string} 的購物車中商品 {string} 的數量為 {int}")
    public void 用戶的購物車中商品的數量為(String userName, String productId, int quantity) {
        String userId = testContext.getId(userName);
        if (userId == null) {
            throw new IllegalStateException("找不到用戶 '" + userName + "' 的 ID，請先建立用戶");
        }

        CartItem cartItem = new CartItem();
        cartItem.setUserId(userId);
        cartItem.setProductId(productId);
        cartItem.setQuantity(quantity);

        cartItemRepository.save(cartItem);
    }
}
```

DataTable 版本：

```java
@Given("系統中有以下用戶：")
public void 系統中有以下用戶(DataTable dataTable) {
    List<Map<String, String>> rows = dataTable.asMaps();
    for (Map<String, String> row : rows) {
        User user = new User();
        user.setId(row.get("userId"));
        user.setName(row.get("name"));
        user.setEmail(row.get("email"));
        userRepository.save(user);
        testContext.putId(row.get("name"), user.getId());
    }
}
```

#### Command（執行 HTTP API）

```java
@When("用戶 {string} 更新課程 {int} 的影片進度為 {int}%")
public void 用戶更新課程的影片進度為(String userName, int lessonId, int progress) {
    String userId = testContext.getId(userName);
    if (userId == null) {
        throw new IllegalStateException("找不到用戶 '" + userName + "' 的 ID");
    }

    String token = jwtHelper.generateToken(userId);

    Map<String, Object> requestBody = Map.of(
        "lessonId", lessonId,
        "progress", progress
    );

    HttpHeaders headers = new HttpHeaders();
    headers.setContentType(MediaType.APPLICATION_JSON);
    headers.setBearerAuth(token);

    HttpEntity<Map<String, Object>> request = new HttpEntity<>(requestBody, headers);

    ResponseEntity<String> response = testRestTemplate.exchange(
        "/api/v1/lesson-progress/update-video-progress",
        HttpMethod.POST,
        request,
        String.class
    );

    testContext.setLastResponse(response);
}
```

#### Query（執行 HTTP GET API）

```java
@When("用戶 {string} 查詢課程 {int} 的進度")
public void 用戶查詢課程的進度(String userName, int lessonId) {
    String userId = testContext.getId(userName);
    if (userId == null) {
        throw new IllegalStateException("找不到用戶 '" + userName + "' 的 ID");
    }

    String token = jwtHelper.generateToken(userId);
    String url = "/api/v1/lessons/" + lessonId + "/progress";

    HttpHeaders headers = new HttpHeaders();
    headers.setBearerAuth(token);

    HttpEntity<Void> request = new HttpEntity<>(headers);

    ResponseEntity<String> response = testRestTemplate.exchange(
        url,
        HttpMethod.GET,
        request,
        String.class
    );

    testContext.setLastResponse(response);
}
```

有 Query Parameters 時使用 `UriComponentsBuilder`：

```java
String url = UriComponentsBuilder
    .fromPath("/api/v1/journeys/" + journeyId + "/lessons")
    .queryParam("chapterId", chapterId)
    .toUriString();
```

#### Aggregate-Then（驗證 DB 狀態）

```java
import static org.assertj.core.api.Assertions.assertThat;

@Then("用戶 {string} 在課程 {int} 的進度應為 {int}%")
public void 用戶在課程的進度應為(String userName, int lessonId, int progress) {
    String userId = testContext.getId(userName);
    if (userId == null) {
        throw new IllegalStateException("找不到用戶 '" + userName + "' 的 ID");
    }

    LessonProgress progressEntity = lessonProgressRepository
            .findByUserIdAndLessonId(userId, lessonId)
            .orElse(null);

    assertThat(progressEntity)
            .as("找不到課程進度")
            .isNotNull();
    assertThat(progressEntity.getProgress())
            .as("預期進度 %d%%，實際 %d%%", progress, progressEntity.getProgress())
            .isEqualTo(progress);
}
```

#### ReadModel-Then（驗證 HTTP Response）

```java
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import static org.assertj.core.api.Assertions.assertThat;

@Then("查詢結果應包含進度 {int}，狀態為 {string}")
public void 查詢結果應包含進度狀態為(int progress, String status) throws Exception {
    String responseBody = testContext.getLastResponse().getBody().toString();
    JsonNode data = objectMapper.readTree(responseBody);

    String expectedStatus = mapStatus(status);

    assertThat(data.get("progress").asInt())
            .as("預期進度 %d", progress)
            .isEqualTo(progress);
    assertThat(data.get("status").asText())
            .as("預期狀態 %s", expectedStatus)
            .isEqualTo(expectedStatus);
}

private String mapStatus(String status) {
    return switch (status) {
        case "進行中" -> "IN_PROGRESS";
        case "已完成" -> "COMPLETED";
        case "未開始" -> "NOT_STARTED";
        default -> status;
    };
}
```

#### Success-Failure（驗證 HTTP Status Code）

```java
import static org.assertj.core.api.Assertions.assertThat;

@Then("操作成功")
public void 操作成功() {
    ResponseEntity<?> response = testContext.getLastResponse();
    assertThat(response.getStatusCode().is2xxSuccessful())
            .as("預期成功（2XX），實際 %s", response.getStatusCode())
            .isTrue();
}

@Then("操作失敗")
public void 操作失敗() {
    ResponseEntity<?> response = testContext.getLastResponse();
    assertThat(response.getStatusCode().is4xxClientError())
            .as("預期失敗（4XX），實際 %s", response.getStatusCode())
            .isTrue();
}
```

## API 呼叫模式

- **HTTP Client**：`@Autowired TestRestTemplate testRestTemplate`
- **認證**：`jwtHelper.generateToken(userId)` 產生 JWT，使用 `headers.setBearerAuth(token)` 設定
- **Command**：`testRestTemplate.exchange(url, HttpMethod.POST, request, String.class)`，response 存入 `testContext.setLastResponse(response)`
- **Query**：`testRestTemplate.exchange(url, HttpMethod.GET, request, String.class)`，response 存入 `testContext.setLastResponse(response)`
- **Request Body**：使用 `Map.of("key", value)` 構建，欄位名用 camelCase
- **Path Parameters**：直接字串拼接（`"/api/v1/lessons/" + lessonId + "/progress"`）
- **Query Parameters**：使用 `UriComponentsBuilder.fromPath(...).queryParam(...).toUriString()`

## 基礎設施定義

### JPA Entity

```java
// ${JAVA_MODEL_DIR}/CartItem.java
package com.wsa.platform.model;

import jakarta.persistence.*;

@Entity
@Table(name = "cart_items")
public class CartItem {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Integer id;

    @Column(name = "user_id", nullable = false)
    private String userId;

    @Column(name = "product_id", nullable = false)
    private String productId;

    @Column(nullable = false)
    private Integer quantity;

    // Getters and Setters
}
```

### Spring Data JPA Repository

```java
// ${JAVA_REPOSITORY_DIR}/CartItemRepository.java
package com.wsa.platform.repository;

import com.wsa.platform.model.CartItem;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface CartItemRepository extends JpaRepository<CartItem, Integer> {
    Optional<CartItem> findByUserIdAndProductId(String userId, String productId);
}
```

### Enum 類別

```java
// ${JAVA_MODEL_DIR}/ProgressStatus.java
package com.wsa.platform.model;

public enum ProgressStatus {
    IN_PROGRESS, COMPLETED, NOT_STARTED
}
```

## 特殊規則

1. **API JSON 欄位命名使用 camelCase**：Request body 和 Response assert 都使用 camelCase（Java 慣例）。`Map.of("lessonId", 1)` 而非 `Map.of("lesson_id", 1)`。
2. **API Endpoint Path**：必須嚴格遵循 `specs/api.yml`，透過 `summary` 欄位與 Gherkin 語句對應找到正確的 path 和 HTTP method。
3. **中文狀態映射到 Java enum**：使用 `switch` expression 將中文（如「進行中」）映射為 enum 值（如 `ProgressStatus.IN_PROGRESS`）。Entity 的 status 欄位使用 `@Enumerated(EnumType.STRING)` 標註。
4. **ID 儲存**：Given 建立的實體 ID 必須存入 `testContext.putId(naturalKey, id)`，後續透過 `testContext.getId(key)` 取得。
5. **不驗證 Response（Command）**：Command Handler 只儲存 response 到 ScenarioContext，不做 assertThat，驗證交給 Then。
6. **不重新呼叫 API（ReadModel-Then）**：使用 When 中儲存的 `testContext.getLastResponse()`，不重新發請求。
7. **AssertJ 清晰訊息**：使用 `.as("描述")` 提供失敗時的診斷訊息。
8. **PendingException 作為樣板佔位符**：Step Template 生成的樣板使用 `throw new io.cucumber.java.PendingException()` 而非空方法。
9. **Testcontainers 環境**：CucumberSpringConfiguration 管理 Testcontainers 生命週期，執行前需確認 Docker Desktop 已啟動。
10. **紅燈完成後移除 `@ignore` tag**：讓 feature file 可被 `--tags="not @ignore"` 回歸測試涵蓋。
