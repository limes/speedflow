#!/bin/bash
# Speedflow Local Installer
# Usage: bash <(curl -fsSL https://github.com/limes/speedflow/raw/main/install.sh)

set -e

# Global debug flag
DEBUG_MODE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
GITLAB_URL="https://gitlab.speednet.pl"
SPEEDFLOW_REPO="speedflow/core"
SPEEDFLOW_DIR=".claude"
TEMP_DIR="/tmp/speedflow-install-$$"

# Get version from Git tags dynamically
get_current_version() {
    # If version is forced via command line, use that
    if [ -n "$FORCE_VERSION" ]; then
        echo "$FORCE_VERSION" | sed 's/^v//'
        return
    fi

    # Try to get version from current repo if we're in one
    local version=""
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        version=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
    fi

    # If no local version, try remote
    if [ -z "$version" ]; then
        version=$(git ls-remote --tags "git@${GITLAB_URL#https://}:${SPEEDFLOW_REPO}.git" 2>/dev/null |
                  grep -o 'v[0-9]*\.[0-9]*\.[0-9]*$' |
                  sort -V |
                  tail -1 |
                  sed 's/^v//')
    fi

    # Fallback to dev version
    if [ -z "$version" ]; then
        if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            version="dev-$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
        else
            version="dev"
        fi
    fi

    echo "$version"
}

# Set version dynamically
SPEEDFLOW_VERSION=$(get_current_version)


# Progress bar using tput
show_progress() {
    local current=$1
    local total=$2
    local message=$3
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))

    # Save cursor position
    tput sc

    # Move to progress line
    tput cup $(($(tput lines) - 3)) 0

    # Clear line and show progress
    tput el
    printf "\r${BLUE}%s${NC} [" "$message"

    # Draw progress bar
    for ((i=0; i<filled; i++)); do printf "█"; done
    for ((i=filled; i<width; i++)); do printf "░"; done

    printf "] %d%%" "$percentage"

    # Restore cursor
    tput rc
}

