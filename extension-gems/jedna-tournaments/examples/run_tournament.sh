#!/bin/bash

# Run tournament with parallel processing
# Usage: ./run_tournament.sh [config_file]

CONFIG=${1:-tournament_4k.yaml}

echo "🏁 Starting tournament with config: $CONFIG"
echo "📅 Start time: $(date)"
echo

# Clean up any previous runs
if [ -d "results_4k" ]; then
    echo "⚠️  Cleaning up previous results..."
    rm -rf results_4k
fi

# Run the tournament, suppressing debug output
echo "🚀 Running tournament..."
ruby parallel_tournament_runner.rb "$CONFIG" 2>&1 | grep -v "DEBUG\|GAME\|TO " | grep -v "^$"

# Check if successful
if [ $? -eq 0 ]; then
    echo
    echo "✅ Tournament completed successfully!"
    echo "📅 End time: $(date)"
    
    # Display results if they exist
    if [ -f "results_4k/merged/tournament_summary.txt" ]; then
        echo
        echo "📊 Tournament Results:"
        echo "=" * 60
        cat results_4k/merged/tournament_summary.txt
    fi
else
    echo "❌ Tournament failed!"
    exit 1
fi