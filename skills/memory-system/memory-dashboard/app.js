// OpenClaw Memory Dashboard - Frontend Application

const API_BASE = '/api/memory';
let memories = [];
let darkMode = false;

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    initTheme();
    loadData();
    setupEventListeners();
    // Auto-refresh every 60 seconds
    setInterval(loadData, 60000);
});

// Theme Management
function initTheme() {
    darkMode = localStorage.getItem('darkMode') === 'true';
    applyTheme();
}

function toggleTheme() {
    darkMode = !darkMode;
    localStorage.setItem('darkMode', darkMode);
    applyTheme();
}

function applyTheme() {
    if (darkMode) {
        document.documentElement.classList.add('dark');
    } else {
        document.documentElement.classList.remove('dark');
    }
}

// Event Listeners
function setupEventListeners() {
    document.getElementById('themeToggle').addEventListener('click', toggleTheme);
    document.getElementById('refreshBtn').addEventListener('click', loadData);
    document.getElementById('searchInput').addEventListener('input', filterMemories);
    document.getElementById('typeFilter').addEventListener('change', filterMemories);
}

// Load Data
async function loadData() {
    try {
        // In production, this would fetch from API
        // For now, load from local files via bash script
        const response = await fetch('/api/memory/list');
        if (response.ok) {
            memories = await response.json();
        } else {
            // Fallback: simulate data
            memories = await loadMemoriesLocal();
        }
        renderMemories();
        renderStats();
        renderHeatRanking();
        renderRecentActivity();
    } catch (error) {
        console.error('Failed to load data:', error);
        // Load sample data
        memories = getSampleMemories();
        renderMemories();
        renderStats();
        renderHeatRanking();
    }
}

// Load memories from local bash script
async function loadMemoriesLocal() {
    // This would call the bash script via API
    // For demo, return sample data
    return getSampleMemories();
}

// Sample Data
function getSampleMemories() {
    return [
        {
            file: '数字资产 - 微信服务号.md',
            type: 'reference',
            heat: 10,
            created: '2026-03-29T05:59:19.592Z',
            updated: '2026-04-02T13:40:34.476Z',
            summary: '微信服务号自动化系统每 6 小时发布英文 AI 新闻简报，图像生成模型为 Kimi 2.5'
        },
        {
            file: '工作偏好 - 新闻简报.md',
            type: 'user',
            heat: 5,
            created: '2026-03-29T05:47:27.905Z',
            updated: '2026-04-02T12:01:07.749Z',
            summary: '用户新闻简报采用全英文格式服务于微信服务号自动化系统，每 6 小时发布一次'
        },
        {
            file: 'CinaToken-API 网关.md',
            type: 'project',
            heat: 8,
            created: '2026-04-02T12:57:00.000Z',
            updated: '2026-04-02T13:39:00.000Z',
            summary: 'CinaToken 大模型 API 服务上线，支持 6 个语言版本首页国际化部署'
        },
        {
            file: '发布失败事件复盘.md',
            type: 'feedback',
            heat: 3,
            created: '2026-03-30T08:29:00.000Z',
            updated: '2026-03-30T10:00:00.000Z',
            summary: '2026-03-30 早 6 点新闻早报未按时发送，根因为 SSH 密钥权限问题'
        }
    ];
}

// Render Stats
function renderStats() {
    const total = memories.length;
    const totalHeat = memories.reduce((sum, m) => sum + m.heat, 0);
    const avgHeat = total > 0 ? (totalHeat / total).toFixed(1) : 0;
    const lastUpdate = memories.length > 0 
        ? new Date(Math.max(...memories.map(m => new Date(m.updated)))).toLocaleString('zh-CN')
        : '-';

    document.getElementById('totalMemories').textContent = total;
    document.getElementById('totalHeat').textContent = totalHeat;
    document.getElementById('avgHeat').textContent = avgHeat;
    document.getElementById('lastUpdate').textContent = lastUpdate;
}

