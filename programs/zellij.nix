{ config, pkgs, lib, ... }:

{
  # Zellij terminal multiplexer configuration
  home.file.".config/zellij/config.kdl" = {
    force = true;
    text = ''
      // Zellij configuration with iTerm2-like keybindings using Super (Cmd) key

      keybinds clear-defaults=true {
        // Normal mode - these work when you're just using the terminal
        normal {
          // Tab management
          bind "Super t" { NewTab; }
          bind "Super w" { CloseFocus; }
          bind "Super 1" { GoToTab 1; }
          bind "Super 2" { GoToTab 2; }
          bind "Super 3" { GoToTab 3; }
          bind "Super 4" { GoToTab 4; }
          bind "Super 5" { GoToTab 5; }
          bind "Super 6" { GoToTab 6; }
          bind "Super 7" { GoToTab 7; }
          bind "Super 8" { GoToTab 8; }
          bind "Super 9" { GoToTab 9; }

          // Tab navigation (since Cmd+1-9 often doesn't work on macOS)
          bind "Super Shift [" { GoToPreviousTab; }
          bind "Super Shift ]" { GoToNextTab; }

          // Tab organization
          bind "Super e" { SwitchToMode "RenameTab"; TabNameInput 0; }
          bind "Super Alt [" { MoveTab "Left"; }
          bind "Super Alt ]" { MoveTab "Right"; }

          // Tab cycling (alternative to Shift+[/])
          bind "Super Shift Up" { GoToPreviousTab; }
          bind "Super Shift Down" { GoToNextTab; }

          // Pane cycling (alternative to [/])
          bind "Super Shift Left" { FocusPreviousPane; }
          bind "Super Shift Right" { FocusNextPane; }

          // Pane management
          bind "Super d" { NewPane "Right"; }
          bind "Super Shift d" { NewPane "Down"; }
          bind "Super [" { FocusPreviousPane; }
          bind "Super ]" { FocusNextPane; }
          bind "Super Shift Enter" { ToggleFocusFullscreen; }
          bind "Super Shift b" { BreakPane; }
          bind "Super Shift f" { ToggleFloatingPanes; }

          // Enter pane mode for moving panes
          bind "Super p" { SwitchToMode "Pane"; }

          // Enter resize mode for resizing panes
          bind "Super r" { SwitchToMode "Resize"; }

          // Utility
          bind "Super k" { Clear; }
          bind "Super f" { SwitchToMode "EnterSearch"; SearchInput 0; }

          // Copy mode
          bind "Super Shift c" { SwitchToMode "Scroll"; }

          // Session management
          bind "Super s" {
            LaunchOrFocusPlugin "session-manager" {
              floating true
              move_to_focused_tab true
            };
          }
          bind "Super Shift s" { Detach; }
        }

        // Enter search mode - for typing search query
        entersearch {
          bind "Esc" { SwitchToMode "Normal"; }
          bind "Enter" { SwitchToMode "Search"; }
          bind "Ctrl c" { ScrollToBottom; SwitchToMode "Normal"; }
        }

        // Search mode - for navigating search results
        search {
          bind "Esc" { ScrollToBottom; SwitchToMode "Normal"; }
          bind "Enter" { SwitchToMode "Normal"; }
          bind "Super f" { SwitchToMode "Normal"; }
          bind "Ctrl c" { ScrollToBottom; SwitchToMode "Normal"; }
          bind "n" { Search "down"; }
          bind "Shift n" { Search "up"; }
          bind "p" { Search "up"; }
          bind "c" { SearchToggleOption "CaseSensitivity"; }
          bind "w" { SearchToggleOption "Wrap"; }
          bind "o" { SearchToggleOption "WholeWord"; }
        }

        // Scroll/copy mode
        scroll {
          bind "Esc" { SwitchToMode "Normal"; }
          bind "Ctrl c" { SwitchToMode "Normal"; }
          bind "q" { SwitchToMode "Normal"; }

          // Scrolling
          bind "j" { ScrollDown; }
          bind "k" { ScrollUp; }
          bind "Ctrl d" { HalfPageScrollDown; }
          bind "Ctrl u" { HalfPageScrollUp; }
          bind "Ctrl f" { PageScrollDown; }
          bind "Ctrl b" { PageScrollUp; }
          bind "d" { HalfPageScrollDown; }
          bind "u" { HalfPageScrollUp; }
          bind "PageDown" { PageScrollDown; }
          bind "PageUp" { PageScrollUp; }
          bind "Down" { ScrollDown; }
          bind "Up" { ScrollUp; }
          bind "Home" { ScrollToTop; }
          bind "End" { ScrollToBottom; }
          bind "g" { ScrollToTop; }
          bind "Shift g" { ScrollToBottom; }

          // Edit scrollback in editor
          bind "e" { EditScrollback; SwitchToMode "Normal"; }

          // Search from scroll mode
          bind "/" { SwitchToMode "EnterSearch"; SearchInput 0; }
          bind "Ctrl s" { SwitchToMode "EnterSearch"; SearchInput 0; }
        }

        // Session mode
        session {
          bind "Esc" { SwitchToMode "Normal"; }
          bind "Ctrl c" { SwitchToMode "Normal"; }
          bind "d" { Detach; }
          bind "w" {
            LaunchOrFocusPlugin "session-manager" {
              floating true
              move_to_focused_tab true
            };
            SwitchToMode "Normal"
          }
        }

        // Pane mode - for moving panes
        pane {
          bind "Esc" { SwitchToMode "Normal"; }
          bind "Ctrl c" { SwitchToMode "Normal"; }
          bind "Enter" { SwitchToMode "Normal"; }

          // Move focus
          bind "h" "Left" { MoveFocus "Left"; }
          bind "j" "Down" { MoveFocus "Down"; }
          bind "k" "Up" { MoveFocus "Up"; }
          bind "l" "Right" { MoveFocus "Right"; }

          // Move/swap pane position
          bind "Shift h" "Shift Left" { MovePane "Left"; }
          bind "Shift j" "Shift Down" { MovePane "Down"; }
          bind "Shift k" "Shift Up" { MovePane "Up"; }
          bind "Shift l" "Shift Right" { MovePane "Right"; }

          // Other pane actions
          bind "n" { NewPane; }
          bind "d" { NewPane "Down"; }
          bind "r" { NewPane "Right"; }
          bind "x" { CloseFocus; SwitchToMode "Normal"; }
          bind "f" { ToggleFocusFullscreen; SwitchToMode "Normal"; }
        }

        // Resize mode - separate mode just for resizing
        resize {
          bind "Esc" { SwitchToMode "Normal"; }
          bind "Ctrl c" { SwitchToMode "Normal"; }
          bind "Enter" { SwitchToMode "Normal"; }

          bind "h" "Left" { Resize "Increase Left"; }
          bind "j" "Down" { Resize "Increase Down"; }
          bind "k" "Up" { Resize "Increase Up"; }
          bind "l" "Right" { Resize "Increase Right"; }
          bind "=" "+" { Resize "Increase"; }
          bind "-" { Resize "Decrease"; }
        }

        // Rename tab mode - for renaming the current tab
        renametab {
          bind "Enter" { SwitchToMode "Normal"; }
          bind "Esc" { UndoRenameTab; SwitchToMode "Normal"; }
          bind "Ctrl c" { UndoRenameTab; SwitchToMode "Normal"; }
        }

        // Shared bindings across all modes
        shared {
          bind "Super q" { Quit; }
        }
      }

      // UI configuration
      pane_frames false
      default_layout "compact"

      // Theme
      theme "tokyo-night-storm"
    '';
  };
}
