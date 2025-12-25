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
                description = "Caps Lock → Option+Shift (held) or Escape (alone)";
                manipulators = [
                  {
                    type = "basic";
                    from = {
                      key_code = "caps_lock";
                      modifiers = {
                        optional = [ "any" ];
                      };
                    };
                    to = [
                      {
                        key_code = "right_shift";
                        modifiers = [ "right_option" ];
                      }
                    ];
                    to_if_alone = [
                      {
                        key_code = "escape";
                      }
                    ];
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
                    to = [
                      {
                        key_code = "up_arrow";
                        modifiers = [ "control" ];
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
              to = [
                {
                  key_code = "up_arrow";
                  modifiers = [ "control" ];
                }
              ];
            }
          ];
        }
      ];
    };
  };
}

