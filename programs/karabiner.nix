{ config, pkgs, lib, ... }:

{
  # Karabiner-Elements configuration
  # Complex modification rules are stored in ~/.config/karabiner/assets/complex_modifications/

  # Swap left Control and Command for external keyboards only
  home.file.".config/karabiner/karabiner.json" = lib.mkIf pkgs.stdenv.isDarwin {
    force = true;  # Overwrite existing manual configuration
    text = builtins.toJSON {
      profiles = [
        {
          name = "Default profile";
          selected = true;

          # Profile-level: swap left Control and Command (applies to all by default)
          simple_modifications = [
            {
              from = { key_code = "left_control"; };
              to = [{ key_code = "left_command"; }];
            }
            {
              from = { key_code = "left_command"; };
              to = [{ key_code = "left_control"; }];
            }
          ];

          # Complex modifications (enabled rules)
          complex_modifications = {
            rules = [
              {
                description = "Caps Lock → Hyper";
                manipulators = [
                  {
                    type = "basic";
                    from = {
                      key_code = "caps_lock";
                      modifiers = {
                        optional = [ "any" ];
                      };
                    };
                    # Hyper (ctrl+opt+shift+cmd) rather than opt+shift.
                    #
                    # opt+shift+<letter> is NOT a plain keystroke on the US
                    # layout: macOS resolves it to a special character before any
                    # hotkey consumer sees a letter. Verified via UCKeyTranslate
                    # against the live layout: opt+shift+g -> "˝", which is a
                    # DEAD KEY (commits no character on its own), so Raycast
                    # records a degenerate chord and never matches it. Adding
                    # ctrl+cmd means no letter resolves to a character at all.
                    #
                    # Caps Lock is a pure Hyper modifier: no to_if_alone, so a
                    # quick tap emits nothing at all rather than Escape. Escape
                    # remains on its own key.
                    #
                    # lazy is deliberately NOT set here. It exists to stop a
                    # fast Caps Lock+<key> press from resolving Caps Lock as
                    # "alone" and firing Escape while the letter goes out bare.
                    # With to_if_alone gone there is no alone-branch to lose the
                    # race to, and lazy would only delay asserting the modifier
                    # until another key joins -- which is what drops fast chords.
                    # So the modifier now asserts immediately on key-down.
                    to = [
                      {
                        key_code = "right_shift";
                        modifiers = [ "right_option" "right_control" "right_command" ];
                      }
                    ];
                    # No basic.to_if_alone_timeout_milliseconds either: with no
                    # alone-branch there is no alone-vs-held threshold to pin.
                  }
                ];
              }
              {
                description = "Side button → Mission Control";
                manipulators = [
                  {
                    type = "basic";
                    from = {
                      pointing_button = "button4";
                    };
                    # Use the dedicated mission_control key rather than
                    # control+up_arrow: the latter depends on symbolic hotkey 32,
                    # which is absent from com.apple.symbolichotkeys on this
                    # machine (every ID present is enabled=false), so the chord
                    # resolves to nothing. mission_control needs no such binding.
                    to = [
                      {
                        key_code = "mission_control";
                      }
                    ];
                  }
                ];
              }
            ];
          };

          # Device-specific overrides
          devices = [
            # Generic keyboards: cancel the swap with no-op mappings
            {
              identifiers = {
                is_keyboard = true;
              };
              manipulate_caps_lock_led = false;
              simple_modifications = [
                {
                  from = { key_code = "left_command"; };
                  to = [{ key_code = "left_command"; }];
                }
                {
                  from = { key_code = "left_control"; };
                  to = [{ key_code = "left_control"; }];
                }
              ];
            }
            # Apple Internal Keyboard: no modifications
            {
              identifiers = {
                is_keyboard = true;
                product_id = 641;
                vendor_id = 1452;
              };
              manipulate_caps_lock_led = false;
            }
            # Mouse device with wheel flip
            {
              identifiers = {
                is_pointing_device = true;
                product_id = 64518; # Tecknet Wireless Rechargeable Mouse Model: TK-MS009 (change if different mouse is used)
                vendor_id = 13652; 
              };
              ignore = false;
              mouse_flip_horizontal_wheel = true;
              mouse_flip_vertical_wheel = true;
            }
          ];

          virtual_hid_keyboard = {
            keyboard_type_v2 = "ansi";
          };
        }
      ];
    };
  };

  home.file.".config/karabiner/assets/complex_modifications/mouse_side_button.json" = lib.mkIf pkgs.stdenv.isDarwin {
    text = builtins.toJSON {
      title = "Mouse Side Button Modifications";
      rules = [
        {
          description = "Side button → Mission Control";
          manipulators = [
            {
              type = "basic";
              from = {
                pointing_button = "button4";
              };
              # Keep in sync with the inline rule above.
              to = [
                {
                  key_code = "mission_control";
                }
              ];
            }
          ];
        }
      ];
    };
  };
}

