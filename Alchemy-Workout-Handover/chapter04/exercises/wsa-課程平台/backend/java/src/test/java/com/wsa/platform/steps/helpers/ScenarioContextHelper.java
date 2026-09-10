package com.wsa.platform.steps.helpers;

import com.wsa.platform.cucumber.ScenarioContext;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

/**
 * ScenarioContextHelper - 共用的 ScenarioContext 操作方法
 */
@Component
public class ScenarioContextHelper {

    @Autowired
    private ScenarioContext scenarioContext;

    public Long getUserId(String userName) {
        Object userIdObj = scenarioContext.getId(userName);
        if (userIdObj == null) {
            throw new IllegalStateException("找不到用戶 '" + userName + "' 的 ID，請先在 Given 步驟中建立用戶");
        }
        if (userIdObj instanceof Long) {
            return (Long) userIdObj;
        }
        return Long.parseLong(userIdObj.toString());
    }

    public String getUserIdAsString(String userName) {
        return getUserId(userName).toString();
    }
}