# Animated spinner with exit code checking
show_spinner() {
    local pid=$1
    local message=$2
    local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local i=0

    tput civis # Hide cursor

    while kill -0 $pid 2>/dev/null; do
        local char=${chars:$((i % ${#chars})):1}
        printf "\r${BLUE}%s${NC} %s" "$char" "$message"
        sleep 0.1
        ((i++))
    done

    # Wait for process and check exit code
    wait $pid
    local exit_code=$?

    tput cnorm # Show cursor

    if [ $exit_code -ne 0 ]; then
        printf "\r${RED}❌${NC} %s - Failed!\n" "$message"
        exit $exit_code
    else
        printf "\r${GREEN}✅${NC} %s - Complete!\n" "$message"
    fi
}

# Functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_debug() {
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${PURPLE}🐛 DEBUG: $1${NC}" >&2
    fi
}

debug_exec() {
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${PURPLE}🐛 EXEC: $*${NC}" >&2
        "$@"
    else
        "$@"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Precheck functions for welcome screen
precheck_node() {
    if command_exists "node"; then
        local version=$(node --version 2>/dev/null | sed 's/v//')
        local major=$(echo "$version" | cut -d. -f1)
        if [ "$major" -ge 18 ]; then
            echo "✅"
        else
            echo "⚠️"
        fi
    else
        echo "❌"
    fi
}

precheck_git() {
    if command_exists "git"; then
        echo "✅"
    else
        echo "❌"
    fi
}

precheck_gitlab_access() {
    if ssh -T git@gitlab.speednet.pl -o ConnectTimeout=5 -o StrictHostKeyChecking=no 2>&1 | grep -q "Welcome" 2>/dev/null; then
        echo "✅"
    else
        echo "❌"
    fi
}

precheck_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "darwin"* ]] || [[ -n "$WSL_DISTRO_NAME" ]]; then
        echo "✅"
    else
        echo "❌"
    fi
}

precheck_claude() {
    if command_exists "claude"; then
        echo "✅"
    else
        echo "⚠️"
    fi
}

# Get latest version from remote
get_latest_version() {
    git ls-remote --tags "git@${GITLAB_URL#https://}:${SPEEDFLOW_REPO}.git" 2>/dev/null |
    grep -o 'v[0-9]*\.[0-9]*\.[0-9]*$' |
    sort -V |
    tail -1 |
    sed 's/^v//'
}

# Check for updates
check_for_updates() {
    log_info "Checking for Speedflow updates..."

    # Get latest version from GitLab tags
    LATEST_VERSION=$(get_latest_version)

    if [ -z "$LATEST_VERSION" ]; then
        log_warning "Could not check for updates (no network or no tags)"
        return 0
    fi

    # Compare versions (skip dev versions)
    if [[ "$SPEEDFLOW_VERSION" != "dev"* ]] && [ "$SPEEDFLOW_VERSION" != "$LATEST_VERSION" ]; then
        log_warning "Update available: v$LATEST_VERSION (current: v$SPEEDFLOW_VERSION)"
        echo
        read -p "Update now? [Y/n]: " -r
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            log_info "Updating to v$LATEST_VERSION..."
            curl -fsSL "https://github.com/limes/speedflow/raw/v${LATEST_VERSION}/install.sh" | bash
            exit 0
        fi
    else
        log_success "Speedflow is up to date (v$SPEEDFLOW_VERSION)"
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --debug)
                DEBUG_MODE=true
                log_debug "Debug mode enabled"
                shift
                ;;
            --check-update)
                check_for_updates
                exit 0
                ;;
            --auto-update)
                AUTO_UPDATE=true
                shift
                ;;
            --no-auto-update)
                AUTO_UPDATE=false
                shift
                ;;
            --update|--silent)
                # Silent update mode
                SILENT_UPDATE=true
                shift
                ;;
            --version=*)
                # Force specific version installation
                FORCE_VERSION="${1#*=}"
                shift
                ;;
            --version)
                # Force specific version installation (separate argument)
                FORCE_VERSION="$2"
                shift 2
                ;;
            --help|-h)
                echo "Speedflow Installer"
                echo
                echo "Usage: bash <(curl -fsSL .../install.sh) [OPTIONS]"
                echo
                echo "Command line options:"
                echo "  --debug                Enable debug mode (verbose logging)"
                echo "  --check-update         Check for available updates"
                echo "  --auto-update          Enable auto-update (default: ask user)"
                echo "  --no-auto-update       Disable auto-update"
                echo "  --version X.X.X        Force install specific version"
                echo "  --update, --silent     Silent update mode"
                echo "  --help, -h             Show this help"
                echo
                echo "Examples:"
                echo "  bash <(curl -fsSL .../install.sh)                   # Normal installation"
                echo "  bash <(curl -fsSL .../install.sh) --debug          # Installation with debug logs"
                echo "  bash <(curl -fsSL .../install.sh) --version 1.0.1  # Install specific version"
                echo "  bash <(curl -fsSL .../install.sh) --check-update   # Check for updates only"
                echo
                echo "Support:"
                echo "  • Slack: @sjakubowski"
                echo "  • Email: sjakubowski@speednet.pl"
                echo
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done
}

# Verify GitLab SSH access
verify_gitlab_access() {
    log_info "Verifying GitLab SSH access..."

    # Test SSH connection to GitLab
    if ssh -T git@gitlab.speednet.pl -o ConnectTimeout=10 -o StrictHostKeyChecking=no 2>&1 | grep -q "Welcome"; then
        log_success "SSH access to GitLab verified ✅"
        return 0
    else
        log_error "❌ SSH access to GitLab failed"
        echo
        echo "🔑 SSH key setup required:"
        echo "   1. Generate SSH key: ssh-keygen -t ed25519"
        echo "   2. Add key to GitLab: ${GITLAB_URL}/-/profile/keys"
        echo "   3. Re-run installer"
        echo
        echo "   📞 Need help? Contact:"
        echo "   • Slack: #speedflow-support"
        echo "   • Email: admin@speednet.pl"
        exit 1
    fi
}

# Install Claude Code CLI
install_claude_code() {
    log_info "Installing Claude Code CLI..."

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS installation
        if command_exists "brew"; then
            log_info "Installing via Homebrew..."
            brew install claude
        else
            log_info "Installing via curl..."
            curl -fsSL https://claude.ai/install.sh | sh
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux installation
        log_info "Installing via curl..."
        curl -fsSL https://claude.ai/install.sh | sh
    else
        log_error "Automatic Claude Code installation not supported on this OS"
        echo "Please install manually: https://claude.ai/code"
        exit 1
    fi

    # Verify installation
    if command_exists "claude"; then
        log_success "Claude Code CLI installed successfully"
    else
        log_error "Claude Code CLI installation failed"
        echo "Please install manually: https://claude.ai/code"
        exit 1
    fi
}

