#!/bin/bash
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "🔨 Compilando ultron-overlay nativo en Swift..."
swiftc -O "$DIR/main.swift" -o "$DIR/../ultron-overlay"
chmod +x "$DIR/../ultron-overlay"
echo "✅ Compilación exitosa: $DIR/../ultron-overlay"
