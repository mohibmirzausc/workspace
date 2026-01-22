{ config, pkgs, lib, ... }:

let
  raycastPlist = ./com.raycast.macos.xml;
  raycastConfig = ./settings.rayconfig;
in
{
  # Raycast Configuration Management
  #
  # This manages both the plist preferences and the .rayconfig file which includes
  # extensions, quicklinks, snippets, hotkeys, and all other Raycast data.
  #
  # To update your Raycast configuration:
  #   1. Make changes in Raycast (extensions, quicklinks, snippets, etc.)
  #   2. Export settings: Raycast → Settings → Advanced → Export Settings
  #   3. Save the exported .rayconfig as programs/raycast/settings.rayconfig
  #   4. Run: darwin-rebuild switch (or ./install.sh)
  #
  # To import on a new machine:
  #   - After running install.sh, manually import the settings:
  #   - Raycast → Settings → Advanced → Import Settings
  #   - Select: ~/.config/raycast/settings.rayconfig
  #
  # Note: Automatic import via CLI is not supported by Raycast yet.
  # The .rayconfig file must be manually imported through Raycast's UI.

  # Store the XML plist file for macOS preferences
  home.file.".config/raycast/com.raycast.macos.xml" = lib.mkIf pkgs.stdenv.isDarwin {
    source = raycastPlist;
  };

  # Store the .rayconfig file for extensions, quicklinks, snippets, etc.
  home.file.".config/raycast/settings.rayconfig" = lib.mkIf pkgs.stdenv.isDarwin {
    source = raycastConfig;
  };

  # Import plist preferences and remind user about .rayconfig
  home.activation.raycastPrefs = lib.mkIf pkgs.stdenv.isDarwin (lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="/usr/bin:/usr/libexec:/bin:$PATH"

    # Close Raycast if it's running so it doesn't overwrite
    /usr/bin/pkill -x "Raycast" || true
    sleep 0.5

    # Import the XML plist into the com.raycast.macos domain
    echo "Importing Raycast plist preferences from: ${raycastPlist}"
    /usr/bin/defaults import com.raycast.macos "${raycastPlist}"

    # Nuke the prefs cache so Finder/apps see updates
    /usr/bin/killall cfprefsd || true

    # Start Raycast
    echo "Starting Raycast..."
    /usr/bin/open -a Raycast

    echo ""
    echo "✓ Raycast plist preferences imported successfully!"
    echo ""
    echo "⚠️  IMPORTANT: Manual step required for complete setup:"
    echo "   Your .rayconfig file (extensions, quicklinks, snippets) is ready at:"
    echo "   ~/.config/raycast/settings.rayconfig"
    echo ""
    echo "   To import it:"
    echo "   1. Open Raycast"
    echo "   2. Go to Settings → Advanced → Import Settings"
    echo "   3. Select: ~/.config/raycast/settings.rayconfig"
    echo "   4. Enter the password when prompted (hint: sp9)"
    echo ""
    echo "   This will sync all your extensions, quicklinks, and snippets."
    echo ""
  '');
}

