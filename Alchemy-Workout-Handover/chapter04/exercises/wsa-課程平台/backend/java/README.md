# WSA 課程平台 - Java 版本

## 技術棧

- **Java**: 17
- **Framework**: Spring Boot 3.2
- **ORM**: Spring Data JPA / Hibernate
- **Database**: PostgreSQL 15 (via Testcontainers)
- **BDD Testing**: Cucumber 7.15
- **Migration**: Flyway

## 目錄結構

```
java/
├── src/
│   ├── main/
│   │   ├── java/com/wsa/platform/
│   │   │   ├── api/           # REST Controllers
│   │   │   ├── model/         # JPA Entities
│   │   │   ├── repository/    # Spring Data repositories
│   │   │   ├── service/       # Business logic
│   │   │   ├── dto/           # Request/Response DTOs
│   │   │   ├── security/      # JWT authentication
│   │   │   └── Application.java
│   │   └── resources/
│   │       ├── application.yml
│   │       ├── application-test.yml
│   │       └── db/migration/  # Flyway migrations
│   └── test/
│       ├── java/com/wsa/platform/
│       │   ├── cucumber/      # Cucumber config
│       │   │   ├── CucumberSpringConfiguration.java
│       │   │   ├── ScenarioContext.java
│       │   │   └── JwtHelper.java
│       │   ├── steps/         # Step definitions
│       │   │   ├── aggregate_given/
│       │   │   ├── commands/
│       │   │   ├── query/
│       │   │   ├── aggregate_then/
│       │   │   ├── readmodel_then/
│       │   │   └── common_then/
│       │   └── RunCucumberTest.java
│       └── resources/
│           ├── cucumber.properties
│           └── features/      # Symlink to shared features
├── prompts/                   # AI prompts for development
│   ├── e2e/                  # E2E testing prompts
│   │   ├── handlers/         # Handler patterns
│   │   └── *.md              # Workflow prompts
│   └── rules/                # Development rules
├── specs/                     # API specifications
└── pom.xml                    # Maven dependencies
```

## 快速開始

### 前置條件

- Java 17
- Maven 3.8+
- Docker (for Testcontainers)

### 編譯專案

```bash
cd java
mvn compile
```

### 執行測試

```bash
cd java
mvn clean test
```

### 執行特定 Feature

```bash
mvn clean test -Dcucumber.features=src/test/resources/features/01-增加影片進度.feature
```

## Flyway Migration × JPA Entities 一致性驗證（方案 E）

Flyway 本身**不會自動產生** migration SQL（它只負責「執行、追蹤、驗證 checksum」）。

為了讓「AI 產生的 Flyway migration SQL」更可靠，本專案加入一個**驗證護欄**：

- **測試類**：`src/test/java/com/wsa/platform/migration/MigrationValidationTest.java`
- **驗證方式**：Hibernate `ddl-auto=validate`（只驗證、不改資料庫）
- **使用時機**：每次跑完 `mvn flyway:migrate` 後立刻跑一次

```bash
cd java

# 1) 套用/更新 migration
mvn flyway:migrate

# 2) 驗證資料庫 schema 是否與 JPA entities 完全一致（只驗證，不修改）
mvn clean test -Dtest=MigrationValidationTest
```

若驗證失敗，Hibernate 會輸出詳細錯誤（例如：缺欄位、型別不符、nullable 不一致），依錯誤修正後再重跑 migration 與驗證即可。

## E2E 開發流程

使用 prompts/e2e/ 中的 prompts 進行 BDD 開發：

1. **00-資料表及遷移分析.md** - 分析 Feature 需要的資料結構（Flyway migration）
2. **01-Feature-to-Step-Definition-樣板.md** - 產生 Step Definition 樣板
3. **02-紅燈.md** - 執行 mvn clean test 確認紅燈
4. **03-綠燈.md** - 實作程式碼讓測試通過
5. **04-重構.md** - 重構程式碼

## 與 Python 版本的關係

本 Java 版本與 Python 版本共用相同的 Feature Files（位於 `../features/`），確保兩個版本的行為一致。
