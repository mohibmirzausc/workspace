#!/bin/bash
# Shell function wrapper for find-claude-session that preserves directory changes
# 
# To use this, add the following line to your ~/.bashrc or ~/.zshrc:
#   source /path/to/claude-code-tools/scripts/fcs-function.sh
#
# Then use 'fcs' instead of 'find-claude-session' to have directory changes persist

fcs() {
    # Check if user is asking for help
    if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        find-claude-session --help
        return
    fi
    
    # Run find-claude-session in shell mode and evaluate the output
    # Use sed to remove any leading empty lines that might cause issues
    eval "$(find-claude-session --shell "$@" | sed '/^$/d')"
}