# Starter Variant: Java E2E

技術棧：Spring Boot 3.2 + JPA + Cucumber 7.15 + Testcontainers (PostgreSQL) + Flyway

---

## 目錄結構

```
${PROJECT_ROOT}/
├── src/
│   ├── main/
│   │   ├── java/${BASE_PACKAGE_PATH}/          # 例：com/wsa/platform/
│   │   │   ├── Application.java                # Spring Boot 入口（@SpringBootApplication）
│   │   │   └── security/
│   │   │       ├── JwtTokenFilter.java         # JWT 過濾器（OncePerRequestFilter）
│   │   │       └── CurrentUser.java            # 從 request attribute 取得當前用戶 ID
│   │   └── resources/
│   │       ├── application.yml                 # 主設定（DB、JPA、Flyway、JWT）
│   │       ├── application-test.yml            # 測試環境（Testcontainers jdbc:tc: URL）
│   │       └── db/migration/                   # Flyway migration SQL 檔案
│   └── test/
│       ├── java/${BASE_PACKAGE_PATH}/
│       │   ├── RunCucumberTest.java            # Cucumber 入口（JUnit Platform Suite）
│       │   ├── cucumber/
│       │   │   ├── CucumberSpringConfiguration.java  # @CucumberContextConfiguration + @SpringBootTest
│       │   │   ├── ScenarioContext.java               # @ScenarioScope 狀態管理
│       │   │   ├── DatabaseCleanupHook.java           # @Before hook：DELETE + RESET sequence
│       │   │   └── JwtHelper.java                     # 測試用 JWT Token 產生器
│       │   └── steps/
│       │       ├── common_then/
│       │       │   └── CommonThen.java                # 操作成功/失敗/錯誤訊息 通用步驟
│       │       └── helpers/
│       │           └── ScenarioContextHelper.java     # 取得 userId 等便利方法
│       └── resources/
│           └── features/                       # .feature 檔案放置處
├── ${SPECS_ROOT_DIR}/                          # 規格檔案（例：specs/）
│   ├── activities/
│   ├── features/
│   └── clarify/
└── pom.xml
```

---

## 依賴安裝（Maven）

### pom.xml 完整依賴

```xml
<parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.2.0</version>
</parent>

<properties>
    <java.version>17</java.version>
    <cucumber.version>7.15.0</cucumber.version>
    <testcontainers.version>1.19.3</testcontainers.version>
</properties>

<dependencies>
    <!-- Spring Boot Starters -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-data-jpa</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-validation</artifactId>
    </dependency>

    <!-- Database -->
    <dependency>
        <groupId>org.postgresql</groupId>
        <artifactId>postgresql</artifactId>
        <scope>runtime</scope>
    </dependency>
    <dependency>
        <groupId>org.flywaydb</groupId>
        <artifactId>flyway-core</artifactId>
    </dependency>

    <!-- JWT (JJWT 0.12.3) -->
    <dependency>
        <groupId>io.jsonwebtoken</groupId>
        <artifactId>jjwt-api</artifactId>
        <version>0.12.3</version>
    </dependency>
    <dependency>
        <groupId>io.jsonwebtoken</groupId>
        <artifactId>jjwt-impl</artifactId>
        <version>0.12.3</version>
        <scope>runtime</scope>
    </dependency>
    <dependency>
        <groupId>io.jsonwebtoken</groupId>
        <artifactId>jjwt-jackson</artifactId>
        <version>0.12.3</version>
        <scope>runtime</scope>
    </dependency>

    <!-- Testing -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-test</artifactId>
        <scope>test</scope>
    </dependency>

    <!-- Cucumber -->
    <dependency>
        <groupId>io.cucumber</groupId>
        <artifactId>cucumber-java</artifactId>
        <version>${cucumber.version}</version>
        <scope>test</scope>
    </dependency>
    <dependency>
        <groupId>io.cucumber</groupId>
        <artifactId>cucumber-spring</artifactId>
        <version>${cucumber.version}</version>
        <scope>test</scope>
    </dependency>
    <dependency>
        <groupId>io.cucumber</groupId>
        <artifactId>cucumber-junit-platform-engine</artifactId>
        <version>${cucumber.version}</version>
        <scope>test</scope>
    </dependency>
    <dependency>
        <groupId>org.junit.platform</groupId>
        <artifactId>junit-platform-suite</artifactId>
        <scope>test</scope>
    </dependency>

    <!-- Testcontainers -->
    <dependency>
        <groupId>org.testcontainers</groupId>
        <artifactId>testcontainers</artifactId>
        <version>${testcontainers.version}</version>
        <scope>test</scope>
    </dependency>
    <dependency>
        <groupId>org.testcontainers</groupId>
        <artifactId>postgresql</artifactId>
        <version>${testcontainers.version}</version>
        <scope>test</scope>
    </dependency>
    <dependency>
        <groupId>org.testcontainers</groupId>
        <artifactId>junit-jupiter</artifactId>
        <version>${testcontainers.version}</version>
        <scope>test</scope>
    </dependency>

    <!-- Lombok (optional) -->
    <dependency>
        <groupId>org.projectlombok</groupId>
        <artifactId>lombok</artifactId>
        <optional>true</optional>
    </dependency>
</dependencies>
```

