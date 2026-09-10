package com.wsa.platform.cucumber;

import io.cucumber.spring.CucumberContextConfiguration;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.ActiveProfiles;

/**
 * Cucumber Spring Configuration - equivalent to Python's environment.py
 *
 * This class:
 * - Configures Spring Boot Test context
 * - Uses Testcontainers JDBC URL for automatic PostgreSQL container management
 * - Manages test lifecycle (before/after scenario)
 *
 * Note: PostgreSQL container is automatically started via the jdbc:tc: URL
 * configured in application-test.yml
 */
@CucumberContextConfiguration
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("test")
public class CucumberSpringConfiguration {

    @LocalServerPort
    private int port;

    public int getPort() {
        return port;
    }

    public String getBaseUrl() {
        return "http://localhost:" + port;
    }
}