// Render Memory List
function renderMemories(filteredMemories = null) {
    const list = document.getElementById('memoryList');
    const data = filteredMemories || memories;

    if (data.length === 0) {
        list.innerHTML = `
            <div class="text-center py-12">
                <svg class="w-16 h-16 text-gray-300 dark:text-gray-600 mx-auto" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"/>
                </svg>
                <p class="text-gray-500 dark:text-gray-400 mt-4">没有找到匹配的记忆</p>
            </div>
        `;
        return;
    }

    list.innerHTML = data.map(memory => `
        <div class="memory-card bg-gray-50 dark:bg-gray-700/50 rounded-xl p-5 cursor-pointer border border-gray-200 dark:border-gray-600"
             onclick="showMemoryDetail('${memory.file}')">
            <div class="flex items-start justify-between mb-3">
                <div class="flex items-center space-x-2">
                    <span class="type-badge type-${memory.type}">${getTypeLabel(memory.type)}</span>
                    <span class="text-xs text-gray-500 dark:text-gray-400">${formatDate(memory.updated)}</span>
                </div>
                <div class="flex items-center space-x-1">
                    <svg class="w-4 h-4 text-orange-500" fill="currentColor" viewBox="0 0 20 20">
                        <path fill-rule="evenodd" d="M12.395 2.553a1 1 0 00-1.45-.385c-.345.23-.614.581-.801.964-.75 1.534-.692 2.93-.252 4.195.14.403.305.802.493 1.187-.405.07-.82.117-1.244.135-1.65.07-3.185.583-4.425 1.464a1 1 0 00-.243 1.392l1.992 2.656a1 1 0 001.45.15c.88-.66 1.873-1.155 2.947-1.445.403-.108.817-.195 1.24-.258.07.405.158.802.265 1.187.43 1.55 1.436 2.86 2.815 3.64a1 1 0 001.392-.243l2.656-1.992a1 1 0 00.15-1.45c-.66-.88-1.155-1.873-1.445-2.947a10.903 10.903 0 01-.258-1.24c.405-.07.802-.158 1.187-.265 1.55-.43 2.86-1.436 3.64-2.815a1 1 0 00-.243-1.392l-2.656-1.992a1 1 0 00-1.45-.15c-.88.66-1.873 1.155-2.947 1.445-.403.108-.817.195-1.24.258a10.905 10.905 0 01-.265-1.187c-.43-1.55-1.436-2.86-2.815-3.64z" clip-rule="evenodd"/>
                    </svg>
                    <span class="font-semibold text-orange-600 dark:text-orange-400">${memory.heat}</span>
                </div>
            </div>
            <h3 class="font-semibold text-gray-900 dark:text-white mb-2 truncate">${memory.file.replace('.md', '')}</h3>
            <p class="text-sm text-gray-600 dark:text-gray-300 line-clamp-2">${memory.summary}</p>
        </div>
    `).join('');
}

// Render Heat Ranking
function renderHeatRanking() {
    const ranking = document.getElementById('heatRanking');
    const sorted = [...memories].sort((a, b) => b.heat - a.heat).slice(0, 5);

    ranking.innerHTML = sorted.map((memory, index) => `
        <div class="flex items-center justify-between py-2 border-b border-gray-100 dark:border-gray-700 last:border-0">
            <div class="flex items-center space-x-3">
                <span class="w-6 h-6 rounded-full flex items-center justify-center text-sm font-bold
                    ${index === 0 ? 'bg-yellow-100 text-yellow-700' : 
                      index === 1 ? 'bg-gray-100 text-gray-700' : 
                      index === 2 ? 'bg-orange-100 text-orange-700' : 
                      'bg-gray-50 text-gray-500'}">
                    ${index + 1}
                </span>
                <span class="text-sm text-gray-700 dark:text-gray-300 truncate max-w-[150px]">
                    ${memory.file.replace('.md', '')}
                </span>
            </div>
            <span class="font-semibold text-orange-600 dark:text-orange-400">🔥 ${memory.heat}</span>
        </div>
    `).join('');
}

// Render Recent Activity
function renderRecentActivity() {
    const activity = document.getElementById('recentActivity');
    const sorted = [...memories].sort((a, b) => new Date(b.updated) - new Date(a.updated)).slice(0, 5);

    activity.innerHTML = sorted.map(memory => `
        <div class="flex items-start space-x-3">
            <div class="w-2 h-2 rounded-full bg-primary mt-2"></div>
            <div class="flex-1 min-w-0">
                <p class="text-sm text-gray-700 dark:text-gray-300 truncate">${memory.file.replace('.md', '')}</p>
                <p class="text-xs text-gray-500 dark:text-gray-400">${getActivityType(memory.type)} · ${formatDate(memory.updated)}</p>
            </div>
        </div>
    `).join('');
}

// Filter Memories
function filterMemories() {
    const search = document.getElementById('searchInput').value.toLowerCase();
    const type = document.getElementById('typeFilter').value;

    let filtered = memories;

    if (type !== 'all') {
        filtered = filtered.filter(m => m.type === type);
    }

    if (search) {
        filtered = filtered.filter(m => 
            m.file.toLowerCase().includes(search) || 
            m.summary.toLowerCase().includes(search)
        );
    }

    renderMemories(filtered);
}

