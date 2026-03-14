#!/bin/bash

# Build script of Smart Documentation Generator
# This script copies all generated content to the website folder

echo "***********************************************"
echo "Smart Documentation Generator is being built..."
echo "***********************************************"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEBSITE_DIR="$PROJECT_ROOT/website"
DOCS_DIR="$WEBSITE_DIR/docs"
PYTHON_OUTPUT="$PROJECT_ROOT/output/markdown"
R_ANALYTICS="$PROJECT_ROOT/r_analytics"
BUILD_DIR="$PROJECT_ROOT/build"

echo "📁 Project root: $PROJECT_ROOT"
echo ""

echo "Old documentation is being cleaned..."
rm -rf "$DOCS_DIR/documentation"
rm -rf "$DOCS_DIR/assets/images"
rm -rf "$DOCS_DIR/assets/diagrams"
rm -rf "$DOCS_DIR/assets/data"
mkdir -p "$DOCS_DIR/documentation"
mkdir -p "$DOCS_DIR/assets/images"
mkdir -p "$DOCS_DIR/assets/diagrams"
mkdir -p "$DOCS_DIR/assets/data"
echo "   Cleaning successful"
echo ""

echo "Generated documentation is being copied..."
if [ -d "$PYTHON_OUTPUT" ]; then
  cp "$PYTHON_OUTPUT"/*.md "$DOCS_DIR/documentation/" 2>/dev/null
  MD_COUNT=$(find "$DOCS_DIR/documentation" -name "*.md" | wc -l | xargs)
  echo "   Successfully copied $MD_COUNT markdown files"
  
  if [ -f "$DOCS_DIR/documentation/index.md" ]; then
    mv "$DOCS_DIR/documentation/index.md" "$DOCS_DIR/documentation/README.md"
    echo "   index.md is renamed to README.md"
  fi
else
  echo "   No markdown files found in $PYTHON_OUTPUT"
fi
echo ""

echo "Analytics report is being copied..."
if [ -f "$R_ANALYTICS/report.html" ]; then
  cp "$R_ANALYTICS/report.html" "$DOCS_DIR/analytics.html"
  echo "   Analytics report is successfully copied."
  
  cp "$R_ANALYTICS/report.html" "$DOCS_DIR/assets/data/"
else
  echo "   No analytics report found at $R_ANALYTICS/report.html"
fi
echo ""

echo "Analytics plots are being copied..."
if [ -d "$R_ANALYTICS/plots" ]; then
  cp -r "$R_ANALYTICS/plots"/*.png "$DOCS_DIR/assets/images/" 2>/dev/null
  PNG_COUNT=$(find "$DOCS_DIR/assets/images" -name "*.png" | wc -l | xargs)
  echo "   Successfully copied $PNG_COUNT images"
else
  echo "   No plots found in $R_ANALYTICS/plots"
fi
echo ""

echo "JSON data is being copied..."
if [ -f "$BUILD_DIR/code_analysis.json" ]; then
  cp "$BUILD_DIR/code_analysis.json" "$DOCS_DIR/assets/data/"
  echo "   Successfully copied code_analysis.json"
fi
if [ -f "$PROJECT_ROOT/output/statistics.json" ]; then
  cp "$PROJECT_ROOT/output/statistics.json" "$DOCS_DIR/assets/data/"
  echo "   Successfully copied statistics.json"
fi
echo ""

echo "Mermaid diagrams are being copied..."
if ls "$PYTHON_OUTPUT"/*.mmd 1> /dev/null 2>&1; then
  cp "$PYTHON_OUTPUT"/*.mmd "$DOCS_DIR/assets/diagrams/" 2>/dev/null
  MMD_COUNT=$(find "$DOCS_DIR/assets/diagrams" -name "*.mmd" | wc -l | xargs)
  echo "   Successfully copied $MMD_COUNT diagrams"
else
  echo "   No Mermaid diagrams found"
fi
echo ""

echo "Date in homepage is being updated..."
if [ -f "$DOCS_DIR/index.md" ]; then
  CURRENT_DATE=$(date '+%B %d, %Y')
  sed -i '' "s/{date}/$CURRENT_DATE/g" "$DOCS_DIR/index.md" 2>/dev/null
  echo "   Successfully updated date to $CURRENT_DATE"
else
  echo "   Homepage not found at $DOCS_DIR/index.md"
fi
echo ""

echo "MkDocs site is being built..."
cd "$WEBSITE_DIR"
mkdocs build
BUILD_STATUS=$?

if [ $BUILD_STATUS -eq 0 ]; then
  echo "   Site is built successfully"
else
  echo "   Site building failed"
fi
echo ""

echo "***********************************************"
echo "Build Summary"
echo "***********************************************"
echo "Markdown files: $(find "$DOCS_DIR/documentation" -name "*.md" 2>/dev/null | wc -l | xargs)"
echo "Images: $(find "$DOCS_DIR/assets/images" -name "*.png" 2>/dev/null | wc -l | xargs)"
echo "HTML files: $(find "$DOCS_DIR" -name "*.html" 2>/dev/null | wc -l | xargs)"
echo "Site size: $(du -sh "$WEBSITE_DIR/site" 2>/dev/null | cut -f1)"
echo ""
echo "Build complete. Site is ready at: $WEBSITE_DIR/site"
echo "***********************************************"