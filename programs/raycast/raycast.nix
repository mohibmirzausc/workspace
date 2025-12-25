{ config, pkgs, lib, ... }:

let
  raycastPlist = ./com.raycast.macos.xml;
in
{
  # Raycast configuration
  # Manage the plist file and import it on activation
  
  # Store the XML plist file for reference (optional)
  home.file.".config/raycast/com.raycast.macos.xml" = lib.mkIf pkgs.stdenv.isDarwin {
    source = raycastPlist;
  };
  
  # Import the plist into macOS preferences on activation
  home.activation.raycastPrefs = lib.mkIf pkgs.stdenv.isDarwin (lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="/usr/bin:/usr/libexec:/bin:$PATH"

    # Close Raycast if it's running so it doesn't overwrite
    /usr/bin/pkill -x "Raycast" || true
    sleep 0.5

    # Import the XML into the com.raycast.macos domain
    echo "Importing Raycast preferences..."
    /usr/bin/defaults import com.raycast.macos "${raycastPlist}"

    # Nuke the prefs cache so Finder/apps see updates
    /usr/bin/killall cfprefsd || true

    # Start Raycast
    echo "Starting Raycast..."
    /usr/bin/open -a Raycast
  '');
}