// Show Memory Detail
function showMemoryDetail(filename) {
    const memory = memories.find(m => m.file === filename);
    if (!memory) return;

    document.getElementById('modalTitle').textContent = filename.replace('.md', '');
    document.getElementById('modalContent').innerHTML = `
        <div class="space-y-4">
            <div class="flex items-center space-x-3">
                <span class="type-badge type-${memory.type}">${getTypeLabel(memory.type)}</span>
                <span class="text-sm text-gray-500 dark:text-gray-400">
                    🔥 热度：${memory.heat}
                </span>
            </div>
            <div class="grid grid-cols-2 gap-4">
                <div>
                    <p class="text-xs text-gray-500 dark:text-gray-400">创建时间</p>
                    <p class="text-sm font-medium">${new Date(memory.created).toLocaleString('zh-CN')}</p>
                </div>
                <div>
                    <p class="text-xs text-gray-500 dark:text-gray-400">更新时间</p>
                    <p class="text-sm font-medium">${new Date(memory.updated).toLocaleString('zh-CN')}</p>
                </div>
            </div>
            <div>
                <p class="text-xs text-gray-500 dark:text-gray-400 mb-2">摘要</p>
                <p class="text-sm text-gray-700 dark:text-gray-300">${memory.summary}</p>
            </div>
            <div class="pt-4 border-t border-gray-200 dark:border-gray-700">
                <button class="px-4 py-2 bg-primary text-white rounded-lg hover:bg-blue-700 text-sm"
                        onclick="viewFullContent('${memory.file}')">
                    查看完整内容
                </button>
            </div>
        </div>
    `;

    document.getElementById('memoryModal').classList.remove('hidden');
}

function closeModal() {
    document.getElementById('memoryModal').classList.add('hidden');
}

function viewFullContent(filename) {
    // In production, this would fetch and display full content
    alert('查看完整内容功能需要后端 API 支持');
}

// Quick Actions
async function runHeatDecay() {
    if (confirm('确定要应用热度衰减吗？这将减少所有老旧记忆的热度评分。')) {
        try {
            const response = await fetch('/api/memory/heat/decay', { method: 'POST' });
            if (response.ok) {
                alert('热度衰减已应用');
                loadData();
            } else {
                alert('操作失败，请检查后端服务');
            }
        } catch (error) {
            alert('操作失败：' + error.message);
        }
    }
}

async function runWeeklyDigest() {
    if (confirm('确定要生成周度记忆摘要吗？')) {
        try {
            const response = await fetch('/api/memory/digest/weekly', { method: 'POST' });
            if (response.ok) {
                const result = await response.json();
                alert('周度摘要已生成：\n' + JSON.stringify(result, null, 2));
            } else {
                alert('操作失败，请检查后端服务');
            }
        } catch (error) {
            alert('操作失败：' + error.message);
        }
    }
}

async function exportMemories() {
    const data = {
        exported: new Date().toISOString(),
        total: memories.length,
        memories: memories
    };
    
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `memories-export-${new Date().toISOString().split('T')[0]}.json`;
    a.click();
    URL.revokeObjectURL(url);
}

// Utilities
function getTypeLabel(type) {
    const labels = {
        user: '👤 用户画像',
        feedback: '📋 反馈规则',
        project: '📁 项目动态',
        reference: '🔗 外部引用',
        session: '💬 会话状态'
    };
    return labels[type] || type;
}

function getActivityType(type) {
    const actions = {
        user: '用户偏好更新',
        feedback: '规则变更',
        project: '项目进展',
        reference: '引用更新',
        session: '会话记录'
    };
    return actions[type] || '更新';
}

function formatDate(dateString) {
    const date = new Date(dateString);
    const now = new Date();
    const diff = now - date;
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));

    if (days === 0) return '今天';
    if (days === 1) return '昨天';
    if (days < 7) return `${days}天前`;
    return date.toLocaleDateString('zh-CN');
}

// CSS for type badges
const style = document.createElement('style');
style.textContent = `
    .type-badge {
        display: inline-block;
        padding: 0.25rem 0.5rem;
        border-radius: 0.375rem;
        font-size: 0.75rem;
        font-weight: 500;
    }
    .type-user { background-color: #dbeafe; color: #1e40af; }
    .type-feedback { background-color: #fee2e2; color: #991b1b; }
    .type-project { background-color: #d1fae5; color: #065f46; }
    .type-reference { background-color: #e0e7ff; color: #3730a3; }
    .type-session { background-color: #fef3c7; color: #92400e; }
    
    .dark .type-user { background-color: #1e40af; color: #dbeafe; }
    .dark .type-feedback { background-color: #991b1b; color: #fee2e2; }
    .dark .type-project { background-color: #065f46; color: #d1fae5; }
    .dark .type-reference { background-color: #3730a3; color: #e0e7ff; }
    .dark .type-session { background-color: #92400e; color: #fef3c7; }
    
    .line-clamp-2 {
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
    }
`;
document.head.appendChild(style);
