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
                description = "Caps Lock → Super (ctrl+opt+cmd, no shift)";
                manipulators = [
                  {
                    type = "basic";
                    from = {
                      key_code = "caps_lock";
                      modifiers = {
                        optional = [ "any" ];
                      };
                    };
                    # ctrl+opt+cmd -- deliberately NOT full hyper. SHIFT IS
                    # EXCLUDED so it stays available as a discriminator:
                    # Caps Lock+N and Caps Lock+Shift+N are then genuinely
                    # different chords (see programs/omniwm/settings.toml, where
                    # they are switch-workspace vs move-window-to-workspace).
                    #
                    # Why this is safe -- the bug #54 fixed was NOT about shift
                    # being present. opt+shift+<letter> is not a plain keystroke
                    # on the US layout: macOS resolves it through the layout into
                    # a special character before any hotkey consumer sees a
                    # letter (opt+shift+g -> "˝", a DEAD KEY that commits no
                    # character, so Raycast recorded a chord it could never
                    # match). The fix was adding CONTROL: ctrl+<letter> yields a
                    # control character and bypasses layout resolution entirely.
                    # Shift was only along for the ride because "hyper"
                    # conventionally means all four modifiers.
                    #
                    # Re-verified with UCKeyTranslate against the live layout --
                    # ctrl+opt+cmd and ctrl+opt+cmd+shift are indistinguishable
                    # in output, and neither produces a dead key:
                    #
                    #   chord          G     J     C     S     digits
                    #   opt+shift      ˝     Ô     Ç     Í     (broken, #54)
                    #   ctrl+opt+cmd   ^G    ^J    ^C    ^S    1 2 3 4
                    #   + shift        ^G    ^J    ^C    ^S    1 2 3 4
                    #
                    # Caps Lock is a pure modifier: no to_if_alone, so a quick
                    # tap emits nothing rather than Escape. Escape stays on its
                    # own key.
                    #
                    # lazy is deliberately NOT set. It existed to stop a fast
                    # Caps Lock+<key> press from resolving Caps Lock as "alone"
                    # and firing Escape while the letter went out bare. With no
                    # alone-branch there is no race to lose, and lazy would only
                    # delay asserting the modifier until another key joins --
                    # which is what drops fast chords.
                    #
                    # right_control carries the chord as the KEY; option and
                    # command ride along as modifiers. (Previously right_shift
                    # was the key -- that is what made "Caps Lock + left shift"
                    # unexpressible, since macOS reports one shift FLAG no
                    # matter how many shift keys are down.)
                    to = [
                      {
                        key_code = "right_control";
                        modifiers = [ "right_option" "right_command" ];
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
            # Logitech MX Anywhere 2S (Bluetooth LE): deliberately NOT grabbed.
            # Its scroll flip, tilt wheel and side button all live in
            # programs/linearmouse.json instead, because the tilt cannot be
            # done here: over BLE it emits horizontal scroll (HID AC Pan), not
            # a button, repeating every ~100ms from the first event -- even a
            # quick tap sends two. Karabiner cannot take a wheel event as a
            # `from`, and a scroll->key mapping would fire a hotkey per event.
            # LinearMouse instead diverts the tilt over HID++ (controls 0x5B /
            # 0x5D), turning it into one press/release. That needs LinearMouse
            # to reach the physical device, so grabbing it here (ignore =
            # false) would silently break the tilt mapping.
            {
              identifiers = {
                is_keyboard = true;
                is_pointing_device = true;
                product_id = 45082;
                vendor_id = 1133;
              };
              ignore = true;
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

  # Force Karabiner to re-read karabiner.json after activation.
  #
  # Karabiner watches the config file for changes, but home-manager installs it
  # by swapping the SYMLINK at that path to a new nix-store target. That does
  # not modify the file Karabiner is watching, so the watcher never fires and
  # the daemon keeps enforcing the PREVIOUS config -- silently, with no error
  # and nothing in its log. Symptom: you rebuild, the JSON on disk is correct,
  # and your keys still behave the old way until something unrelated (a reboot,
  # a sleep/wake cycle) happens to restart the service.
  #
  # That cost a long debugging session: Karabiner's log showed its last config
  # load at 00:31 while the rebuild had written at 00:35, so a whole batch of
  # hotkey changes appeared to do nothing.
  #
  # kickstart -k restarts the console user server, which reloads the config on
  # startup. Only the user-level agent is touched; the root Core-Service and the
  # DriverKit extension are left alone, so this does not disturb the virtual HID
  # device or require any privilege.
  home.activation.reloadKarabiner = lib.mkIf pkgs.stdenv.isDarwin
    (lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      KB_AGENT="gui/$(id -u)/org.pqrs.service.agent.Karabiner-Console-User-Server"

      # Only if Karabiner is actually installed and the agent is loaded --
      # otherwise this is a no-op (e.g. a fresh machine before the cask lands).
      if /bin/launchctl print "$KB_AGENT" >/dev/null 2>&1; then
        $DRY_RUN_CMD /bin/launchctl kickstart -k "$KB_AGENT" || \
          echo "warning: could not reload Karabiner; its config may be stale until restart"
      fi
    '');
}

