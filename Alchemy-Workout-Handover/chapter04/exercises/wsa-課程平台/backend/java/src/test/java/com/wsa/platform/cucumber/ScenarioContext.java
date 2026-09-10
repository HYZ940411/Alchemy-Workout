package com.wsa.platform.cucumber;

import io.cucumber.spring.ScenarioScope;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;

import java.util.HashMap;
import java.util.Map;

/**
 * ScenarioContext - equivalent to Python's context object
 *
 * This class stores state that is shared across steps within a scenario:
 * - lastResponse: HTTP response from the last API call
 * - ids: mapping of natural keys (e.g., "Alice") to database IDs
 * - memo: temporary storage for any other state
 *
 * @ScenarioScope ensures a new instance is created for each scenario
 */
@Component
@ScenarioScope
public class ScenarioContext {

    // HTTP Response from the last API call
    private ResponseEntity<?> lastResponse;

    // Mapping of natural keys to IDs (e.g., "Alice" -> userId)
    private final Map<String, Object> ids = new HashMap<>();

    // Temporary storage for any other state
    private final Map<String, Object> memo = new HashMap<>();

    // JWT token for the current user
    private String jwtToken;

    // Query result (for Query operations)
    private Object queryResult;

    // Last error message
    private String lastError;

    // Getters and Setters

    public ResponseEntity<?> getLastResponse() {
        return lastResponse;
    }

    public void setLastResponse(ResponseEntity<?> lastResponse) {
        this.lastResponse = lastResponse;
    }

    public Map<String, Object> getIds() {
        return ids;
    }

    public void putId(String key, Object value) {
        ids.put(key, value);
    }

    @SuppressWarnings("unchecked")
    public <T> T getId(String key) {
        return (T) ids.get(key);
    }

    public boolean hasId(String key) {
        return ids.containsKey(key);
    }

    public Map<String, Object> getMemo() {
        return memo;
    }

    public void putMemo(String key, Object value) {
        memo.put(key, value);
    }

    @SuppressWarnings("unchecked")
    public <T> T getMemo(String key) {
        return (T) memo.get(key);
    }

    public String getJwtToken() {
        return jwtToken;
    }

    public void setJwtToken(String jwtToken) {
        this.jwtToken = jwtToken;
    }

    public Object getQueryResult() {
        return queryResult;
    }

    public void setQueryResult(Object queryResult) {
        this.queryResult = queryResult;
    }

    public String getLastError() {
        return lastError;
    }

    public void setLastError(String lastError) {
        this.lastError = lastError;
    }

    /**
     * Clear all state - called at the start of each scenario
     */
    public void clear() {
        this.lastResponse = null;
        this.ids.clear();
        this.memo.clear();
        this.jwtToken = null;
        this.queryResult = null;
        this.lastError = null;
    }
}
