#!/bin/bash
# OpenClaw Memory Backup & Sync System
# Encrypted cloud backup for memory files
# Supports: Local, S3, GitHub, WebDAV

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="/root/.openclaw/workspace"
MEMORY_DIR="$WORKSPACE_DIR/memory"
SCENE_DIR="/root/.openclaw/memory-tdai/scene_blocks"
BACKUP_DIR="$WORKSPACE_DIR/.backups/memory"
LOG_FILE="$WORKSPACE_DIR/logs/memory-backup.log"
CONFIG_FILE="$WORKSPACE_DIR/.memory-backup-config.json"

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
success() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"; }
warn() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }

# Initialize config
init_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'EOF'
{
  "enabled": true,
  "encryption": {
    "enabled": true,
    "algorithm": "aes-256-cbc",
    "password_env": "MEMORY_BACKUP_PASSWORD"
  },
  "destinations": {
    "local": {
      "enabled": true,
      "path": "/root/.openclaw/workspace/.backups/memory"
    },
    "github": {
      "enabled": false,
      "repo": "username/memory-backup",
      "branch": "main",
      "path": "backups/"
    },
    "s3": {
      "enabled": false,
      "bucket": "my-memory-backup",
      "region": "us-east-1",
      "path": "openclaw/memory/"
    },
    "webdav": {
      "enabled": false,
      "url": "https://dav.example.com",
      "path": "/openclaw/memory"
    }
  },
  "retention": {
    "daily": 7,
    "weekly": 4,
    "monthly": 12
  },
  "schedule": {
    "auto_backup": true,
    "interval_hours": 24
  }
}
EOF
        log "Created default config: $CONFIG_FILE"
    fi
}

# Create backup directory
init_backup_dir() {
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$WORKSPACE_DIR/logs"
}

# Generate backup filename
get_backup_filename() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local checksum=$(find "$MEMORY_DIR" "$SCENE_DIR" -type f -name "*.md" 2>/dev/null | xargs cat 2>/dev/null | md5sum | cut -d' ' -f1)
    echo "memory_backup_${timestamp}_${checksum:0:8}"
}

# Encrypt file
encrypt_file() {
    local input="$1"
    local output="$2"
    local password="${!PASSWORD_ENV}"
    
    if [[ -z "$password" ]]; then
        warn "Encryption password not set, skipping encryption"
        cp "$input" "$output"
        return
    fi
    
    openssl enc -aes-256-cbc -salt -pbkdf2 -in "$input" -out "$output" -pass pass:"$password"
    log "Encrypted: $(basename "$input") → $(basename "$output")"
}

# Decrypt file
decrypt_file() {
    local input="$1"
    local output="$2"
    local password="${!PASSWORD_ENV}"
    
    if [[ -z "$password" ]]; then
        warn "Encryption password not set, skipping decryption"
        cp "$input" "$output"
        return
    fi
    
    openssl enc -aes-256-cbc -d -pbkdf2 -in "$input" -out "$output" -pass pass:"$password"
    log "Decrypted: $(basename "$input") → $(basename "$output")"
}