### Maven Plugins

- `maven-compiler-plugin 3.13.0`：release = 17
- `spring-boot-maven-plugin`：排除 Lombok
- `maven-surefire-plugin`：只 include `**/RunCucumberTest.java`
- `flyway-maven-plugin 9.22.3`：開發環境用 migration 管理

安裝指令：`mvn clean compile`

---

## 設定檔說明

### application.yml

```yaml
spring:
  application:
    name: {{ARTIFACT_ID}}
  datasource:
    url: jdbc:postgresql://localhost:5432/{{ARTIFACT_ID}}_dev
    username: postgres
    password: postgres
    driver-class-name: org.postgresql.Driver
  jpa:
    hibernate:
      ddl-auto: validate       # 不自動建表，靠 Flyway
    show-sql: true
    properties:
      hibernate:
        format_sql: true
        dialect: org.hibernate.dialect.PostgreSQLDialect
  flyway:
    enabled: true
    locations: classpath:db/migration
    baseline-on-migrate: true

server:
  port: 8080

jwt:
  secret-key: chapter04-test-secret-key-do-not-use-in-production
  algorithm: HS256
  expire-hours: 1

api:
  v1:
    prefix: /api/v1
```

### application-test.yml（Testcontainers 自動管理 DB）

```yaml
spring:
  datasource:
    url: jdbc:tc:postgresql:15:///{{ARTIFACT_ID}}_test    # tc: 前綴啟用 Testcontainers
    username: postgres
    password: postgres
    driver-class-name: org.testcontainers.jdbc.ContainerDatabaseDriver
  jpa:
    hibernate:
      ddl-auto: validate
    show-sql: false
  flyway:
    enabled: true
    locations: classpath:db/migration
    baseline-on-migrate: true
    clean-disabled: false

jwt:
  secret-key: chapter04-test-secret-key-do-not-use-in-production
  algorithm: HS256
  expire-hours: 1
```

關鍵：`jdbc:tc:postgresql:15:///` URL 讓 Testcontainers 自動啟動 PostgreSQL 15 容器，不需手動管理容器生命週期。

---

## 測試框架設定（Cucumber + Spring Boot Test）

### RunCucumberTest.java（Cucumber 入口）

```java
@Suite
@IncludeEngines("cucumber")
@SelectClasspathResource("features")
@ConfigurationParameter(key = GLUE_PROPERTY_NAME,
    value = "{{BASE_PACKAGE}}.cucumber, {{BASE_PACKAGE}}.steps")
@ConfigurationParameter(key = PLUGIN_PROPERTY_NAME,
    value = "pretty, html:target/cucumber-reports.html")
@ConfigurationParameter(key = FILTER_TAGS_PROPERTY_NAME,
    value = "not @ignore")
public class RunCucumberTest {
}
```

### CucumberSpringConfiguration.java

```java
@CucumberContextConfiguration
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("test")
public class CucumberSpringConfiguration {
    @LocalServerPort
    private int port;

    public String getBaseUrl() {
        return "http://localhost:" + port;
    }
}
```

### ScenarioContext.java（@ScenarioScope 狀態管理）

```java
@Component
@ScenarioScope
public class ScenarioContext {
    private ResponseEntity<?> lastResponse;
    private final Map<String, Object> ids = new HashMap<>();
    private final Map<String, Object> memo = new HashMap<>();
    private String jwtToken;
    private Object queryResult;
    private String lastError;

    // getter / setter / putId / getId / hasId / putMemo / getMemo / clear()
}
```

與 Python 的 `context.ids`、`context.memo` 對應。

