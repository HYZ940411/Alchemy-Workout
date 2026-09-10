# Green Variant: java-e2e

## 測試命令

```bash
# 開發階段：執行特定 Feature 檔案（快速迭代）
mvn clean test -Dtest=RunCucumberTest -Dcucumber.features=${JAVA_TEST_FEATURES_DIR}/xxx.feature

# 開發階段：執行特定 Scenario（最快）
mvn clean test -Dtest=RunCucumberTest -Dcucumber.features=${JAVA_TEST_FEATURES_DIR}/xxx.feature -Dcucumber.filter.name="scenario name"

# 完成階段：執行所有已完成紅燈的測試（總回歸測試）
mvn clean test -Dtest=RunCucumberTest -Dcucumber.filter.tags="not @ignore"
```

**為什麼使用 `not @ignore`？**
- 只執行已完成紅燈實作的 features（已移除 `@ignore` 標籤）
- 避免執行尚未實作的 features 造成混淆
- 確保回歸測試的範圍清晰明確

## 實作模式

### 實作目標

DTO → Service → Controller → Route 註冊

### 實作順序

根據測試錯誤訊息逐步實作：

1. 執行測試 → `mvn clean test -Dtest=RunCucumberTest -Dcucumber.features=${JAVA_TEST_FEATURES_DIR}/xxx.feature`
2. 看錯誤訊息（HTTP 404? 500? 400?）
3. 根據錯誤補充最少的程式碼（DTO → Service → Controller → 路由註冊）
4. 再次執行測試
5. 循環直到特定測試通過
6. 執行總回歸測試 → `mvn clean test -Dtest=RunCucumberTest -Dcucumber.filter.tags="not @ignore"`

### 最小增量範例

```java
// 做太多了（測試沒要求）
@PostMapping("/lesson-progress/update-video-progress")
public ResponseEntity<?> updateVideoProgress(@RequestBody UpdateVideoProgressRequest request) {
    validateInventory();      // 沒測試
    sendEmailNotification();  // 沒測試
    logAuditTrail();         // 沒測試
    return updateProgressLogic(request);
}

// 剛好夠（只實作測試要求的）
@PostMapping("/lesson-progress/update-video-progress")
public ResponseEntity<?> updateVideoProgress(@RequestBody UpdateVideoProgressRequest request) {
    return updateProgressLogic(request);
}
```

## 框架 API

### Spring Boot Controller 建立

```java
// ${JAVA_CONTROLLER_DIR}/LessonProgressController.java
package com.wsa.platform.controller;

import org.springframework.web.bind.annotation.*;
import org.springframework.http.ResponseEntity;

@RestController
@RequestMapping("/api/v1")
public class LessonProgressController {

    @PostMapping("/lesson-progress/update-video-progress")
    public ResponseEntity<?> updateVideoProgress(@RequestBody UpdateVideoProgressRequest request) {
        // TODO: 實作業務邏輯
        return ResponseEntity.ok().build();
    }
}
```

### Service 注入

```java
@Service
public class LessonProgressService {

    @Autowired
    private LessonProgressRepository lessonProgressRepository;

    public void updateProgress(Long userId, Long lessonId, int progress) {
        // 業務邏輯
    }
}
```

### JPA Entity 映射

```java
@Entity
@Table(name = "lesson_progress")
public class LessonProgress {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    // 必須有無參數 constructor（JPA 要求）
    protected LessonProgress() {}
}
```

### Spring Data JPA Repository

```java
@Repository
public interface LessonProgressRepository extends JpaRepository<LessonProgress, Long> {
    List<LessonProgress> findByUserId(Long userId);
    Optional<LessonProgress> findByIdAndUserId(Long id, Long userId);
}
```

## 常見錯誤修復

### HTTP 404 Not Found
**原因**：API Endpoint 不存在
**修復**：
1. 在 `${JAVA_CONTROLLER_DIR}/` 中創建 Controller
2. 確保 `@RestController` 和 `@RequestMapping` 正確

### HTTP 500 Internal Server Error
**原因**：後端程式碼有錯誤
**修復**：
1. 檢查錯誤訊息和 stack trace
2. 修正 Service/Repository 的邏輯

### HTTP 400 Bad Request
**原因**：業務規則驗證失敗
**修復**：
1. 確認業務規則正確實作
2. 調整驗證邏輯

### HTTP 401 Unauthorized
**原因**：JWT Token 驗證失敗
**修復**：
1. 確認 Security 配置正確
2. 確認 JWT 密鑰與測試用的 JwtHelper 一致

### Spring Application Context 啟動失敗
**錯誤訊息**：`Unable to start application context` / `Failed to load ApplicationContext`
**常見原因**：
- `@Autowired` 注入的 Bean 不存在
- `@ComponentScan` 範圍沒涵蓋到 Service 或 Repository
- `application.yml` / `application.properties` 缺少必要設定

**診斷步驟**：
1. 看 stack trace 的 `Caused by: org.springframework.beans.factory.NoSuchBeanDefinitionException`
2. 確認 Bean 的類別上有 `@Service`、`@Repository`、`@Component` 等標記
3. 確認 `@SpringBootApplication` 的 package 範圍能掃到這些 Bean

```java
// 常見錯誤：忘記加 @Service 標記
public class LessonProgressService { ... }  // 沒有標記

// 修正
@Service
public class LessonProgressService { ... }  // 正確
```

