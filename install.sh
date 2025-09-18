#!/bin/bash
# Speedflow Local Installer
# Usage: bash <(curl -fsSL https://github.com/limes/speedflow/raw/main/install.sh)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SPEEDFLOW_VERSION="1.0.0"
GITLAB_URL="https://gitlab.speednet.pl"
SPEEDFLOW_REPO="speedflow/core"
SPEEDFLOW_DIR=".claude"
TEMP_DIR="/tmp/speedflow-install-$$"


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

# Animated spinner
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

    tput cnorm # Show cursor
    printf "\r${GREEN}✅${NC} %s - Complete!\n" "$message"
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

# Check for updates
check_for_updates() {
    log_info "Checking for Speedflow updates..."

    # Get latest version from GitLab tags
    LATEST_VERSION=$(git ls-remote --tags "git@gitlab.speednet.pl:${SPEEDFLOW_REPO}.git" 2>/dev/null |
                     grep -o 'v[0-9]*\.[0-9]*\.[0-9]*$' |
                     sort -V |
                     tail -1 |
                     sed 's/^v//')

    if [ -z "$LATEST_VERSION" ]; then
        log_warning "Could not check for updates (no network or no tags)"
        return 0
    fi

    # Compare versions
    if [ "$SPEEDFLOW_VERSION" != "$LATEST_VERSION" ]; then
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
    log_info "Checking .gitignore safety..."
    
    # Add .claude to .gitignore if not present
    if [ ! -f ".gitignore" ] || ! grep -q "^\.claude/" .gitignore; then
        echo ".claude/" >> .gitignore
        log_success "Added .claude/ to .gitignore"
    else
        log_success ".claude/ already in .gitignore"
    fi
    
    # ALWAYS verify .gitignore is committed (regardless if added now or existed before)
    gitignore_status=$(git status --porcelain .gitignore 2>/dev/null)
    if [ -n "$gitignore_status" ]; then
        echo
        log_warning "SECURITY: .gitignore must be committed before continuing"
        echo "   This prevents accidentally committing Speedflow files to client repo."
        echo
        echo "   Git status shows: $gitignore_status"
        echo "   Run these commands NOW:"
        echo "   git add .gitignore"
        echo "   git commit -m 'Add .claude to gitignore'"
        echo
        read -p "Press Enter AFTER committing .gitignore..." -r
        
        # Check again after user claims to have committed
        gitignore_status=$(git status --porcelain .gitignore 2>/dev/null)
        if [ -n "$gitignore_status" ]; then
            log_error ".gitignore changes still not committed!"
            echo "Git status shows: $gitignore_status"
            echo "Please commit .gitignore first, then re-run installer"
            exit 1
        fi
    fi
    
    log_success ".gitignore is committed - safe to proceed"
}

