const MAX_CONSECUTIVE_FAILURES = 3;
let consecutiveFailures = 0;

function autoCompactIfNeeded(simulateFailure = false) {
    if (consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
        return { executed: false, reason: 'Circuit breaker open' };
    }
    
    if (simulateFailure) {
        consecutiveFailures++;
        return { executed: false, reason: 'Simulated failure' };
    }
    
    consecutiveFailures = 0;
    return { executed: true, reason: 'Success' };
}

// Test: 3 failures should stop execution
autoCompactIfNeeded(true);
autoCompactIfNeeded(true);
autoCompactIfNeeded(true);
const result = autoCompactIfNeeded(false);

console.log(JSON.stringify({
    consecutiveFailures,
    executionBlocked: !result.executed,
    passed: consecutiveFailures === 3 && !result.executed
}));
