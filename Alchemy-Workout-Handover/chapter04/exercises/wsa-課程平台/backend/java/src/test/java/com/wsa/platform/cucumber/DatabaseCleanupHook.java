package com.wsa.platform.cucumber;

import io.cucumber.java.Before;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;

public class DatabaseCleanupHook {

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private ScenarioContext scenarioContext;

    @Before(order = 0)
    public void cleanDatabase() {
        // Clear ScenarioContext
        scenarioContext.clear();

        // Delete in correct order to respect foreign key constraints
        jdbcTemplate.execute("DELETE FROM payment_requests");
        jdbcTemplate.execute("DELETE FROM coupons");
        jdbcTemplate.execute("DELETE FROM order_items");
        jdbcTemplate.execute("DELETE FROM orders");
        jdbcTemplate.execute("DELETE FROM products");
        jdbcTemplate.execute("DELETE FROM lesson_progress");
        jdbcTemplate.execute("DELETE FROM lessons");
        jdbcTemplate.execute("DELETE FROM chapters");
        jdbcTemplate.execute("DELETE FROM roles");
        jdbcTemplate.execute("DELETE FROM journeys");
        jdbcTemplate.execute("DELETE FROM users");

        // Reset sequences
        jdbcTemplate.execute("ALTER SEQUENCE users_id_seq RESTART WITH 1");
        jdbcTemplate.execute("ALTER SEQUENCE journeys_id_seq RESTART WITH 1");
        jdbcTemplate.execute("ALTER SEQUENCE chapters_id_seq RESTART WITH 1");
        jdbcTemplate.execute("ALTER SEQUENCE lessons_id_seq RESTART WITH 1");
        jdbcTemplate.execute("ALTER SEQUENCE lesson_progress_id_seq RESTART WITH 1");
        jdbcTemplate.execute("ALTER SEQUENCE roles_id_seq RESTART WITH 1");
        jdbcTemplate.execute("ALTER SEQUENCE products_id_seq RESTART WITH 1");
        jdbcTemplate.execute("ALTER SEQUENCE orders_id_seq RESTART WITH 1");
        jdbcTemplate.execute("ALTER SEQUENCE order_items_id_seq RESTART WITH 1");
        jdbcTemplate.execute("ALTER SEQUENCE coupons_id_seq RESTART WITH 1");
        jdbcTemplate.execute("ALTER SEQUENCE payment_requests_id_seq RESTART WITH 1");
    }
}