# Check system requirements
check_requirements() {
    log_info "Checking system requirements..."

    # Check OS
    if [[ "$OSTYPE" != "linux-gnu"* ]] && [[ "$OSTYPE" != "darwin"* ]]; then
        if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ -n "$WINDIR" ]]; then
            log_error "Windows detected - WSL required!"
            echo
            echo "🪟 Windows users must use WSL (Windows Subsystem for Linux):"
            echo "   1. Install WSL: wsl --install"
            echo "   2. Restart computer"
            echo "   3. Run installer from WSL terminal"
            echo
            echo "   📖 Guide: https://docs.microsoft.com/en-us/windows/wsl/install"
        else
            log_error "Unsupported OS: $OSTYPE"
            log_error "Speedflow supports Linux, macOS, and Windows WSL only"
        fi
        exit 1
    fi

    # Check required commands
    local missing_commands=()

    for cmd in git; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done

    # Check for Claude Code CLI
    if ! command_exists "claude"; then
        log_warning "Claude Code CLI not found - attempting installation..."
        log_info "Note: Claude Code requires Node.js 18+"
        install_claude_code
    else
        log_success "Claude Code CLI found"
    fi

    if [ ${#missing_commands[@]} -gt 0 ]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        echo "Please install missing commands and try again."
        exit 1
    fi

    log_success "System requirements met"
}

# Ensure .claude is in committed .gitignore
ensure_gitignore_safety() {
    log_debug "Starting ensure_gitignore_safety function"
    log_info "Checking Git safety requirements..."

    log_debug "Checking if current directory is a Git repository"
    # Check if we're in a Git repository (this check is now done inline in install_with_progress)
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log_debug "Git repository check failed"
        echo
        log_error "SECURITY REQUIREMENT: Must be in Git repository"
        echo
        echo "🔒 Speedflow requires Git version control for security:"
        echo "   • Prevents accidental commit of .claude/ files"
        echo "   • Ensures .gitignore protection is committed"
        echo "   • Maintains clean client repositories"
        echo
        echo "📋 Initialize Git repository first:"
        echo "   git init"
        echo "   git add ."
        echo "   git commit -m 'Initial commit'"
        echo
        echo "   Or clone your existing client repository:"
        echo "   git clone <your-client-repo-url> ."
        echo
        echo "   Then re-run Speedflow installer"
        echo
        exit 1
    fi

    log_debug "Git repository check passed"

    # Add .claude to .gitignore if not present
    log_debug "Checking if .claude/ is in .gitignore"
    if [ ! -f ".gitignore" ] || ! grep -q "^\.claude/" .gitignore; then
        log_debug "Adding .claude/ to .gitignore"
        echo ".claude/" >> .gitignore
        log_success "Added .claude/ to .gitignore"
    else
        log_success ".claude/ already in .gitignore"
    fi

    # ALWAYS verify .gitignore is committed (regardless if added now or existed before)
    log_debug "Checking if .gitignore is committed to Git"
    gitignore_status=$(git status --porcelain .gitignore 2>/dev/null)
    log_debug "Git status for .gitignore: '$gitignore_status'"
    if [ -n "$gitignore_status" ]; then
        log_debug ".gitignore is not committed, showing error message"
        echo
        log_error "SECURITY REQUIREMENT: .gitignore must be committed"
        echo
        echo "🔒 This prevents accidentally committing Speedflow files to client repo."
        echo
        echo "   Git status shows: $gitignore_status"
        echo "   📋 Commit .gitignore NOW:"
        echo "   git add .gitignore"
        echo "   git commit -m 'Add .claude to gitignore'"
        echo
        echo "   Then re-run Speedflow installer"
        echo
        exit 1
    fi

    log_success "Git safety requirements met - safe to proceed"
}

# Install Speedflow locally
install_speedflow() {
    log_info "Installing Speedflow in current directory: $(pwd)"

    # Create temp directory
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"

    # Clone repository using SSH (quietly)
    log_info "Downloading Speedflow from GitLab..."
    if [ -n "$FORCE_VERSION" ]; then
        log_info "Installing forced version: v$FORCE_VERSION"
        if ! git clone --depth 1 --branch "v$FORCE_VERSION" "git@gitlab.speednet.pl:${SPEEDFLOW_REPO}.git" core > /dev/null 2>&1; then
            log_error "Failed to clone repository at version v$FORCE_VERSION"
            log_error "Check if version exists and your SSH key configuration"
            exit 1
        fi
    else
        if ! git clone "git@gitlab.speednet.pl:${SPEEDFLOW_REPO}.git" core > /dev/null 2>&1; then
            log_error "Failed to clone repository"
            log_error "Check your SSH key configuration and repository access"
            exit 1
        fi
    fi

    # Return to original directory
    cd - >/dev/null

    # Copy entire .claude structure from repo (quietly)
    log_info "Setting up .claude directory structure..."
    if [ -d "$TEMP_DIR/core" ]; then
        # Create target directory if it doesn't exist
        mkdir -p "$SPEEDFLOW_DIR"

        # Copy everything except .git and install.sh
        # Using cp instead of rsync for better compatibility
        for item in "$TEMP_DIR/core"/*; do
            basename=$(basename "$item")
            if [ "$basename" != ".git" ] && [ "$basename" != "install.sh" ] && [ "$basename" != "README.md" ]; then
                cp -r "$item" "$SPEEDFLOW_DIR/"
            fi
        done

        # Also copy hidden files (if any, excluding .git)
        for item in "$TEMP_DIR/core"/.*; do
            basename=$(basename "$item")
            if [ "$basename" != "." ] && [ "$basename" != ".." ] && [ "$basename" != ".git" ]; then
                cp -r "$item" "$SPEEDFLOW_DIR/" 2>/dev/null || true
            fi
        done

        log_success "Speedflow structure installed"
    else
        log_error "Repository structure not found"
        exit 1
    fi

    # No need to keep repo - updates can re-run installer

    # Create configuration files from templates
    log_info "Creating configuration files..."

    # Copy and configure Speedflow config
    if [ -f "$TEMP_DIR/core/templates/config.json.template" ]; then
        cp "$TEMP_DIR/core/templates/config.json.template" "$SPEEDFLOW_DIR/config.json"

        # Use portable sed replacement
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/{{VERSION}}/$SPEEDFLOW_VERSION/g" "$SPEEDFLOW_DIR/config.json"
            sed -i '' "s/{{AUTO_UPDATE}}/${AUTO_UPDATE:-false}/g" "$SPEEDFLOW_DIR/config.json"
            sed -i '' "s/{{INSTALLED_AT}}/$(date -u +%Y-%m-%dT%H:%M:%SZ)/g" "$SPEEDFLOW_DIR/config.json"
        else
            sed -i "s/{{VERSION}}/$SPEEDFLOW_VERSION/g" "$SPEEDFLOW_DIR/config.json"
            sed -i "s/{{AUTO_UPDATE}}/${AUTO_UPDATE:-false}/g" "$SPEEDFLOW_DIR/config.json"
            sed -i "s/{{INSTALLED_AT}}/$(date -u +%Y-%m-%dT%H:%M:%SZ)/g" "$SPEEDFLOW_DIR/config.json"
        fi
    fi

    # Copy Claude Code settings
    if [ -f "$TEMP_DIR/core/templates/settings.local.json.template" ]; then
        cp "$TEMP_DIR/core/templates/settings.local.json.template" "$SPEEDFLOW_DIR/settings.local.json"
    fi

    log_success "Configuration files created"
}

# Cleanup
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Prompt user to launch Claude Code CLI after successful installation
prompt_launch_claude() {
    # Skip prompt in silent mode (auto-updates)
    if [ "$SILENT_UPDATE" = "true" ]; then
        log_debug "Skipping Claude launch prompt in silent mode"
        return 0
    fi

    log_debug "Prompting user to launch Claude Code CLI"
    echo
    echo -e "${YELLOW}🚀 Launch Claude Code CLI now?${NC}"
    echo "• Claude Code is ready with Speedflow enhancements"
    echo "• All agents and commands are immediately available"
    echo "• You'll need to approve directory trust (choose 'Yes, proceed')"
    echo

    while true; do
        read -p "Start Claude Code CLI? [Y/n]: " -r
        case $REPLY in
            [Yy]* | "")
                log_debug "User chose to launch Claude Code CLI"
                echo
                log_info "Launching Claude Code CLI..."
                echo
                # Launch Claude and exit installer
                if command_exists "claude"; then
                    echo "Starting Claude Code CLI..."
                    echo "→ When prompted, choose 'Yes, proceed' to trust this directory"
                    echo
                    exec claude
                else
                    log_error "Claude Code CLI not found after installation"
                    echo "Please run: claude"
                fi
                break
                ;;
            [Nn]*)
                log_debug "User chose not to launch Claude Code CLI"
                echo
                log_info "Claude Code CLI ready when you need it!"
                echo "To start later: claude"
                break
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."

    if [ -d "$SPEEDFLOW_DIR/agents" ] && [ -f "$SPEEDFLOW_DIR/settings.local.json" ]; then
        log_success "Speedflow installed successfully! 🎉"
        echo
        echo "📋 Next steps:"
        echo "   1. Start Claude Code CLI: claude"
        echo "   2. Use Speedflow commands: /speedflow-review-pr"
        echo "   3. Access Speedflow agents automatically"
        echo
        echo "📁 Files installed in .claude/"
        echo "   • Agents: $(ls -1 "$SPEEDFLOW_DIR/agents" | wc -l | tr -d ' ') AI agents"
        echo "   • Context: Global company standards"
        echo "   • Commands: Speedflow slash commands"
    else
        log_error "Installation verification failed"
        exit 1
    fi
}


# Show welcome screen with live prechecks
show_welcome() {
    clear
    echo -e "${BLUE}"
    echo "███████╗██████╗ ███████╗███████╗██████╗ ███████╗██╗      ██████╗ ██╗    ██╗"
    echo "██╔════╝██╔══██╗██╔════╝██╔════╝██╔══██╗██╔════╝██║     ██╔═══██╗██║    ██║"
    echo "███████╗██████╔╝█████╗  █████╗  ██║  ██║█████╗  ██║     ██║   ██║██║ █╗ ██║"
    echo "╚════██║██╔═══╝ ██╔══╝  ██╔══╝  ██║  ██║██╔══╝  ██║     ██║   ██║██║███╗██║"
    echo "███████║██║     ███████╗███████╗██████╔╝██║     ███████╗╚██████╔╝╚███╔███╔╝"
    echo "╚══════╝╚═╝     ╚══════╝╚══════╝╚═════╝ ╚═╝     ╚══════╝ ╚═════╝  ╚══╝╚══╝ "
    echo -e "${BLUE}by Speednet${NC}"
    echo -e "${YELLOW}v${SPEEDFLOW_VERSION}${NC}"
    echo -e "${NC}"
    echo

    # Show system requirements with live checking
    echo -e "${BLUE}📋 System Requirements Check:${NC}"
    echo

    # Create temp file for precheck results
    local check_file="/tmp/speedflow-precheck-$$"

    # Start background checks
    {
        echo "os:$(precheck_os)"
        echo "git:$(precheck_git)"
        echo "node:$(precheck_node)"
        echo "claude:$(precheck_claude)"
        echo "gitlab:$(precheck_gitlab_access)"
    } > "$check_file" 2>/dev/null &
    local check_pid=$!

    # Display checks with live updates
    local checks_done=false
    while [ "$checks_done" = false ]; do
        if [ -f "$check_file" ]; then
            # Save cursor position and display results
            local os_status="⏳"
            local git_status="⏳"
            local node_status="⏳"
            local claude_status="⏳"
            local gitlab_status="⏳"

            if [ -s "$check_file" ]; then
                os_status=$(grep "^os:" "$check_file" 2>/dev/null | cut -d: -f2 || echo "⏳")
                git_status=$(grep "^git:" "$check_file" 2>/dev/null | cut -d: -f2 || echo "⏳")
                node_status=$(grep "^node:" "$check_file" 2>/dev/null | cut -d: -f2 || echo "⏳")
                claude_status=$(grep "^claude:" "$check_file" 2>/dev/null | cut -d: -f2 || echo "⏳")
                gitlab_status=$(grep "^gitlab:" "$check_file" 2>/dev/null | cut -d: -f2 || echo "⏳")
            fi

            tput sc  # Save cursor
            echo "   $os_status Operating System (Linux/macOS/WSL)"
            echo "   $git_status Git installed"
            echo "   $node_status Node.js 18+"
            echo "   $claude_status Claude Code CLI (will install if missing)"
            echo "   $gitlab_status Speednet GitLab SSH Access"
            echo

            # Check if background process is done
            if ! kill -0 $check_pid 2>/dev/null; then
                checks_done=true
            else
                sleep 0.5
                tput rc  # Restore cursor
                tput ed  # Clear below cursor
            fi
        else
            sleep 0.1
        fi
    done

    # Clean up
    rm -f "$check_file" 2>/dev/null

    echo
    read -p "Press Enter to continue with installation..." -r
    clear
}

# Enhanced installation with progress
install_with_progress() {
    log_debug "Starting installation with progress tracking"
    local steps=5
    local current=0

    # Step 1: Requirements
    log_debug "Step 1: Checking system requirements"
    printf "\r${BLUE}⏳${NC} Checking system requirements...\n"
    if check_requirements > /dev/null 2>&1; then
        printf "\r${GREEN}✅${NC} Checking system requirements - Complete!\n"
    else
        printf "\r${RED}❌${NC} Checking system requirements - Failed!\n"
        exit 1
    fi

    # Step 2: GitLab access
    log_debug "Step 2: Verifying GitLab SSH access"
    printf "\r${BLUE}⏳${NC} Verifying GitLab access...\n"
    if ! verify_gitlab_access > /dev/null 2>&1; then
        log_debug "GitLab access verification failed"
        printf "\r${RED}❌${NC} Verifying GitLab access - Failed!\n"
        echo
        echo
        log_error "❌ SSH access to GitLab failed"
        echo
        echo "🔑 SSH key setup required:"
        echo "   1. Generate SSH key: ssh-keygen -t ed25519"
        echo "   2. Add key to GitLab: ${GITLAB_URL}/-/profile/keys"
        echo "   3. Re-run installer"
        echo
        echo "   📞 Need help? Contact:"
        echo "   • Slack: #speedflow-support"
        echo "   • Email: admin@speednet.pl"
        echo
        exit 1
    else
        log_debug "GitLab access verification passed"
        printf "\r${GREEN}✅${NC} Verifying GitLab access - Complete!\n"
    fi

    # Step 3: Git safety
    log_debug "Step 3: Ensuring Git safety requirements"
    printf "\r${BLUE}⏳${NC} Ensuring Git safety...\n"

    # Check if we're in a Git repository (direct check to avoid subshell issues)
    log_debug "Performing direct Git repository check"
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log_debug "Direct Git repository check failed"
        printf "\r${RED}❌${NC} Ensuring Git safety - Failed!\n"
        echo
        echo
        log_error "SECURITY REQUIREMENT: Must be in Git repository"
        echo
        echo "🔒 Speedflow requires Git version control for security:"
        echo "   • Prevents accidental commit of .claude/ files"
        echo "   • Ensures .gitignore protection is committed"
        echo "   • Maintains clean client repositories"
        echo
        echo "📋 Initialize Git repository first:"
        echo "   git init"
        echo "   git add ."
        echo "   git commit -m 'Initial commit'"
        echo
        echo "   Or clone your existing client repository:"
        echo "   git clone <your-client-repo-url> ."
        echo
        echo "   Then re-run Speedflow installer"
        echo
        exit 1
    fi

    log_debug "Direct Git repository check passed"

    # Run the rest of gitignore safety checks
    log_debug "Running detailed Git safety checks via ensure_gitignore_safety"
    if ! ensure_gitignore_safety; then
        log_debug "ensure_gitignore_safety function failed"
        printf "\r${RED}❌${NC} Ensuring Git safety - Failed!\n"
        echo
        echo "Failed to configure .gitignore safety. Check permissions."
        exit 1
    else
        log_debug "Git safety checks completed successfully"
        printf "\r${GREEN}✅${NC} Ensuring Git safety - Complete!\n"
    fi

    # Step 4: Installation
    log_debug "Step 4: Installing Speedflow components"
    printf "\r${BLUE}⏳${NC} Installing Speedflow components...\n"

    # Run install_speedflow directly without background process
    if install_speedflow > /tmp/speedflow-install-log-$$.txt 2>&1; then
        printf "\r${GREEN}✅${NC} Installing Speedflow components - Complete!\n"
    else
        printf "\r${RED}❌${NC} Installing Speedflow components - Failed!\n"
        log_error "Installation failed. Check /tmp/speedflow-install-log-$$.txt for details"
        exit 1
    fi

    # Step 5: Verification
    log_debug "Step 5: Verifying installation"
    printf "\r${BLUE}⏳${NC} Verifying installation...\n"

    # Run verify_installation directly
    if verify_installation > /dev/null 2>&1; then
        printf "\r${GREEN}✅${NC} Verifying installation - Complete!\n"
    else
        printf "\r${RED}❌${NC} Verifying installation - Failed!\n"
        exit 1
    fi

    echo
    log_success "Ready to use Speedflow with Claude Code! 🎯"

    # Prompt to launch Claude Code CLI
    prompt_launch_claude
}

# Check for existing installation and handle user choice
handle_existing_installation() {
    if [ -d "$SPEEDFLOW_DIR" ]; then
        echo
        log_warning "Existing Speedflow installation found in .claude/"
        echo
        echo "Choose an option:"
        echo "  1) Backup current installation and install fresh"
        echo "  2) Remove current installation and install fresh"
        echo "  3) Exit without changes"
        echo
        read -p "Enter your choice [1-3]: " -r choice

        case $choice in
            1)
                local backup_name=".claude.backup.$(date +%Y%m%d_%H%M%S)"
                log_info "Backing up existing installation to $backup_name"
                mv "$SPEEDFLOW_DIR" "$backup_name"
                log_success "Backup created: $backup_name"
                ;;
            2)
                log_info "Removing existing installation..."
                rm -rf "$SPEEDFLOW_DIR"
                log_success "Existing installation removed"
                ;;
            3)
                log_info "Installation cancelled by user"
                exit 0
                ;;
            *)
                log_error "Invalid choice. Installation cancelled."
                exit 1
                ;;
        esac
        echo
    fi
}

# Ask user about auto-update
configure_auto_update() {
    if [ -z "$AUTO_UPDATE" ] && [ "$SILENT_UPDATE" != "true" ]; then
        echo
        echo -e "${YELLOW}Auto-Update Configuration:${NC}"
        echo "• Speedflow can automatically check for updates when Claude starts"
        echo "• Updates require manual confirmation"
        echo "• You can change this later in .claude/config.json"
        echo
        read -p "Enable auto-update checking? [Y/n]: " -r
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            AUTO_UPDATE=false
        else
            AUTO_UPDATE=true
        fi
    fi
}

# Main installation flow
main() {
    log_debug "Starting Speedflow installer (main function)"
    log_debug "Command line arguments: $*"

    # Parse command line arguments first
    log_debug "Parsing command line arguments"
    parse_args "$@"

    # Check for updates if requested
    if [ "${1:-}" = "--check-update" ]; then
        log_debug "Update check requested, running check_for_updates"
        check_for_updates
        exit 0
    fi

    log_debug "Showing welcome screen"
    show_welcome

    # Check for existing installation
    log_debug "Checking for existing installation"
    handle_existing_installation

    # Configure auto-update preference
    log_debug "Configuring auto-update preferences"
    configure_auto_update

    # Trap cleanup
    trap cleanup EXIT

    # Check if terminal supports advanced features
    log_debug "Checking terminal capabilities for progress display"
    if [ "$TERM" != "dumb" ] && [ -t 1 ] && [ "$SILENT_UPDATE" != "true" ]; then
        log_debug "Terminal supports advanced features, using progress installation"
        install_with_progress
    else
        log_debug "Using fallback simple installation"
        # Fallback to simple installation
        check_requirements
        verify_gitlab_access
        ensure_gitignore_safety
        install_speedflow
        verify_installation
        log_success "Ready to use Speedflow with Claude Code! 🎯"

        # Prompt to launch Claude Code CLI
        prompt_launch_claude
    fi
}

# Run main function
main "$@"
