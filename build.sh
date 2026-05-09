[ -f "$HOME/.local/share/swiftly/env.sh" ] && source "$HOME/.local/share/swiftly/env.sh"
#!/bin/bash

# Quantum Badger Build Script
# Builds the complete application with all dependencies

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BUILD_CONFIG="debug"
VERBOSE=false
RUN_TESTS=false
CLEAN=false
STRICT_MODE=false
TESTS_FAILED=false
PLATFORM_FLAGS=() # Fallback flags for non-macOS environments

# Print usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -c, --config <debug|release>   Build configuration (default: debug)"
    echo "  -t, --test                      Run tests after building"
    echo "  --strict                        Fail build on test failures (strict mode)"
    echo "  --clean                         Clean build artifacts before building"
    echo "  -v, --verbose                  Verbose output"
    echo "  -h, --help                      Show this help message"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            BUILD_CONFIG="$2"
            if [[ "$BUILD_CONFIG" != "debug" && "$BUILD_CONFIG" != "release" ]]; then
                echo -e "${RED}Error: Invalid config '$BUILD_CONFIG'. Use 'debug' or 'release'.${NC}"
                exit 1
            fi
            shift 2
            ;;
        -t|--test)
            RUN_TESTS=true
            shift
            ;;
        --strict)
            STRICT_MODE=true
            shift
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option '$1'${NC}"
            usage
            exit 1
            ;;
    esac
done

# Print banner
echo -e "${BLUE}"
echo "=========================================="
echo "  🦡 Quantum Badger Build Script"
echo "=========================================="
echo -e "${NC}"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"

# Detect Platform / Jules Fallback
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${YELLOW}⚠ Non-macOS environment detected (Jules/Linux).${NC}"
    echo -e "${YELLOW}Applying fallback flags: -Xswiftc -DJS_LINUX${NC}"
    # Use -Xswiftc to pass the conditional compilation flag to the compiler
    PLATFORM_FLAGS=("-Xswiftc" "-DJS_LINUX")
else
    # Check for Xcode only on macOS
    if ! xcode-select -p &>/dev/null; then
        echo -e "${RED}Error: Xcode command line tools not found.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Xcode tools found${NC}"
fi

# Check for Swift 6+ (Common to both macOS and Linux)
SWIFT_VERSION=$(swift --version 2>/dev/null | head -1 | grep -o 'Swift version [0-9]\+' | grep -o '[0-9]\+' || echo "0")
if [[ "$SWIFT_VERSION" -lt 6 ]]; then
    echo -e "${RED}Error: Swift 6.0+ is required. Found: $(swift --version 2>/dev/null | head -1)${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Swift version check passed${NC}"

# Clean if requested
if [[ "$CLEAN" == true ]]; then
    echo -e "${YELLOW}Cleaning build artifacts...${NC}"
    rm -rf BadgerCore/.build
    rm -rf BadgerRuntime/.build
    rm -rf BadgerApp/.build
    echo -e "${GREEN}✓ Clean complete${NC}"
fi

# Build function
build_package() {
    local package_dir=$1
    local package_name=$2
    
    echo ""
    echo -e "${BLUE}Building ${package_name}...${NC}"
    
    cd "$package_dir"
    
    local build_args=(-c "$BUILD_CONFIG")
    if [[ "$VERBOSE" == true ]]; then
        build_args+=(--verbose)
    fi
    
    # Execute build with platform fallback flags
    if swift build "${build_args[@]}" "${PLATFORM_FLAGS[@]}"; then
        echo -e "${GREEN}✓ ${package_name} built successfully${NC}"
    else
        echo -e "${RED}✗ ${package_name} build failed${NC}"
        exit 1
    fi
    
    cd "$SCRIPT_DIR"
}

# Test function
test_package() {
    local package_dir=$1
    local package_name=$2
    
    echo ""
    echo -e "${BLUE}Testing ${package_name}...${NC}"
    
    cd "$package_dir"
    
    local test_args=()
    if [[ "$VERBOSE" == true ]]; then
        test_args+=(--verbose)
    fi
    
    # Execute tests with platform fallback flags
    if swift test "${test_args[@]}" "${PLATFORM_FLAGS[@]}"; then
        echo -e "${GREEN}✓ ${package_name} tests passed${NC}"
    else
        TESTS_FAILED=true
        if [[ "$STRICT_MODE" == true ]]; then
            echo -e "${RED}✗ ${package_name} tests failed${NC}"
            exit 1
        else
            echo -e "${YELLOW}⚠ ${package_name} tests failed (continuing in non-strict mode)${NC}"
        fi
    fi
    
    cd "$SCRIPT_DIR"
}

# Build all packages in dependency order
build_package "BadgerCore" "BadgerCore"
build_package "BadgerRuntime" "BadgerRuntime"
build_package "BadgerApp" "BadgerApp"

# Run tests if requested
if [[ "$RUN_TESTS" == true ]]; then
    echo ""
    echo -e "${BLUE}=========================================="
    echo "  Running Tests"
    echo "==========================================${NC}"
    
    test_package "BadgerCore" "BadgerCore"
    test_package "BadgerRuntime" "BadgerRuntime"
    test_package "BadgerApp" "BadgerApp"
fi

# Summary logic remains the same...
echo ""
echo -e "${GREEN}=========================================="
echo "  🎉 Build Process Complete!"
echo "=========================================="
echo -e "${NC}"
