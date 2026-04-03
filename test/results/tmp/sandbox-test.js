const path = require('path');

const MEMORY_DIR = process.argv[2];
const testPath = process.argv[3] || '/tmp/outside-memory.txt';

function isWithinMemoryDir(filePath, memoryDir) {
    const resolved = path.resolve(filePath);
    const memDir = path.resolve(memoryDir);
    return resolved.startsWith(memDir + path.sep) || resolved === memDir;
}

// Test write permission
const canWrite = isWithinMemoryDir(testPath, MEMORY_DIR);
console.log(JSON.stringify({
    path: testPath,
    canWrite: canWrite,
    reason: canWrite ? 'Within memory directory' : 'Outside memory directory'
}));