### DatabaseCleanupHook.java

```java
public class DatabaseCleanupHook {
    @Autowired private JdbcTemplate jdbcTemplate;
    @Autowired private ScenarioContext scenarioContext;

    @Before(order = 0)
    public void cleanDatabase() {
        scenarioContext.clear();
        // TODO: 加入 DELETE 語句（注意外鍵順序，先刪子表）
        // jdbcTemplate.execute("DELETE FROM order_items");
        // jdbcTemplate.execute("DELETE FROM orders");
        // TODO: 重設 sequence
        // jdbcTemplate.execute("ALTER SEQUENCE users_id_seq RESTART WITH 1");
    }
}
```

注意：此檔案的 DELETE/RESET 語句需使用者在加入 Entity 後自行填入。

### JwtHelper.java（測試用 JWT 產生器）

```java
@Component
public class JwtHelper {
    private final SecretKey secretKey;  // 從 jwt.secret-key 讀取
    private final int expireHours;     // 從 jwt.expire-hours 讀取

    public String generateToken(String userId) {
        return Jwts.builder()
                .subject(userId)
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plus(expireHours, ChronoUnit.HOURS)))
                .signWith(secretKey)
                .compact();
    }

    public String verifyToken(String token) { ... }
}
```

---

## 安全機制

### JwtTokenFilter.java（主程式 JWT 過濾器）

```java
@Component
public class JwtTokenFilter extends OncePerRequestFilter {
    public static final String CURRENT_USER_ID_ATTRIBUTE = "currentUserId";
    // 解析 Authorization: Bearer <token>
    // 成功 → request.setAttribute(CURRENT_USER_ID_ATTRIBUTE, userId)
    // 失敗 → 401 JSON 回應
}
```

### CurrentUser.java（Controller 取得當前用戶）

```java
public class CurrentUser {
    public static Long getId(HttpServletRequest request) {
        // 從 request attribute 取得 currentUserId，若無則拋 401
    }
    public static Long getIdOrNull(HttpServletRequest request) {
        // 同上但允許 null（用於可選認證的 API）
    }
}
```

---

## 通用步驟定義

### CommonThen.java

```java
public class CommonThen {
    @Then("操作成功")
    public void operationSuccessful() {
        // 檢查 HTTP status code 為 2XX（200~299）
    }

    @Then("操作失敗")
    public void operationFailed() {
        // 檢查 HTTP status code 為 4XX（400~499）
    }

    @Then("錯誤訊息應為 {string}")
    public void errorMessageShouldBe(String expectedMessage) {
        // 從 response body 提取 message / detail / error 欄位
    }

    @Then("操作失敗，原因為 {string}")
    public void operationFailedWithReason(String reason) {
        // 組合：操作失敗 + 錯誤訊息
    }
}
```

### ScenarioContextHelper.java

```java
@Component
public class ScenarioContextHelper {
    public Long getUserId(String userName) {
        // 從 ScenarioContext.ids 取得用戶 ID（Given 步驟中建立的）
    }
    public String getUserIdAsString(String userName) { ... }
}
```

---

## arguments.yml 變數對照

| Placeholder | 來源 | 說明 | 範例 |
|-------------|------|------|------|
| `{{PROJECT_NAME}}` | 詢問使用者 | 專案顯示名稱 | `課程平台` |
| `{{PROJECT_DESCRIPTION}}` | 詢問使用者 | 專案描述 | `BDD Workshop - Java Spring Boot` |
| `{{GROUP_ID}}` | arguments.yml | Maven groupId | `com.wsa` |
| `{{ARTIFACT_ID}}` | arguments.yml | Maven artifactId | `platform` |
| `{{BASE_PACKAGE}}` | arguments.yml | Java base package | `com.wsa.platform` |
| `{{BASE_PACKAGE_PATH}}` | 從 BASE_PACKAGE 推導 | 檔案系統路徑（`.` → `/`） | `com/wsa/platform` |
| `{{SPECS_ROOT_DIR}}` | arguments.yml | 規格檔案根目錄 | `specs` |

推導規則：
- `BASE_PACKAGE_PATH` = BASE_PACKAGE 中 `.` 換成 `/`

---

## 與 Python E2E 的差異

