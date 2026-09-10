package com.wsa.platform.migration;

import jakarta.persistence.EntityManagerFactory;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import static org.junit.jupiter.api.Assertions.assertNotNull;

/**
 * Migration 驗證測試
 * 
 * 目的：確保 Flyway Migration SQL 與 JPA Entities 完全一致
 * 
 * 原理：
 * - 使用 Hibernate 的 validate 模式
 * - Hibernate 會比對資料庫 schema 與 JPA entities
 * - 如果不一致，會在啟動時拋出詳細的錯誤訊息
 * 
 * 執行時機：
 * - 每次執行完 mvn flyway:migrate 後立即執行
 * - 整合到 00-資料表及遷移分析.md 流程中
 * 
 * 執行方式：
 * mvn clean test -Dtest=MigrationValidationTest
 */
@SpringBootTest(properties = {
    // DataSource (對齊 java/docker-compose.yml 與 flyway-maven-plugin 設定)
    "spring.datasource.url=jdbc:postgresql://localhost:5432/chapter04_dev",
    "spring.datasource.username=postgres",
    "spring.datasource.password=postgres",

    // 關鍵：只驗證、不修改
    "spring.jpa.hibernate.ddl-auto=validate",

    // 減少噪音
    "spring.jpa.open-in-view=false",
    "spring.jpa.properties.hibernate.show_sql=false",
    "spring.jpa.properties.hibernate.format_sql=true",

    // 測試只做 schema validate；migration 請在外部先跑 mvn flyway:migrate
    "spring.flyway.enabled=false"
})
public class MigrationValidationTest {
    
    @Autowired
    private EntityManagerFactory entityManagerFactory;
    
    /**
     * 驗證 Schema 與 Entities 一致性
     * 
     * 測試通過 = Flyway Migration SQL 與 JPA Entities 完全一致
     * 測試失敗 = 存在不一致，Hibernate 會輸出詳細錯誤訊息
     */
    @Test
    public void validateSchemaMatchesEntities() {
        // EntityManagerFactory 的建立過程中，
        // Hibernate 會自動驗證 schema
        assertNotNull(entityManagerFactory, 
            "EntityManagerFactory should be created successfully. " +
            "If this test fails, check Hibernate validation errors above.");
    }
}
