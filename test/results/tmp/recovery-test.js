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
    }
    
    canExecute() {
        if (this.state === 'CLOSED') return true;
        if (this.state === 'OPEN' && this.lastFailureTime) {
            if (Date.now() - this.lastFailureTime >= this.resetTimeout) {
                this.state = 'HALF_OPEN';
                return true;
            }
        }
        return false;
    }
    
    recordSuccess() {
        this.failures = 0;
        this.state = 'CLOSED';
    }
}

// Synchronous wait
function sleep(ms) {
    const end = Date.now() + ms;
    while (Date.now() < end) { /* busy wait */ }
}

const cb = new CircuitBreaker(3, 100);

// Trip the breaker
cb.recordFailure();
cb.recordFailure();
cb.recordFailure();

// Wait for recovery
sleep(150);

// Should be able to execute in half-open state
const canExecute = cb.canExecute();
cb.recordSuccess();

console.log(JSON.stringify({
    recovered: cb.state === 'CLOSED' && cb.failures === 0,
    passed: canExecute && cb.state === 'CLOSED'
}));
