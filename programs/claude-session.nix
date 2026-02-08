{ pkgs }:

pkgs.writeShellScriptBin "claude-session" ''
  #!/usr/bin/env bash

  SESSION_PREFIX="claude"
  TMUX_SOCKET="claude-sessions"

  usage() {
      cat <<EOF
  Usage: claude-session <command> [arguments]

  Commands:
      new <name> [directory]  Create a new Claude Code session
      attach <name>           Attach to an existing Claude session
      list                    List all Claude sessions
      kill <name>             Kill a specific Claude session
      killall                 Kill all Claude sessions
      status                  Show status of all Claude sessions

  Examples:
      claude-session new myproject ~/projects/myproject
      claude-session attach myproject
      claude-session list
      claude-session kill myproject
  EOF
  }

  create_session() {
      local name="$1"
      local directory="''${2:-$PWD}"
      local session_name="''${SESSION_PREFIX}-''${name}"

      if ! [ -d "$directory" ]; then
          echo "Error: Directory '$directory' does not exist"
          return 1
      fi

      if ${pkgs.tmux}/bin/tmux -L "$TMUX_SOCKET" has-session -t "$session_name" 2>/dev/null; then
          echo "Session '$name' already exists. Use 'claude-session attach $name' to connect."
          return 1
      fi

      ${pkgs.tmux}/bin/tmux -L "$TMUX_SOCKET" new-session -d -s "$session_name" -c "$directory"
      ${pkgs.tmux}/bin/tmux -L "$TMUX_SOCKET" send-keys -t "$session_name" "claude" Enter

      echo "Created Claude session '$name' in directory: $directory"
      echo "Attaching to session..."
      ${pkgs.tmux}/bin/tmux -L "$TMUX_SOCKET" attach-session -t "$session_name"
  }

  attach_session() {
      local name="$1"
      local session_name="''${SESSION_PREFIX}-''${name}"

      if ! ${pkgs.tmux}/bin/tmux -L "$TMUX_SOCKET" has-session -t "$session_name" 2>/dev/null; then
          echo "Error: Session '$name' does not exist"
          echo "Available sessions:"
          list_sessions
          return 1
      fi

      ${pkgs.tmux}/bin/tmux -L "$TMUX_SOCKET" attach-session -t "$session_name"
  }

  list_sessions() {
      if ! ${pkgs.tmux}/bin/tmux -L "$TMUX_SOCKET" list-sessions 2>/dev/null | grep -q "^''${SESSION_PREFIX}-"; then
          echo "No Claude sessions found"
          return 0
      fi

      echo "Active Claude sessions:"
      ${pkgs.tmux}/bin/tmux -L "$TMUX_SOCKET" list-sessions 2>/dev/null | grep "^''${SESSION_PREFIX}-" | while IFS=: read -r session rest; do
          local name="''${session#''${SESSION_PREFIX}-}"
          echo "  - $name"
      done
  }

  kill_session() {
      local name="$1"
      local session_name="''${SESSION_PREFIX}-''${name}"

      if ! ${pkgs.tmux}/bin/tmux -L "$TMUX_SOCKET" has-session -t "$session_name" 2>/dev/null; then
          echo "Error: Session '$name' does not exist"
          return 1
      fi

      ${pkgs.tmux}/bin/tmux -L "$TMUX_SOCKET" kill-session -t "$session_name"
      echo "Killed Claude session '$name'"
  }

  kill_all_sessions() {
      local sessions=$(${pkgs.tmux}/bin/tmux -L "$TMUX_SOCKET" list-sessions 2>/dev/null | grep "^''${SESSION_PREFIX}-" | cut -d: -f1)

      if [ -z "$sessions" ]; then
          echo "No Claude sessions to kill"
          return 0
      fi

      echo "Killing all Claude sessions..."
      echo "$sessions" | while read -r session; do
          ${pkgs.tmux}/bin/tmux -L "$TMUX_SOCKET" kill-session -t "$session"
          local name="''${session#''${SESSION_PREFIX}-}"
          echo "  Killed: $name"
      done
  }

  show_status() {
      if ! ${pkgs.tmux}/bin/tmux -L "$TMUX_SOCKET" list-sessions 2>/dev/null | grep -q "^''${SESSION_PREFIX}-"; then
          echo "No active Claude sessions"
          return 0
      fi

      echo "Claude Session Status:"
      echo "----------------------"
      ${pkgs.tmux}/bin/tmux -L "$TMUX_SOCKET" list-sessions 2>/dev/null | grep "^''${SESSION_PREFIX}-" | while IFS=: read -r session rest; do
          local name="''${session#''${SESSION_PREFIX}-}"
          local info=$(echo "$rest" | sed 's/^ *//')
          echo "Session: $name"
          echo "  Info: $info"
          echo ""
      done
  }

  case "''${1:-}" in
      new)
          if [ -z "''${2:-}" ]; then
              echo "Error: Session name required"
              echo "Usage: claude-session new <name> [directory]"
              exit 1
          fi
          create_session "$2" "''${3:-}"
          ;;
      attach)
          if [ -z "''${2:-}" ]; then
              echo "Error: Session name required"
              echo "Usage: claude-session attach <name>"
              exit 1
          fi
          attach_session "$2"
          ;;
      list|ls)
          list_sessions
          ;;
      kill)
          if [ -z "''${2:-}" ]; then
              echo "Error: Session name required"
              echo "Usage: claude-session kill <name>"
              exit 1
          fi
          kill_session "$2"
          ;;
      killall)
          kill_all_sessions
          ;;
      status)
          show_status
          ;;
      -h|--help|help|"")
          usage
          ;;
      *)
          echo "Error: Unknown command '$1'"
          echo ""
          usage
          exit 1
          ;;
  esac
''
