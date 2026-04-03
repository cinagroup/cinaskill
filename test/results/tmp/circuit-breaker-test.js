const { Atomics } = require('node:util');

class CircuitBreaker {
    constructor(maxFailures = 3, resetTimeout = 100) {
        this.maxFailures = maxFailures;
        this.resetTimeout = resetTimeout;
        this.failures = 0;
        this.lastFailureTime = null;
        this.state = 'CLOSED';
    }
    
    recordFailure() {
        this.failures++;
        this.lastFailureTime = Date.now();
        if (this.failures >= this.maxFailures) {
            this.state = 'OPEN';
        }
        return this.state;
    }
    
    recordSuccess() {
        this.failures = 0;
        this.state = 'CLOSED';
    }
    
    canExecute() {
        if (this.state === 'CLOSED') return true;
        if (this.state === 'OPEN' && this.lastFailureTime) {
            const elapsed = Date.now() - this.lastFailureTime;
            if (elapsed >= this.resetTimeout) {
                this.state = 'HALF_OPEN';
                return true;
            }
        }
        return false;
    }
}

// Synchronous wait function
function sleep(ms) {
    const end = Date.now() + ms;
    while (Date.now() < end) { /* busy wait */ }
}

// Test scenario
const cb = new CircuitBreaker(3, 100);

// Record 3 failures - should open
cb.recordFailure();
cb.recordFailure();
cb.recordFailure();
const afterFailures = cb.state;

// Wait for reset timeout
sleep(150);

const canExecute = cb.canExecute();
const halfOpen = cb.state;

// Record success - should close
cb.recordSuccess();
const afterSuccess = cb.state;

console.log(JSON.stringify({
    afterFailures,
    canExecute,
    halfOpen,
    afterSuccess,
    passed: afterFailures === 'OPEN' && canExecute && halfOpen === 'HALF_OPEN' && afterSuccess === 'CLOSED'
}));
