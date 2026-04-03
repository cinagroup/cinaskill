/**
 * recall-engine.js - Memory Recall Engine for OpenClaw
 * 
 * Implements Phase 3 of the OpenClaw Memory System:
 * 1) scanMemoryFiles - Scan memory directory for .md files
 * 2) formatMemoryManifest - Format memory headers into manifest string
 * 3) selectRelevantMemories - AI-driven selection algorithm
 * 4) Tool-aware filtering logic
 * 5) Staleness warnings
 * 
 * @module recall-engine
 */

const fs = require('fs').promises;
const path = require('path');

// ============================================================================
// Configuration Constants (from SKILL.md)
// ============================================================================

const CONFIG = {
    MAX_MEMORY_FILES: 200,
    FRONTMATTER_MAX_LINES: 30,
    MAX_RECALLED_FILES: 5,
    MAX_ENTRYPOINT_LINES: 200,
    MAX_ENTRYPOINT_BYTES: 25000,
};

// ============================================================================
// Type Definitions (JSDoc)
// ============================================================================

/**
 * @typedef {Object} MemoryHeader
 * @property {string} filename - Relative path from memory dir
 * @property {string} filePath - Absolute path
 * @property {number} mtimeMs - Last modification timestamp
 * @property {string} description - From frontmatter
 * @property {string} type - Memory type (user|feedback|project|reference)
 */

/**
 * @typedef {Object} RelevantMemory
 * @property {string} path - Absolute file path
 * @property {number} mtimeMs - Modification time
 * @property {string} content - File content (optional)
 * @property {string} stalenessWarning - Warning if file is old (optional)
 */

// ============================================================================
// Storage Layer Functions
// ============================================================================

/**
 * Scan memory directory for .md files and extract frontmatter metadata
 * 
 * @param {string} memoryDir - Path to memory directory
 * @returns {Promise<MemoryHeader[]>} Array of memory headers
 */
async function scanMemoryFiles(memoryDir) {
    const headers = [];
    
    try {
        // Check if directory exists
        const stat = await fs.stat(memoryDir);
        if (!stat.isDirectory()) {
            return [];
        }
    } catch (err) {
        // Directory doesn't exist
        return [];
    }
    
    // Recursively find all .md files
    const files = await findMarkdownFiles(memoryDir);
    
    // Process each file
    for (const file of files) {
        if (headers.length >= CONFIG.MAX_MEMORY_FILES) {
            break;
        }
        
        const filename = path.basename(file);
        
        // Skip MEMORY.md
        if (filename === 'MEMORY.md') {
            continue;
        }
        
        try {
            // Get file stats
            const stats = await fs.stat(file);
            const mtimeMs = stats.mtimeMs;
            
            // Read first 30 lines for frontmatter
            const content = await readFirstLines(file, CONFIG.FRONTMATTER_MAX_LINES);
            
            // Parse frontmatter
            const frontmatter = parseFrontmatter(content);
            
            // Get relative path
            const relPath = path.relative(memoryDir, file);
            
            headers.push({
                filename: relPath,
                filePath: file,
                mtimeMs: mtimeMs,
                description: frontmatter.description || '',
                type: frontmatter.type || 'project',
            });
        } catch (err) {
            // Skip files that can't be read
            console.error(`Warning: Could not read ${file}:`, err.message);
        }
    }
    
    // Sort by mtime (newest first)
    headers.sort((a, b) => b.mtimeMs - a.mtimeMs);
    
    return headers;
}

/**
 * Recursively find all markdown files in a directory
 * 
 * @param {string} dir - Directory to search
 * @returns {Promise<string[]>} Array of file paths
 */
async function findMarkdownFiles(dir) {
    const results = [];
    
    try {
        const entries = await fs.readdir(dir, { withFileTypes: true });
        
        for (const entry of entries) {
            const fullPath = path.join(dir, entry.name);
            
            if (entry.isDirectory()) {
                const subDirFiles = await findMarkdownFiles(fullPath);
                results.push(...subDirFiles);
            } else if (entry.isFile() && entry.name.endsWith('.md')) {
                results.push(fullPath);
            }
        }
    } catch (err) {
        // Ignore permission errors
    }
    
    return results;
}

