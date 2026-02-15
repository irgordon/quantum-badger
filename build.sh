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

# Print usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -c, --config <debug|release>   Build configuration (default: debug)"
    echo "  -t, --test                     Run tests after building"
    echo "  --strict                       Fail build on test failures (strict mode)"
    echo "  --clean                        Clean build artifacts before building"
    echo "  -v, --verbose                  Verbose output"
    echo "  -h, --help                     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                             # Build debug configuration"
    echo "  $0 --config release            # Build release configuration"
    echo "  $0 --test                      # Build and run tests (warnings only)"
    echo "  $0 --test --strict             # Build and fail on test errors"
    echo "  $0 --clean --config release    # Clean and build release"
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

# Verbose output function
log() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "$@"
    fi
}

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

# Check for macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}Error: This project requires macOS to build.${NC}"
    exit 1
fi

# Check for Swift 6+
SWIFT_VERSION=$(swift --version 2>/dev/null | head -1 | grep -o 'Swift version [0-9]\+' | grep -o '[0-9]\+' || echo "0")
if [[ "$SWIFT_VERSION" -lt 6 ]]; then
    echo -e "${RED}Error: Swift 6.0+ is required. Found: $(swift --version 2>/dev/null | head -1)${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Swift version check passed${NC}"

# Check for Xcode
if ! xcode-select -p &>/dev/null; then
    echo -e "${RED}Error: Xcode command line tools not found.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Xcode tools found${NC}"

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
    
    if swift build "${build_args[@]}"; then
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
    
    if swift test "${test_args[@]}"; then
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

# Print summary
echo ""
echo -e "${GREEN}=========================================="
echo "  🎉 Build Complete!"
echo "=========================================="
echo -e "${NC}"
echo "Configuration: $BUILD_CONFIG"
echo ""
echo "Built packages:"
echo "  • BadgerCore"
echo "  • BadgerRuntime"
echo "  • BadgerApp"

if [[ "$RUN_TESTS" == true ]]; then
    echo ""
    if [[ "$TESTS_FAILED" == true ]]; then
        echo -e "${YELLOW}Test run completed with failures. Use --strict to fail on test errors.${NC}"
    elif [[ "$STRICT_MODE" == true ]]; then
        echo -e "${GREEN}All tests passed in strict mode!${NC}"
    else
        echo -e "${GREEN}All tests passed!${NC}"
    fi
fi

echo ""
echo -e "${YELLOW}Note: BadgerApp is a Swift package library.${NC}"
echo -e "${YELLOW}To create a full macOS app bundle, an Xcode project would be needed.${NC}"

# Exit with error code if tests failed in strict mode (for CI)
if [[ "$STRICT_MODE" == true && "$TESTS_FAILED" == true ]]; then
    exit 1
fi
