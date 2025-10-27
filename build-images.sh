#!/bin/bash
set -e

echo "=================================="
echo "Building Blue/Green App Images"
echo "=================================="
echo ""

# Build blue app
echo "Building blue-app:local..."
docker build -t blue-app:local ./app
echo "✓ blue-app:local built successfully"
echo ""

# Build green app
echo "Building green-app:local..."
docker build -t green-app:local ./app
echo "✓ green-app:local built successfully"
echo ""

# Show images
echo "Built images:"
docker images | grep -E "REPOSITORY|blue-app|green-app"
echo ""

echo "=================================="
echo "✓ Build Complete"
echo "=================================="
echo ""
echo "Next steps:"
echo "  1. Start the stack:    docker-compose up -d"
echo "  2. Run verification:   ./verify-failover.sh"
echo "  3. View logs:          docker-compose logs -f"
