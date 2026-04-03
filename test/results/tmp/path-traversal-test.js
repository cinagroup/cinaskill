const path = require('path');

function sanitizePathKey(key) {
    // Reject URL-encoded traversal
    if (/%2[eE]/.test(key)) throw new Error('URL-encoded traversal detected');
    
    // Unicode normalization
    const normalized = key.normalize('NFC');
    
    // Reject backslashes, absolute paths, null bytes, double dots
    if (/[\\]/.test(normalized)) throw new Error('Backslash detected');
    if (path.isAbsolute(normalized)) throw new Error('Absolute path detected');
    if (/\x00/.test(normalized)) throw new Error('Null byte detected');
    if (/\.\./.test(normalized)) throw new Error('Parent directory traversal detected');
    
    return normalized;
}

const testPaths = [
    { path: 'safe-file.md', shouldPass: true },
    { path: '../escape.md', shouldPass: false },
    { path: 'subdir/file.md', shouldPass: true },
    { path: '/absolute/path.md', shouldPass: false },
    { path: 'file%2e%2e%2fescape.md', shouldPass: false },
];

let passed = 0;
for (const test of testPaths) {
    try {
        sanitizePathKey(test.path);
        if (test.shouldPass) passed++;
    } catch (e) {
        if (!test.shouldPass) passed++;
    }
}

console.log(JSON.stringify({ passed: passed, total: testPaths.length }));