/**
 * Read first N lines of a file
 * 
 * @param {string} filePath - Path to file
 * @param {number} maxLines - Maximum lines to read
 * @returns {Promise<string>} Content string
 */
async function readFirstLines(filePath, maxLines) {
    const content = await fs.readFile(filePath, 'utf-8');
    const lines = content.split('\n');
    return lines.slice(0, maxLines).join('\n');
}

/**
 * Parse YAML frontmatter from content
 * 
 * @param {string} content - File content
 * @returns {Object} Parsed frontmatter object
 */
function parseFrontmatter(content) {
    const frontmatter = {};
    
    // Check for YAML frontmatter (--- delimiters)
    const match = content.match(/^---\n([\s\S]*?)\n---/);
    if (!match) {
        return frontmatter;
    }
    
    const yamlContent = match[1];
    const lines = yamlContent.split('\n');
    
    for (const line of lines) {
        const kvMatch = line.match(/^(\w+):\s*(.*)$/);
        if (kvMatch) {
            const key = kvMatch[1].trim();
            let value = kvMatch[2].trim();
            
            // Remove quotes if present
            if ((value.startsWith('"') && value.endsWith('"')) ||
                (value.startsWith("'") && value.endsWith("'"))) {
                value = value.slice(1, -1);
            }
            
            frontmatter[key] = value;
        }
    }
    
    return frontmatter;
}

// ============================================================================
// Index Layer Functions
// ============================================================================

/**
 * Format memory headers into a human-readable manifest string
 * 
 * @param {MemoryHeader[]} headers - Array of memory headers
 * @returns {string} Formatted manifest string
 */
function formatMemoryManifest(headers) {
    if (!headers || headers.length === 0) {
        return '(No memory files found)';
    }
    
    return headers.map(h => {
        const date = new Date(h.mtimeMs).toISOString().split('T')[0];
        return `- [${h.type}] ${h.filename} (${date}): ${h.description}`;
    }).join('\n');
}

/**
 * Generate staleness warning for a memory file
 * 
 * @param {number} mtimeMs - Modification time in milliseconds
 * @returns {string} Warning string (empty if fresh)
 */
function memoryFreshnessText(mtimeMs) {
    const now = Date.now();
    const ageDays = Math.floor((now - mtimeMs) / 86400000);
    
    if (ageDays <= 1) {
        return '';
    }
    
    return `⚠️ This memory is ${ageDays} days old. Code references (line numbers, function names) may have drifted. Always verify against the current codebase before acting on this information.`;
}

// ============================================================================
// Recall Engine Functions
// ============================================================================

/**
 * Select relevant memories using AI-driven selection
 * 
 * @param {string} query - User's current query
 * @param {string} manifest - Formatted memory manifest
 * @param {string[]} [recentTools] - Recently used tools
 * @param {Set<string>} [alreadySurfaced] - Already shown file paths
 * @param {AbortSignal} [signal] - Abort signal
 * @returns {Promise<string[]>} Array of selected filenames
 */
async function selectRelevantMemories(query, manifest, recentTools = [], alreadySurfaced = new Set(), signal = null) {
    // Build system prompt
    const systemPrompt = buildSelectMemoriesSystemPrompt(recentTools, alreadySurfaced);
    
    // Build user prompt
    const userPrompt = `Current Query: ${query}

Available Memory Files:
${manifest}

Select the most relevant memories for this query.`;
    
    try {
        // Call LLM for selection
        const response = await callLLMForSelection(systemPrompt, userPrompt, signal);
        
        // Parse response
        const parsed = parseSelectionResponse(response);
        
        return parsed;
    } catch (err) {
        console.error('Error in selectRelevantMemories:', err.message);
        
        // Fallback to keyword-based selection
        return keywordBasedSelection(query, manifest);
    }
}

