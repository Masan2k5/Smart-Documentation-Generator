#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1
echo "Running from: $SCRIPT_DIR"


# Full pipeline of Smart Documentation Generator
# This script runs the entire pipeline from C++ to website

echo "***********************************************"
echo "Smart Documentation Generator"
echo "Full Pipeline"
echo "***********************************************"
echo ""

START_TIME=$(date +%s)

echo "C++ parser is being run..."
cd "$SCRIPT_DIR/build" || exit 1
if [ -f "./parser" ]; then
  ./parser ../sample_project
  echo "   C++ parser is successfully complete"
else
  echo "   C++ parser not found. Build it first with: cd build && cmake .. && make"
fi
echo ""

echo "Running Python AI generator is being run..."
cd "$SCRIPT_DIR/python_ai" || exit 1
if [ -d "venv" ]; then
  source venv/bin/activate
  python3 generate_docs.py
  deactivate
  echo "   Python generator is successfully complete"
else
  echo "   Python venv not found. Run: python3 -m venv venv && pip install -r requirements.txt"
fi
echo ""

echo "R analytics is being run..."
cd "$SCRIPT_DIR/r_analytics" || exit 1

if command -v Rscript &> /dev/null; then
    Rscript analyze_docs.R
    Rscript -e "rmarkdown::render('report.Rmd')"
    echo "   R analytics is successfully complete"
    
    echo "   Waiting for report.html to be ready..."
    MAX_WAIT=5
    WAITED=0
    while [ $WAITED -lt $MAX_WAIT ]; do
        if [ -f "report.html" ] && [ $(wc -c < "report.html") -gt 1000 ]; then
            echo "   report.html is ready ($(wc -c < "report.html") bytes)"
            break
        fi
        sleep 1
        WAITED=$((WAITED + 1))
    done
else
    echo "   Rscript not found. Install R first."
fi
echo ""

echo "R report is being copied to website..."

mkdir -p "$SCRIPT_DIR/website/docs/reports"

if [ -f "$SCRIPT_DIR/r_analytics/report.html" ]; then
    SIZE=$(wc -c < "$SCRIPT_DIR/r_analytics/report.html")
    echo "   Found report.html ($SIZE bytes)"
    
    cp "$SCRIPT_DIR/r_analytics/report.html" "$SCRIPT_DIR/website/docs/reports/"
    
    if [ -f "$SCRIPT_DIR/website/docs/reports/report.html" ]; then
        COPY_SIZE=$(wc -c < "$SCRIPT_DIR/website/docs/reports/report.html")
        echo "   Copied successfully ($COPY_SIZE bytes)"
        
        if [ "$SIZE" -eq "$COPY_SIZE" ]; then
            echo "   File sizes match"
        else
            echo "   File size mismatch! Source: $SIZE, Copy: $COPY_SIZE"
        fi
    else
        echo "   Copy failed - file not found after copy"
    fi
else
    echo "   report.html not found at $SCRIPT_DIR/r_analytics/report.html"
    echo "      Contents of r_analytics:"
    ls -la "$SCRIPT_DIR/r_analytics/"
fi

echo "   PNG files are being copied..."
png_count=0
for png_file in "$SCRIPT_DIR/r_analytics/"*.png; do
    if [ -f "$png_file" ]; then
        cp "$png_file" "$SCRIPT_DIR/website/docs/reports/"
        png_count=$((png_count + 1))
        echo "      Copied $(basename "$png_file")"
    fi
done
echo "   Successfully copied $png_count PNG files"

echo "   Files found in website/docs/reports:"
ls -la "$SCRIPT_DIR/website/docs/reports/"

echo "Website is being built..."
cd "$SCRIPT_DIR/website" || exit 1
if [ -f "./build_site.sh" ]; then
  ./build_site.sh
else
  echo "   build_site.sh not found. Creating it first..."
  cat > build_site.sh << 'EOF'
#!/bin/bash
echo "Building website..."
mkdocs build
echo "Website is successfully built"
EOF
  chmod +x build_site.sh
  ./build_site.sh
fi
echo ""

END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))
MINUTES=$((TOTAL_TIME / 60))
SECONDS=$((TOTAL_TIME % 60))

echo "***********************************************"
echo "Pipeline is fully completed"
echo "***********************************************"
echo "Total time: ${MINUTES}m ${SECONDS}s"
echo "Website available at: $(pwd)/site/index.html"
echo ""
echo "To view the site:"
echo "  cd website && mkdocs serve"
echo "  or open site/index.html"
echo "***********************************************"