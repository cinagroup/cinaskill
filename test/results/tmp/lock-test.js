const fs = require('fs');
const path = require('path');

const LOCK_FILE = path.join(process.argv[2], '.consolidate-lock');

function acquireLock(memoryDir) {
    const lockPath = path.join(memoryDir, '.consolidate-lock');
    
    try {
        // Check if lock exists
        if (fs.existsSync(lockPath)) {
            const lock = JSON.parse(fs.readFileSync(lockPath, 'utf-8'));
            const age = Date.now() - lock.timestamp;
            const STALE_MS = 3600000; // 1 hour
            
            // Check if lock is stale
            if (age >= STALE_MS) {
                // Lock is stale, overwrite
            } else {
                // Lock is still valid
                return { acquired: false, reason: 'Lock held by another process' };
            }
        }
        
        // Acquire lock
        fs.writeFileSync(lockPath, JSON.stringify({
            pid: process.pid,
            timestamp: Date.now()
        }));
        
        return { acquired: true, reason: 'Lock acquired' };
    } catch (e) {
        return { acquired: false, reason: e.message };
    }
}

function releaseLock() {
    try {
        fs.unlinkSync(LOCK_FILE);
        return { released: true };
    } catch (e) {
        return { released: false, error: e.message };
    }
}

// Test
const acquireResult = acquireLock(process.argv[2]);
console.log('Acquire:', JSON.stringify(acquireResult));

// Try to acquire again (should fail)
const secondAttempt = acquireLock(process.argv[2]);
console.log('Second attempt:', JSON.stringify(secondAttempt));

// Release
const releaseResult = releaseLock();
console.log('Release:', JSON.stringify(releaseResult));

console.log(JSON.stringify({
    passed: acquireResult.acquired && !secondAttempt.acquired && releaseResult.released
}));