/**
 * Build the system prompt for memory selection
 * 
 * @param {string[]} recentTools - Recently used tools
 * @param {Set<string>} alreadySurfaced - Already shown files
 * @returns {string} System prompt
 */
function buildSelectMemoriesSystemPrompt(recentTools, alreadySurfaced) {
    let prompt = `You are a memory recall assistant. Given a user's current query and a list of available memory files,
select the most relevant memories that would help answer the query.

Rules:
- Return at most 5 filenames.
- If you are unsure whether a memory is relevant, do NOT include it.
- Do NOT select memories that are API usage references for tools currently being used
  (the conversation already has that context).
- DO select memories about known issues, gotchas, or corrections for those tools.
- Prefer newer memories over older ones when relevance is similar.

Output format: JSON object with key "selected_memories" containing an array of filenames.

Example output: {"selected_memories": ["api-patterns.md", "user-preferences.md"]}`;
    
    // Add tool-aware filtering context
    if (recentTools && recentTools.length > 0) {
        prompt += `\n\nRecent tools in use: ${recentTools.join(', ')}
- Suppress: API docs/usage guides for these tools (already in context)
- Prioritize: Known issues, gotchas, workarounds for these tools`;
    }
    
    // Add already surfaced files context
    if (alreadySurfaced && alreadySurfaced.size > 0) {
        prompt += `\n\nAlready shown in this conversation: ${Array.from(alreadySurfaced).join(', ')}
- Avoid re-selecting these files unless highly relevant`;
    }
    
    return prompt;
}

/**
 * Call LLM for memory selection
 * 
 * @param {string} systemPrompt - System prompt
 * @param {string} userPrompt - User prompt
 * @param {AbortSignal} [signal] - Abort signal
 * @returns {Promise<string>} LLM response
 */
async function callLLMForSelection(systemPrompt, userPrompt, signal = null) {
    // This is a placeholder - in production, this would call the actual LLM API
    // For OpenClaw, this would use the side-query mechanism
    
    // Check if we're in an OpenClaw environment
    if (typeof global.openclaw !== 'undefined' && global.openclaw.sideQuery) {
        const response = await global.openclaw.sideQuery({
            system: systemPrompt,
            user: userPrompt,
            signal: signal,
        });
        return response;
    }
    
    // Fallback: return empty selection
    // In production, this would call an actual LLM API
    throw new Error('LLM not available - using fallback selection');
}

/**
 * Parse LLM selection response
 * 
 * @param {string} response - LLM response
 * @returns {string[]} Array of selected filenames
 */
function parseSelectionResponse(response) {
    try {
        // Try to parse as JSON
        const parsed = JSON.parse(response);
        if (parsed.selected_memories && Array.isArray(parsed.selected_memories)) {
            return parsed.selected_memories.slice(0, CONFIG.MAX_RECALLED_FILES);
        }
    } catch (err) {
        // Try to extract filenames from text
        const matches = response.match(/[\w-]+\.md/g);
        if (matches) {
            return matches.slice(0, CONFIG.MAX_RECALLED_FILES);
        }
    }
    
    return [];
}

/**
 * Fallback selection using keyword matching
 * 
 * @param {string} query - User query
 * @param {string} manifest - Memory manifest
 * @returns {string[]} Selected filenames
 */
function keywordBasedSelection(query, manifest) {
    // Extract keywords from query
    const keywords = query
        .toLowerCase()
        .match(/\b[a-z]{3,}\b/g) || [];
    
    const uniqueKeywords = [...new Set(keywords)].slice(0, 10);
    
    // Score each memory file
    const scores = [];
    const lines = manifest.split('\n');
    
    for (const line of lines) {
        if (!line.match(/^\-.*\.md/)) {
            continue;
        }
        
        const filenameMatch = line.match(/\] ([^ ]+) \(/);
        if (!filenameMatch) {
            continue;
        }
        
        const filename = filenameMatch[1];
        const score = uniqueKeywords.reduce((acc, keyword) => {
            return acc + (line.toLowerCase().includes(keyword) ? 1 : 0);
        }, 0);
        
        if (score > 0) {
            scores.push({ filename, score });
        }
    }
    
    // Sort by score and return top 5
    scores.sort((a, b) => b.score - a.score);
    
    return scores.slice(0, CONFIG.MAX_RECALLED_FILES).map(s => s.filename);
}

