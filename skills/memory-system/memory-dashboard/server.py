#!/usr/bin/env python3
"""
OpenClaw Memory Dashboard API Server
Provides REST API for memory dashboard frontend
"""

import json
import os
import subprocess
from http.server import HTTPServer, SimpleHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
from datetime import datetime
import glob

WORKSPACE_DIR = "/root/.openclaw/workspace"
MEMORY_DIR = f"{WORKSPACE_DIR}/memory"
SCENE_DIR = "/root/.openclaw/memory-tdai/scene_blocks"
DASHBOARD_DIR = f"{WORKSPACE_DIR}/memory-dashboard"

class MemoryAPIHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        
        # API endpoints
        if parsed.path.startswith('/api/memory/'):
            self.handle_api(parsed.path)
        # Serve static files
        else:
            if parsed.path == '/':
                self.path = '/memory-dashboard/index.html'
            elif parsed.path.endswith('.js'):
                self.path = f'/memory-dashboard{parsed.path}'
            elif parsed.path.endswith('.css'):
                self.path = f'/memory-dashboard{parsed.path}'
            super().do_GET()
    
    def do_POST(self):
        parsed = urlparse(self.path)
        
        if parsed.path.startswith('/api/memory/'):
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length).decode('utf-8') if content_length > 0 else '{}'
            self.handle_api_post(parsed.path, body)
        else:
            self.send_error(404)
    
    def handle_api(self, path):
        """Handle GET API requests"""
        try:
            if path == '/api/memory/list':
                data = self.get_memories()
            elif path == '/api/memory/stats':
                data = self.get_stats()
            elif path == '/api/memory/heat/ranking':
                data = self.get_heat_ranking()
            elif path == '/api/memory/recent':
                data = self.get_recent_activity()
            else:
                self.send_error(404)
                return
            
            self.send_json(data)
        except Exception as e:
            self.send_error(500, str(e))
    
    def handle_api_post(self, path, body):
        """Handle POST API requests"""
        try:
            if path == '/api/memory/heat/decay':
                result = self.run_heat_decay()
            elif path == '/api/memory/digest/weekly':
                result = self.run_weekly_digest()
            elif path == '/api/memory/backup':
                result = self.run_backup()
            else:
                self.send_error(404)
                return
            
            self.send_json(result)
        except Exception as e:
            self.send_error(500, str(e))
    
    def get_memories(self):
        """Get all memory files with metadata"""
        memories = []
        
        # Scan scene blocks
        if os.path.exists(SCENE_DIR):
            for file in glob.glob(f"{SCENE_DIR}/*.md"):
                metadata = self.parse_memory_file(file)
                if metadata:
                    memories.append(metadata)
        
        # Scan memory directory
        if os.path.exists(MEMORY_DIR):
            for file in glob.glob(f"{MEMORY_DIR}/**/*.md", recursive=True):
                if "MEMORY_SYSTEM_STATUS" not in file and "MEMORY_RECALL" not in file:
                    metadata = self.parse_memory_file(file)
                    if metadata:
                        memories.append(metadata)
        
        return {"memories": memories, "total": len(memories)}
    
    def parse_memory_file(self, filepath):
        """Parse memory file and extract metadata"""
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Extract frontmatter
            metadata = {
                "file": os.path.basename(filepath),
                "path": filepath,
                "type": "unknown",
                "heat": 1,
                "created": "",
                "updated": "",
                "summary": ""
            }
            
            # Parse META frontmatter
            if "-----META-START-----" in content:
                start = content.find("-----META-START-----")
                end = content.find("-----META-END-----")
                if end > start:
                    meta_content = content[start:end]
                    for line in meta_content.split('\n'):
                        if ':' in line:
                            key, value = line.split(':', 1)
                            key = key.strip()
                            value = value.strip()
                            if key in metadata:
                                metadata[key] = value
                            elif key == 'type':
                                metadata['type'] = value
                            elif key == 'heat':
                                metadata['heat'] = int(value) if value.isdigit() else 1
            
            # Extract summary from first paragraph if not in meta
            if not metadata['summary']:
                lines = content.split('\n')
                for line in lines[5:15]:  # Skip frontmatter
                    if line.strip() and not line.startswith('#'):
                        metadata['summary'] = line[:100]
                        break
            
            # Get file stats if dates not in meta
            if not metadata['updated']:
                stat = os.stat(filepath)
                metadata['updated'] = datetime.fromtimestamp(stat.st_mtime).isoformat()
                metadata['created'] = datetime.fromtimestamp(stat.st_ctime).isoformat()
            
            return metadata
        except Exception as e:
            print(f"Error parsing {filepath}: {e}")
            return None
    
    def get_stats(self):
        """Get memory statistics"""
        memories = self.get_memories()["memories"]
        
        total = len(memories)
        total_heat = sum(m.get('heat', 1) for m in memories)
        avg_heat = round(total_heat / total, 2) if total > 0 else 0
        
        latest_update = max((m.get('updated', '') for m in memories), default='')
        
        return {
            "total": total,
            "total_heat": total_heat,
            "avg_heat": avg_heat,
            "latest_update": latest_update
        }
    
    def get_heat_ranking(self, limit=10):
        """Get heat score ranking"""
        memories = self.get_memories()["memories"]
        sorted_memories = sorted(memories, key=lambda x: x.get('heat', 0), reverse=True)[:limit]
        return {"ranking": sorted_memories}
    
    def get_recent_activity(self, limit=10):
        """Get recent activity"""
        memories = self.get_memories()["memories"]
        sorted_memories = sorted(
            memories, 
            key=lambda x: x.get('updated', ''), 
            reverse=True
        )[:limit]
        return {"activities": sorted_memories}
    
    def run_heat_decay(self):
        """Run heat decay script"""
        script = f"{WORKSPACE_DIR}/scripts/manage-heat.sh"
        if os.path.exists(script):
            result = subprocess.run(
                ["bash", script, "auto"],
                capture_output=True,
                text=True,
                timeout=30
            )
            return {
                "success": result.returncode == 0,
                "output": result.stdout,
                "error": result.stderr
            }
        return {"success": False, "error": "Script not found"}
    
    def run_weekly_digest(self):
        """Run weekly digest script"""
        script = f"{WORKSPACE_DIR}/scripts/memory-notify.sh"
        if os.path.exists(script):
            result = subprocess.run(
                ["bash", script, "weekly"],
                capture_output=True,
                text=True,
                timeout=30
            )
            return {
                "success": result.returncode == 0,
                "output": result.stdout,
                "error": result.stderr
            }
        return {"success": False, "error": "Script not found"}
    
    def run_backup(self):
        """Run backup script"""
        script = f"{WORKSPACE_DIR}/scripts/memory-backup.sh"
        if os.path.exists(script):
            result = subprocess.run(
                ["bash", script, "full"],
                capture_output=True,
                text=True,
                timeout=120
            )
            return {
                "success": result.returncode == 0,
                "output": result.stdout,
                "error": result.stderr
            }
        return {"success": False, "error": "Script not found"}
    
    def send_json(self, data, status=200):
        """Send JSON response"""
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode('utf-8'))
    
    def send_error(self, code, message=""):
        """Send error response"""
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"error": message}).encode('utf-8'))
    
    def log_message(self, format, *args):
        """Override to log to stdout"""
        print(f"[{datetime.now().isoformat()}] {args[0]}")

def main():
    port = 8080
    server = HTTPServer(('0.0.0.0', port), MemoryAPIHandler)
    print(f"🚀 OpenClaw Memory Dashboard API Server")
    print(f"📍 Running on http://localhost:{port}")
    print(f"📁 Dashboard: {DASHBOARD_DIR}")
    print(f"📁 Memory: {MEMORY_DIR}")
    print(f"📁 Scenes: {SCENE_DIR}")
    print(f"\nPress Ctrl+C to stop")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n👋 Shutting down...")
        server.shutdown()

if __name__ == '__main__':
    main()