### Spring Bean 注入失敗
**錯誤訊息**：`BeanCreationException` / `UnsatisfiedDependencyException`
**常見原因**：
- 循環依賴（A 注入 B，B 注入 A）
- Interface 有多個實作但沒有 `@Primary` 或 `@Qualifier`

**修復**：
```java
// 循環依賴解法：用 @Lazy 打破循環
@Autowired
@Lazy
private SomeService someService;
```

### JPA / Hibernate 映射錯誤
**錯誤訊息**：`InvalidDefinitionException` / `SerializationException` / `Column xxx not found`
**診斷步驟**：
```
錯誤 → "could not execute statement"
  └→ 看 SQL 語句，確認 column name 正確
  └→ 確認 @Entity 的 @Table(name = "...") 對應正確資料表名稱
  └→ 確認 @Column(name = "...") 對應正確欄位名稱
```

### Cucumber Step Definition 找不到
**錯誤訊息**：`You can implement missing steps with the snippets below` / `Undefined step`
**原因**：Step Definition 的 `@Given`/`@When`/`@Then` pattern 與 feature file 的 step 文字不匹配
**修復**：
1. 對比 feature 中的 step 文字與 Step Definition 的 pattern（大小寫、標點符號都要一致）
2. 確認 Step Definition 的 Java 類別在 `@CucumberOptions` 的 `glue` 路徑下

```java
// Feature 寫的：When 行銷人員提交完整的 Lead 資料
// 不匹配（多了空格）
@When("行銷人員提交 完整的 Lead 資料")
public void submitLeadData() { ... }

// 完全匹配
@When("行銷人員提交完整的 Lead 資料")
public void submitLeadData() { ... }
```

## 迭代策略

### 開發循環（快速迭代）

```
1. 執行特定測試 → mvn clean test -Dcucumber.features=xxx.feature
2. 看錯誤訊息 → 理解失敗原因
3. 寫最少的程式碼修正這個錯誤
4. 再次執行特定測試 → mvn clean test -Dcucumber.features=xxx.feature
5. 還有錯誤？回到步驟 2
6. 特定測試通過？進入完成驗證
```

### 完成驗證（回歸測試）

```
7. 執行所有已完成紅燈的測試 → mvn clean test -Dcucumber.filter.tags="not @ignore"
8. 所有測試通過？完成綠燈！
9. 有測試失敗？回到步驟 2，修復破壞的測試
```

### 範例執行流程

```
開發階段（快速迭代）：
→ mvn clean test -Dcucumber.features=xxx.feature
  FAILED: HTTP 404 Not Found

→ 建立 API endpoint
→ mvn clean test -Dcucumber.features=xxx.feature
  FAILED: HTTP 500 Internal Server Error

→ 修正 Service 邏輯
→ mvn clean test -Dcucumber.features=xxx.feature
  FAILED: HTTP 400 Bad Request (進度不可倒退)

→ 調整業務規則驗證
→ mvn clean test -Dcucumber.features=xxx.feature
  PASSED（特定測試通過）

完成驗證（回歸測試）：
→ mvn clean test -Dcucumber.filter.tags="not @ignore"
  2 features passed, 5 scenarios passed（所有測試通過，真正完成！）
```

### 完成判定標準

```
特定測試通過 → 功能開發完成
                |
                v
         執行總回歸測試
                |
                v
  mvn clean test -Dtest=RunCucumberTest -Dcucumber.filter.tags="not @ignore"
                |
                v
   所有已完成紅燈的測試通過
                |
                v
         真正完成綠燈！
```

## Docker / 環境

### 執行前確認

```bash
# 1. 確認 Docker Desktop 是否在運行
docker ps

# 如果未啟動，在 macOS 執行：
open -a Docker

# 2. 確認 Docker Daemon 正常響應
docker info
```

### 常見錯誤訊息與解法

| 錯誤訊息 | 原因 | 解法 |
|---------|------|------|
| `java.lang.IllegalStateException: Could not find a valid Docker environment` | Docker Desktop 未啟動 | 執行 `open -a Docker`（macOS）或啟動 Docker Desktop |
| `org.testcontainers.containers.ContainerLaunchException` | PostgreSQL 容器啟動失敗 | 確認 Docker 正常，執行 `docker pull postgres:16` 預載 image |
| `Connection refused` 在測試執行中途 | Testcontainers 初始化異常 | 確認 `CucumberSpringConfiguration` 正確設定 Testcontainers 生命週期 |
| `Failed to load ApplicationContext` + Docker 相關錯誤 | Spring 啟動時無法連線資料庫 | 確認 Docker Desktop 已啟動，查看完整 stack trace |

### 診斷步驟

```
錯誤 → "Could not find a valid Docker environment"
  └→ 執行 `docker ps`
       ├→ 成功：Docker 正常，問題在其他地方（查看完整 stack trace）
       └→ 失敗：啟動 Docker Desktop，再重新執行測試
```

### 完成條件

- [ ] 執行特定測試 `mvn clean test -Dtest=RunCucumberTest -Dcucumber.features=xxx.feature` 通過
- [ ] 執行總回歸測試 `mvn clean test -Dtest=RunCucumberTest -Dcucumber.filter.tags="not @ignore"` 所有測試通過
- [ ] 沒有破壞既有功能
- [ ] 程式碼簡單直接
- [ ] 未引入任何測試未要求的功能