# Create backup archive
create_backup() {
    local backup_name=$(get_backup_filename)
    local temp_dir=$(mktemp -d)
    local archive_file="$BACKUP_DIR/${backup_name}.tar.gz"
    local encrypted_file="$BACKUP_DIR/${backup_name}.tar.gz.enc"
    
    log "Creating backup: $backup_name"
    
    # Copy memory files
    if [[ -d "$MEMORY_DIR" ]]; then
        cp -r "$MEMORY_DIR" "$temp_dir/"
        log "Copied workspace memory files"
    fi
    
    if [[ -d "$SCENE_DIR" ]]; then
        mkdir -p "$temp_dir/scene_blocks"
        cp -r "$SCENE_DIR"/* "$temp_dir/scene_blocks/" 2>/dev/null || true
        log "Copied scene blocks"
    fi
    
    if [[ -f "$WORKSPACE_DIR/MEMORY.md" ]]; then
        cp "$WORKSPACE_DIR/MEMORY.md" "$temp_dir/"
        log "Copied MEMORY.md"
    fi
    
    # Create metadata
    cat > "$temp_dir/backup_metadata.json" << EOF
{
  "created": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "source": "$WORKSPACE_DIR",
  "file_count": $(find "$temp_dir" -type f | wc -l),
  "total_size": $(du -sb "$temp_dir" | cut -f1)
}
EOF
    
    # Create tar archive
    tar -czf "$archive_file" -C "$temp_dir" .
    log "Created archive: $archive_file ($(du -h "$archive_file" | cut -f1))"
    
    # Encrypt if enabled
    local encryption_enabled=$(jq -r '.encryption.enabled' "$CONFIG_FILE" 2>/dev/null || echo "false")
    if [[ "$encryption_enabled" == "true" ]]; then
        export PASSWORD_ENV=$(jq -r '.encryption.password_env' "$CONFIG_FILE" 2>/dev/null || echo "MEMORY_BACKUP_PASSWORD")
        encrypt_file "$archive_file" "$encrypted_file"
        rm "$archive_file"
        archive_file="$encrypted_file"
    fi
    
    # Cleanup temp
    rm -rf "$temp_dir"
    
    echo "$archive_file"
    success "Backup created: $archive_file"
}

# Sync to GitHub
sync_github() {
    local backup_file="$1"
    local github_config=$(jq -r '.destinations.github' "$CONFIG_FILE" 2>/dev/null)
    local enabled=$(echo "$github_config" | jq -r '.enabled' 2>/dev/null || echo "false")
    
    if [[ "$enabled" != "true" ]]; then
        log "GitHub sync disabled, skipping"
        return 0
    fi
    
    local repo=$(echo "$github_config" | jq -r '.repo')
    local branch=$(echo "$github_config" | jq -r '.branch')
    local path=$(echo "$github_config" | jq -r '.path')
    
    log "Syncing to GitHub: $repo/$path"
    
    # Clone or pull backup repo
    local backup_repo_dir="$WORKSPACE_DIR/.backups/github-repo"
    
    if [[ -d "$backup_repo_dir/.git" ]]; then
        cd "$backup_repo_dir"
        git pull origin "$branch" 2>/dev/null || true
    else
        git clone "https://github.com/$repo.git" "$backup_repo_dir" 2>/dev/null || {
            error "Failed to clone GitHub repo"
            return 1
        }
        cd "$backup_repo_dir"
    fi
    
    # Copy backup file
    mkdir -p "$path"
    cp "$backup_file" "$path/"
    
    # Commit and push
    git add "$path"
    git commit -m "🧠 Memory backup: $(basename "$backup_file")" || true
    git push origin "$branch" 2>/dev/null || {
        warn "Failed to push to GitHub"
    }
    
    cd - > /dev/null
    success "Synced to GitHub"
}

# Sync to S3
sync_s3() {
    local backup_file="$1"
    local s3_config=$(jq -r '.destinations.s3' "$CONFIG_FILE" 2>/dev/null)
    local enabled=$(echo "$s3_config" | jq -r '.enabled' 2>/dev/null || echo "false")
    
    if [[ "$enabled" != "true" ]]; then
        log "S3 sync disabled, skipping"
        return 0
    fi
    
    local bucket=$(echo "$s3_config" | jq -r '.bucket')
    local region=$(echo "$s3_config" | jq -r '.region')
    local path=$(echo "$s3_config" | jq -r '.path')
    
    log "Syncing to S3: $bucket/$path"
    
    # Check if aws cli is available
    if ! command -v aws &>/dev/null; then
        warn "AWS CLI not installed, skipping S3 sync"
        return 0
    fi
    
    aws s3 cp "$backup_file" "s3://$bucket/$path$(basename "$backup_file")" \
        --region "$region" 2>/dev/null || {
        warn "Failed to sync to S3"
        return 0
    }
    
    success "Synced to S3"
}

# Sync to WebDAV
sync_webdav() {
    local backup_file="$1"
    local webdav_config=$(jq -r '.destinations.webdav' "$CONFIG_FILE" 2>/dev/null)
    local enabled=$(echo "$webdav_config" | jq -r '.enabled' 2>/dev/null || echo "false")
    
    if [[ "$enabled" != "true" ]]; then
        log "WebDAV sync disabled, skipping"
        return 0
    fi
    
    local url=$(echo "$webdav_config" | jq -r '.url')
    local path=$(echo "$webdav_config" | jq -r '.path')
    
    log "Syncing to WebDAV: $url$path"
    
    # Check if curl is available
    if ! command -v curl &>/dev/null; then
        warn "curl not installed, skipping WebDAV sync"
        return 0
    fi
    
    # Upload via PUT
    curl -T "$backup_file" "$url$path/$(basename "$backup_file")" \
        -u "${WEBDAV_USER:-}:${WEBDAV_PASSWORD:-}" 2>/dev/null || {
        warn "Failed to sync to WebDAV"
        return 0
    }
    
    success "Synced to WebDAV"
}

# Cleanup old backups
cleanup_old() {
    log "Cleaning up old backups..."
    
    local daily_retention=$(jq -r '.retention.daily' "$CONFIG_FILE" 2>/dev/null || echo "7")
    local weekly_retention=$(jq -r '.retention.weekly' "$CONFIG_FILE" 2>/dev/null || echo "4")
    local monthly_retention=$(jq -r '.retention.monthly' "$CONFIG_FILE" 2>/dev/null || echo "12")
    
    # Daily: keep last N days
    find "$BACKUP_DIR" -type f -name "*.tar.gz*" -mtime +$daily_retention -delete 2>/dev/null || true
    
    # Weekly: keep first backup of each week
    # Monthly: keep first backup of each month
    # (Simplified: just keep total under limit)
    local max_files=$((daily_retention + weekly_retention + monthly_retention))
    local current_files=$(find "$BACKUP_DIR" -type f -name "*.tar.gz*" | wc -l)
    
    if [[ $current_files -gt $max_files ]]; then
        local to_delete=$((current_files - max_files))
        find "$BACKUP_DIR" -type f -name "*.tar.gz*" -printf '%T+ %p\n' | \
            sort | head -n $to_delete | cut -d' ' -f2- | xargs rm -f
        log "Deleted $to_delete old backup(s)"
    fi
    
    success "Cleanup complete"
}

# List backups
list_backups() {
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}        Memory Backups${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        echo "No backups found"
        return
    fi
    
    printf "${YELLOW}%-40s %-10s %s${NC}\n" "Filename" "Size" "Created"
    echo -e "${BLUE}────────────────────────────────────────${NC}"
    
    for file in "$BACKUP_DIR"/*.tar.gz*; do
        if [[ -f "$file" ]]; then
            local filename=$(basename "$file")
            local size=$(du -h "$file" | cut -f1)
            local created=$(stat -c %y "$file" | cut -d' ' -f1)
            printf "%-40s %-10s %s\n" "$filename" "$size" "$created"
        fi
    done
    
    echo -e "${BLUE}════════════════════════════════════════${NC}"
}

# Restore from backup
restore() {
    local backup_file="$1"
    local target_dir="${2:-$WORKSPACE_DIR}"
    
    if [[ ! -f "$backup_file" ]]; then
        error "Backup file not found: $backup_file"
        return 1
    fi
    
    log "Restoring from: $backup_file"
    
    local temp_dir=$(mktemp -d)
    local decrypted_file="$temp_dir/backup.tar.gz"
    
    # Decrypt if needed
    if [[ "$backup_file" == *.enc ]]; then
        export PASSWORD_ENV=$(jq -r '.encryption.password_env' "$CONFIG_FILE" 2>/dev/null || echo "MEMORY_BACKUP_PASSWORD")
        decrypt_file "$backup_file" "$decrypted_file"
    else
        decrypted_file="$backup_file"
    fi
    
    # Extract
    tar -xzf "$decrypted_file" -C "$target_dir"
    
    # Cleanup
    rm -rf "$temp_dir"
    
    success "Restored to: $target_dir"
}

# Full backup workflow
full_backup() {
    init_config
    init_backup_dir
    
    log "=========================================="
    log "Starting Full Memory Backup"
    log "=========================================="
    
    # Create backup
    local backup_file=$(create_backup)
    
    # Sync to destinations
    sync_github "$backup_file"
    sync_s3 "$backup_file"
    sync_webdav "$backup_file"
    
    # Cleanup old backups
    cleanup_old
    
    log "=========================================="
    log "Backup Complete"
    log "=========================================="
    
    echo "$backup_file"
}

# Show usage
usage() {
    cat << EOF
Usage: $(basename "$0") <command> [options]

Commands:
  backup          Create new backup
  restore <file>  Restore from backup file
  list            List all backups
  cleanup         Clean up old backups
  full            Full backup workflow (backup + sync + cleanup)
  config          Show/edit configuration
  status          Show backup status

Examples:
  $(basename "$0") backup
  $(basename "$0") restore /path/to/backup.tar.gz.enc
  $(basename "$0") full
  $(basename "$0") list

Environment Variables:
  MEMORY_BACKUP_PASSWORD  Encryption password
  WEBDAV_USER             WebDAV username
  WEBDAV_PASSWORD         WebDAV password

EOF
}

# Show status
show_status() {
    init_config
    
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}        Memory Backup Status${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    
    local config=$(cat "$CONFIG_FILE")
    
    printf "Enabled:          %s\n" "$(jq -r '.enabled' "$CONFIG_FILE")"
    printf "Encryption:       %s\n" "$(jq -r '.encryption.enabled' "$CONFIG_FILE")"
    printf "Local Backup:     %s\n" "$(jq -r '.destinations.local.enabled' "$CONFIG_FILE")"
    printf "GitHub Sync:      %s\n" "$(jq -r '.destinations.github.enabled' "$CONFIG_FILE")"
    printf "S3 Sync:          %s\n" "$(jq -r '.destinations.s3.enabled' "$CONFIG_FILE")"
    printf "WebDAV Sync:      %s\n" "$(jq -r '.destinations.webdav.enabled' "$CONFIG_FILE")"
    printf "Retention (D/W/M): %s/%s/%s days\n" \
        "$(jq -r '.retention.daily' "$CONFIG_FILE")" \
        "$(jq -r '.retention.weekly' "$CONFIG_FILE")" \
        "$(jq -r '.retention.monthly' "$CONFIG_FILE")"
    
    echo -e "${BLUE}────────────────────────────────────────${NC}"
    
    if [[ -d "$BACKUP_DIR" ]]; then
        local count=$(find "$BACKUP_DIR" -type f -name "*.tar.gz*" 2>/dev/null | wc -l)
        local size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "0")
        printf "Total Backups:    %s\n" "$count"
        printf "Total Size:       %s\n" "$size"
        
        if [[ $count -gt 0 ]]; then
            local latest=$(ls -t "$BACKUP_DIR"/*.tar.gz* 2>/dev/null | head -1)
            printf "Latest Backup:    %s\n" "$(basename "$latest")"
        fi
    else
        echo "No backups yet"
    fi
    
    echo -e "${BLUE}════════════════════════════════════════${NC}"
}

# Main
main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        backup)
            create_backup
            ;;
        restore)
            restore "$@"
            ;;
        list)
            list_backups
            ;;
        cleanup)
            init_backup_dir
            cleanup_old
            ;;
        full)
            full_backup
            ;;
        config)
            init_config
            cat "$CONFIG_FILE"
            ;;
        status)
            show_status
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