| 項目 | Python E2E | Java E2E |
|------|------------|----------|
| Framework | FastAPI + SQLAlchemy | Spring Boot 3.2 + JPA |
| Test Runner | Behave | Cucumber 7.15 + JUnit Platform Suite |
| DB Container | Testcontainers（顯式 start/stop） | Testcontainers（`jdbc:tc:` URL 自動管理） |
| Migration | Alembic | Flyway |
| Build Tool | pip + requirements.txt | Maven (pom.xml) |
| JWT | PyJWT | JJWT 0.12.3 |
| Package 結構 | 平坦目錄 + `__init__.py` | 分層 package（base package 可配置） |
| DB Cleanup | after_scenario TRUNCATE CASCADE | @Before hook DELETE + RESET sequence |
| Context 管理 | Behave context 直接掛屬性 | @ScenarioScope Spring Bean (ScenarioContext) |

---

## 環境需求

- **Java**: 17+
- **Maven**: 3.8+
- **Docker**: 需要執行中的 Docker daemon（Testcontainers 使用 `jdbc:tc:` URL 自動管理 PostgreSQL 15 容器）
- **PostgreSQL**: 不需手動安裝，完全由 Testcontainers 管理
- **作業系統**: macOS / Linux（Testcontainers 依賴 Docker socket）

---

## Template 檔案對照表

| Template 檔名（`__` = `/`，`BASE_PKG` = `${BASE_PACKAGE_PATH}`） | 輸出路徑 |
|-------------------------------------------------------------------|----------|
| `pom.xml` | `pom.xml` |
| `src__main__resources__application.yml` | `src/main/resources/application.yml` |
| `src__main__resources__application-test.yml` | `src/main/resources/application-test.yml` |
| `src__main__java__BASE_PKG__Application.java` | `src/main/java/${BASE_PACKAGE_PATH}/Application.java` |
| `src__main__java__BASE_PKG__security__JwtTokenFilter.java` | `src/main/java/${BASE_PACKAGE_PATH}/security/JwtTokenFilter.java` |
| `src__main__java__BASE_PKG__security__CurrentUser.java` | `src/main/java/${BASE_PACKAGE_PATH}/security/CurrentUser.java` |
| `src__test__java__BASE_PKG__RunCucumberTest.java` | `src/test/java/${BASE_PACKAGE_PATH}/RunCucumberTest.java` |
| `src__test__java__BASE_PKG__cucumber__CucumberSpringConfiguration.java` | `src/test/java/${BASE_PACKAGE_PATH}/cucumber/CucumberSpringConfiguration.java` |
| `src__test__java__BASE_PKG__cucumber__ScenarioContext.java` | `src/test/java/${BASE_PACKAGE_PATH}/cucumber/ScenarioContext.java` |
| `src__test__java__BASE_PKG__cucumber__DatabaseCleanupHook.java` | `src/test/java/${BASE_PACKAGE_PATH}/cucumber/DatabaseCleanupHook.java` |
| `src__test__java__BASE_PKG__cucumber__JwtHelper.java` | `src/test/java/${BASE_PACKAGE_PATH}/cucumber/JwtHelper.java` |
| `src__test__java__BASE_PKG__steps__common_then__CommonThen.java` | `src/test/java/${BASE_PACKAGE_PATH}/steps/common_then/CommonThen.java` |
| `src__test__java__BASE_PKG__steps__helpers__ScenarioContextHelper.java` | `src/test/java/${BASE_PACKAGE_PATH}/steps/helpers/ScenarioContextHelper.java` |

---

## 驗證步驟

完成骨架建立後，確認以下事項：

1. **檔案完整性**：所有 template 對照表中的檔案都已寫入目標路徑
2. **Placeholder 替換**：專案中不應殘留任何 `{{...}}` 字串
3. **目錄結構**：`src/main/resources/db/migration/` 目錄已建立
4. **編譯測試**：`mvn clean compile` 能正常完成
5. **Cucumber 可執行**：`mvn clean test` 能啟動（無 feature 檔案時 0 scenarios）

---

## 安全規則

- 不覆蓋已存在的檔案（跳過並回報）
- 不建立 feature-specific 程式碼（JPA Entities、Repositories、Services、Controllers、Step Definitions）
- 不執行 `mvn install` 或 `flyway migrate`
- DatabaseCleanupHook 中的 DELETE/RESET 語句需使用者在加入 Entity 後自行填入

---

## 完成後引導

```
Walking skeleton 已建立完成。

下一步：
1. cd ${PROJECT_ROOT} && mvn clean test
2. /aibdd-discovery — 開始需求探索
```
