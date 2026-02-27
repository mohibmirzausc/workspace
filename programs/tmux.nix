{ config, pkgs, lib, ... }:

{
  # tmux configuration with direct Cmd+key bindings (no prefix needed by user)
  #
  # How it works:
  # Ghostty sends Ctrl-Space (\x00) + key for each Cmd+key press.
  # tmux prefix is Ctrl-Space, so it interprets this as prefix+key automatically.
  # You just press Cmd+t and tmux creates a new window. No manual prefix.

  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    baseIndex = 1;
    escapeTime = 0;
    mouse = true;
    keyMode = "vi";
    historyLimit = 50000;

    extraConfig = ''
      # ── General ──────────────────────────────────────────────────────
      set -g renumber-windows on
      set -g set-titles on
      set -g focus-events on
      set -g pane-base-index 1
      set -as terminal-features ',xterm-ghostty:RGB'

      # ── Prefix: Ctrl-Space (injected by Ghostty for Cmd+key) ────────
      unbind C-b
      set -g prefix C-Space
      bind C-Space send-prefix

      # ── Status bar (compact, like Zellij compact layout) ────────────
      set -g status-position bottom
      set -g status-style 'bg=default,fg=white'
      set -g status-left '#[fg=blue,bold]#S #[fg=default]'
      set -g status-left-length 20
      set -g status-right '#[fg=brightblack]%H:%M'
      set -g window-status-format '#[fg=brightblack] #I:#W '
      set -g window-status-current-format '#[fg=blue,bold] #I:#W '
      set -g window-status-separator ""

      # ── Pane borders ────────────────────────────────────────────────
      set -g pane-border-lines simple
      set -g pane-border-style 'fg=brightblack'
      set -g pane-active-border-style 'fg=blue'

      # ── Window (tab) management ─────────────────────────────────────
      # Cmd+t / Cmd+w / Cmd+1-9 / Cmd+Shift+[/] / Cmd+e
      bind t new-window -c "#{pane_current_path}"
      bind w kill-pane
      bind 1 select-window -t :1
      bind 2 select-window -t :2
      bind 3 select-window -t :3
      bind 4 select-window -t :4
      bind 5 select-window -t :5
      bind 6 select-window -t :6
      bind 7 select-window -t :7
      bind 8 select-window -t :8
      bind 9 select-window -t :9
      bind '{' previous-window
      bind '}' next-window
      bind e command-prompt -I "#W" "rename-window '%%'"

      # ── Pane management ─────────────────────────────────────────────
      # Cmd+d / Cmd+Shift+d / Cmd+[/] / Cmd+Shift+Enter
      bind d split-window -h -c "#{pane_current_path}"
      bind D split-window -v -c "#{pane_current_path}"
      bind [ select-pane -t :.-
      bind ] select-pane -t :.+
      bind Enter resize-pane -Z

      # Cmd+Shift+b (break pane to its own tab)
      # Cmd+Shift+j (join: pick a window to merge this pane into)
      # Cmd+Shift+f (popup)
      bind B break-pane
      bind J choose-window "join-pane -t '%%'"
      bind F display-popup -E -w 80% -h 80% -d "#{pane_current_path}"

      # ── Pane mode (Cmd+p -> h/j/k/l to navigate/move) ──────────────
      bind p switch-client -T pane-mode

      bind -T pane-mode h select-pane -L
      bind -T pane-mode j select-pane -D
      bind -T pane-mode k select-pane -U
      bind -T pane-mode l select-pane -R
      bind -T pane-mode Left select-pane -L
      bind -T pane-mode Down select-pane -D
      bind -T pane-mode Up select-pane -U
      bind -T pane-mode Right select-pane -R
      bind -T pane-mode H swap-pane -d -t '{left-of}'
      bind -T pane-mode J swap-pane -d -t '{down-of}'
      bind -T pane-mode K swap-pane -d -t '{up-of}'
      bind -T pane-mode L swap-pane -d -t '{right-of}'
      bind -T pane-mode n split-window -c "#{pane_current_path}"
      bind -T pane-mode d split-window -v -c "#{pane_current_path}"
      bind -T pane-mode r split-window -h -c "#{pane_current_path}"
      bind -T pane-mode x kill-pane
      bind -T pane-mode f resize-pane -Z
      bind -T pane-mode Escape switch-client -T prefix

      # ── Resize mode (Cmd+r -> h/j/k/l to resize) ───────────────────
      bind r switch-client -T resize-mode

      bind -T resize-mode h resize-pane -L 5
      bind -T resize-mode j resize-pane -D 5
      bind -T resize-mode k resize-pane -U 5
      bind -T resize-mode l resize-pane -R 5
      bind -T resize-mode Left resize-pane -L 5
      bind -T resize-mode Down resize-pane -D 5
      bind -T resize-mode Up resize-pane -U 5
      bind -T resize-mode Right resize-pane -R 5
      bind -T resize-mode = resize-pane -Z
      bind -T resize-mode - resize-pane -x 50%
      bind -T resize-mode Escape switch-client -T prefix

      # ── Utility ─────────────────────────────────────────────────────
      # Cmd+k (clear) / Cmd+f (search) / Cmd+Shift+c (copy mode)
      bind k send-keys C-l \; clear-history
      bind f copy-mode \; send-keys /
      bind C copy-mode

      # ── Session management ──────────────────────────────────────────
      # Cmd+s (picker) / Cmd+Shift+s (detach) / Cmd+q (quit)
      bind s choose-tree -s
      bind S detach-client
      bind q confirm-before -p "Kill session #S? (y/n)" kill-session

      # ── Copy mode (vi-style) ────────────────────────────────────────
      bind -T copy-mode-vi v send-keys -X begin-selection
      bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "pbcopy"
      bind -T copy-mode-vi Escape send-keys -X cancel
      bind -T copy-mode-vi q send-keys -X cancel
    '';
  };
}
