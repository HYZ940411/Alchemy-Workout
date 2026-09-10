# Refactor Variant: Java E2E

## Linter / Formatter

```bash
mvn spotless:apply    # 自動排版（需 spotless-maven-plugin）
mvn checkstyle:check  # 程式碼風格檢查
```

或使用 IDE 內建：IntelliJ IDEA → Code → Reformat Code

## 測試命令

```bash
# 每次重構後必須執行
mvn clean test -Dtest=RunCucumberTest -Dcucumber.filter.tags="not @ignore"
```

## 入口

### 被 control-flow 調用

接收目標程式碼路徑，確認綠燈後進入重構流程。

### 獨立使用

1. 詢問目標範圍（Feature 相關的程式碼）
2. 執行測試確認綠燈
3. 進入重構流程

---

## Java 特有重構模式

### Record 類別（Java 17+）

DTO 若只是資料容器，改用 `record`：

```java
// 重構前
public class UpdateVideoProgressRequest {
    private int lessonId;
    private int progress;
    // getters, setters, constructors...
}

// 重構後
public record UpdateVideoProgressRequest(int lessonId, int progress) {}
```

### Enum with Switch Expression

```java
// 重構前
private String mapStatus(String status) {
    if (status.equals("進行中")) return "IN_PROGRESS";
    else if (status.equals("已完成")) return "COMPLETED";
    else return status;
}

// 重構後
private ProgressStatus mapStatus(String status) {
    return switch (status) {
        case "進行中" -> ProgressStatus.IN_PROGRESS;
        case "已完成" -> ProgressStatus.COMPLETED;
        case "未開始" -> ProgressStatus.NOT_STARTED;
        default -> ProgressStatus.valueOf(status);
    };
}
```

### Spring Annotation 慣例

- `@Service` — 業務邏輯層
- `@Repository` — 資料存取層
- `@RestController` — API 控制器
- `@Component` — 通用 Bean
- `@ScenarioScope` — Cucumber 測試狀態

### AssertJ 斷言風格

```java
// 重構前
assert progressEntity != null;
assert progressEntity.getProgress() == 80;

// 重構後
assertThat(progressEntity).as("找不到課程進度").isNotNull();
assertThat(progressEntity.getProgress()).as("預期進度 80%%").isEqualTo(80);
```

### Cucumber Step 整理

- 類別命名：`{Feature}{StepType}Steps.java`
- 共用 helper 提取到 utility class
- ScenarioContext 集中管理測試狀態
- DataTable 轉換邏輯可抽取為 private method

```java
// 共用 helper
public class StatusMapper {
    public static ProgressStatus map(String chinese) {
        return switch (chinese) {
            case "進行中" -> ProgressStatus.IN_PROGRESS;
            case "已完成" -> ProgressStatus.COMPLETED;
            case "未開始" -> ProgressStatus.NOT_STARTED;
            default -> ProgressStatus.valueOf(chinese);
        };
    }
}
```

### Import 排序（IntelliJ 預設）

```java
// 1. java.*
import java.util.List;

// 2. javax.* / jakarta.*
import jakarta.persistence.*;

// 3. 第三方
import org.springframework.beans.factory.annotation.Autowired;
import io.cucumber.java.en.Given;

// 4. 本地
import com.wsa.platform.model.LessonProgress;
```

---

## 常見重構方向

### Step Definition 層
- 提取共用的 Given 步驟到共用類別
- 統一 ScenarioContext 的使用模式
- 消除重複的 status mapping 邏輯
- 改善 DataTable 解析的可讀性

### Service 層
- 提取業務規則為獨立方法
- 消除過長的方法
- 引入 Strategy Pattern 處理條件分支
- 統一異常處理模式

### Controller 層
- 統一 API 回應格式
- 提取共用的驗證邏輯
- 統一錯誤回應結構

### Entity / Repository 層
- 添加缺少的 JPA 註解
- 優化查詢方法命名
- 添加自訂查詢（@Query）提升效能

### 重構粒度範例

- 提取一個方法
- 重命名一個變數或方法
- 消除一個重複片段
- 將 magic number 提取為常數
- 調整一個類別的職責

---

## 品質規範

完整 Java 品質規範詳見 `references/code-quality/java.md`。