/**
 * Apply tool-aware filtering to memory headers
 * 
 * @param {MemoryHeader[]} headers - Memory headers
 * @param {string[]} recentTools - Recently used tools
 * @returns {MemoryHeader[]} Filtered headers
 */
function filterByTools(headers, recentTools) {
    if (!recentTools || recentTools.length === 0) {
        return headers;
    }
    
    // Filter logic:
    // - Suppress API reference files for active tools
    // - Prioritize known issues/gotchas for active tools
    
    return headers.filter(header => {
        const desc = header.description.toLowerCase();
        const filename = header.filename.toLowerCase();
        
        // Check if this is an API reference for an active tool
        for (const tool of recentTools) {
            const toolName = tool.split('__').pop().toLowerCase();
            
            // If it's a pure API reference, suppress it
            if ((desc.includes('api') || desc.includes('usage') || desc.includes('reference')) &&
                (filename.includes(toolName) || desc.includes(toolName))) {
                return false;
            }
        }
        
        return true;
    });
}

/**
 * Main recall engine - orchestrates the full pipeline
 * 
 * @param {Object} options - Options object
 * @param {string} options.query - User's query
 * @param {string} options.memoryDir - Path to memory directory
 * @param {string[]} [options.recentTools] - Recently used tools
 * @param {Set<string>} [options.alreadySurfaced] - Already shown file paths
 * @param {AbortSignal} [options.signal] - Abort signal
 * @returns {Promise<RelevantMemory[]>} Array of relevant memories
 */
async function findRelevantMemories({
    query,
    memoryDir,
    recentTools = [],
    alreadySurfaced = new Set(),
    signal = null,
}) {
    // Step 1: Scan memory files
    const headers = await scanMemoryFiles(memoryDir);
    
    if (headers.length === 0) {
        return [];
    }
    
    // Step 2: Deduplicate (skip already shown)
    const filtered = headers.filter(h => !alreadySurfaced.has(h.filePath));
    
    if (filtered.length === 0) {
        return [];
    }
    
    // Step 3: Apply tool-aware filtering
    const toolFiltered = filterByTools(filtered, recentTools);
    
    // Step 4: Build manifest
    const manifest = formatMemoryManifest(toolFiltered);
    
    // Step 5: AI selection
    const selectedFilenames = await selectRelevantMemories(
        query,
        manifest,
        recentTools,
        alreadySurfaced,
        signal
    );
    
    // Step 6: Map back to full paths with content and warnings
    const results = [];
    
    for (const filename of selectedFilenames) {
        const header = toolFiltered.find(h => h.filename === filename);
        
        if (header && header.filePath) {
            try {
                const content = await fs.readFile(header.filePath, 'utf-8');
                const stalenessWarning = memoryFreshnessText(header.mtimeMs);
                
                results.push({
                    path: header.filePath,
                    mtimeMs: header.mtimeMs,
                    content: content,
                    stalenessWarning: stalenessWarning || undefined,
                });
            } catch (err) {
                console.error(`Warning: Could not read ${header.filePath}:`, err.message);
            }
        }
    }
    
    return results;
}

// ============================================================================
// Exports
// ============================================================================

module.exports = {
    // Core functions
    scanMemoryFiles,
    formatMemoryManifest,
    selectRelevantMemories,
    findRelevantMemories,
    
    // Utility functions
    memoryFreshnessText,
    filterByTools,
    parseFrontmatter,
    keywordBasedSelection,
    
    // Configuration
    CONFIG,
};