# Install Speedflow locally
install_speedflow() {
    log_info "Installing Speedflow in current directory: $(pwd)"
    
    # Remove existing .claude if present
    if [ -d "$SPEEDFLOW_DIR" ]; then
        log_warning "Existing .claude directory found, backing up..."
        mv "$SPEEDFLOW_DIR" "${SPEEDFLOW_DIR}.backup.$(date +%s)"
    fi
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # Clone repository using SSH (quietly)
    log_info "Downloading Speedflow from GitLab..."
    if ! git clone "git@gitlab.speednet.pl:${SPEEDFLOW_REPO}.git" core > /dev/null 2>&1; then
        log_error "Failed to clone repository"
        log_error "Check your SSH key configuration and repository access"
        exit 1
    fi
    
    # Return to original directory
    cd - >/dev/null
    
    # Copy entire .claude structure from repo (quietly)
    log_info "Setting up .claude directory structure..."
    if [ -d "$TEMP_DIR/core" ]; then
        # Copy everything except .git and install.sh
        rsync -a --exclude='.git' --exclude='install.sh' --exclude='README.md' "$TEMP_DIR/core/" "$SPEEDFLOW_DIR/" > /dev/null 2>&1
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
        sed -i '' "s/{{VERSION}}/$SPEEDFLOW_VERSION/g" "$SPEEDFLOW_DIR/config.json" 2>/dev/null || \
        sed -i "s/{{VERSION}}/$SPEEDFLOW_VERSION/g" "$SPEEDFLOW_DIR/config.json"
        sed -i '' "s/{{AUTO_UPDATE}}/${AUTO_UPDATE:-false}/g" "$SPEEDFLOW_DIR/config.json" 2>/dev/null || \
        sed -i "s/{{AUTO_UPDATE}}/${AUTO_UPDATE:-false}/g" "$SPEEDFLOW_DIR/config.json"
        sed -i '' "s/{{INSTALLED_AT}}/$(date -u +%Y-%m-%dT%H:%M:%SZ)/g" "$SPEEDFLOW_DIR/config.json" 2>/dev/null || \
        sed -i "s/{{INSTALLED_AT}}/$(date -u +%Y-%m-%dT%H:%M:%SZ)/g" "$SPEEDFLOW_DIR/config.json"
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
    echo -e "${NC}"
    echo
    echo -e "${YELLOW}                    AI Development Platform Installer v1.0${NC}"
    echo
    echo -e "${GREEN}/install${NC}    install speedflow        ${BLUE}curl | bash${NC}"
    echo -e "${GREEN}/agents${NC}     ai code reviewers        ${BLUE}auto-loaded${NC}"
    echo -e "${GREEN}/context${NC}    company standards        ${BLUE}global rules${NC}"
    echo -e "${GREEN}/commands${NC}   claude code integration   ${BLUE}slash commands${NC}"
    echo
    echo -e "${YELLOW}Speedflow integrates with Claude Code CLI for enhanced development${NC}"
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
            echo -e "${YELLOW}Legend: ✅=Ready ⚠️=Warning ❌=Missing ⏳=Checking...${NC}"
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
    local steps=5
    local current=0

    # Step 1: Requirements
    show_progress $((++current)) $steps "Checking system requirements"
    check_requirements > /dev/null 2>&1 &
    show_spinner $! "Checking system requirements"

    # Step 2: GitLab access
    show_progress $((++current)) $steps "Verifying GitLab access"
    verify_gitlab_access > /dev/null 2>&1 &
    show_spinner $! "Verifying GitLab access"

    # Step 3: Git safety
    show_progress $((++current)) $steps "Ensuring Git safety"
    ensure_gitignore_safety > /dev/null 2>&1 &
    show_spinner $! "Ensuring Git safety"

    # Step 4: Installation
    show_progress $((++current)) $steps "Installing Speedflow"
    install_speedflow > /dev/null 2>&1 &
    show_spinner $! "Installing Speedflow components"

    # Step 5: Verification
    show_progress $((++current)) $steps "Verifying installation"
    verify_installation > /dev/null 2>&1 &
    show_spinner $! "Verifying installation"

    # Complete
    show_progress $steps $steps "Installation complete"
    echo
    log_success "Ready to use Speedflow with Claude Code! 🎯"
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
    # Parse command line arguments first
    parse_args "$@"

    # Check for updates if requested
    if [ "${1:-}" = "--check-update" ]; then
        check_for_updates
        exit 0
    fi

    show_welcome

    # Configure auto-update preference
    configure_auto_update

    # Trap cleanup
    trap cleanup EXIT

    # Check if terminal supports advanced features
    if [ "$TERM" != "dumb" ] && [ -t 1 ] && [ "$SILENT_UPDATE" != "true" ]; then
        install_with_progress
    else
        # Fallback to simple installation
        check_requirements
        verify_gitlab_access
        ensure_gitignore_safety
        install_speedflow
        verify_installation
        log_success "Ready to use Speedflow with Claude Code! 🎯"
    fi
}

# Run main function
main "$@"
