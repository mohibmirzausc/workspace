# Vault - Encrypted .env Backup Manager

## Overview

The `vault` tool provides centralized, encrypted backup for `.env` files across
all your projects. It uses SOPS (Secrets OPerationS) with GPG encryption to
securely store your environment variables in a central location at
`~/Git/dotenvs/`.

## How It Works

1. **Central Storage**: All encrypted backups are stored in `~/Git/dotenvs/`
2. **Project-based**: Each project's `.env` file is backed up with the project
   directory name (e.g., `myproject.env.encrypt`)
3. **GPG Encryption**: Uses your GPG key to encrypt/decrypt files
4. **Smart Sync**: Automatically detects which version is newer and syncs
   appropriately
5. **Safety First**: Always creates timestamped backups before overwriting

## Requirements

- GPG key configured on your system
- SOPS installed (`brew install sops` on macOS)

## Commands

### vault sync

Smart synchronization that automatically detects the sync direction:
- If only local `.env` exists → encrypts to vault
- If only vault backup exists → decrypts to local
- If local is newer → encrypts to vault (with confirmation)
- If vault is newer → decrypts to local (with confirmation)

```bash
vault sync           # Auto-detect direction
vault sync --push    # Force encrypt (local → vault)
vault sync --pull    # Force decrypt (vault → local)
```

### vault encrypt

Explicitly encrypt your local `.env` file to the centralized vault:

```bash
vault encrypt
```

Features:
- Creates timestamped backup if encrypted file already exists
- Requires confirmation before overwriting existing backups

### vault decrypt

Explicitly decrypt from the centralized vault to local `.env`:

```bash
vault decrypt
```

Features:
- Creates timestamped backup of current `.env` before overwriting
- Warns if local `.env` is newer than backup
- Requires confirmation in case of conflicts

### vault list

List all encrypted backups in the central vault:

```bash
vault list
```

Shows all `.env.encrypt` files in `~/Git/dotenvs/` with their sizes.

### vault status

Show detailed status for the current project:

```bash
vault status
```

Displays:
- Whether local `.env` exists
- Whether backup exists
- Which version is newer (with timestamps)
- Sync status (in sync, local newer, backup newer, etc.)

## Workflow Examples

### Initial Setup

```bash
cd myproject
# Create your .env file with secrets
vault encrypt  # Backup to central vault
```

### Cloning a Project

```bash
git clone https://github.com/user/project
cd project
vault decrypt  # Restore .env from central vault
```

### Regular Development

```bash
# After modifying .env
vault sync  # Automatically encrypts to vault

# On a different machine
vault sync  # Automatically decrypts newer version
```

### Conflict Resolution

When both local and vault versions exist but differ:

```bash
vault status  # Check which is newer
vault sync --push  # Force local → vault
vault sync --pull  # Force vault → local
```

## Security Notes

- Files are encrypted using your GPG key
- Only you can decrypt the files (with your private key)
- The central vault (`~/Git/dotenvs/`) should be included in your backups
- Consider version controlling the encrypted files for additional safety

## Troubleshooting

### "No GPG key found"

Generate a GPG key:
```bash
gpg --gen-key
```

### "SOPS not found"

Install SOPS:
```bash
# macOS
brew install sops

# Linux
# Download from https://github.com/mozilla/sops/releases
```

### Permission Issues

Ensure you have write access to `~/Git/dotenvs/`:
```bash
mkdir -p ~/Git/dotenvs
chmod 700 ~/Git/dotenvs
```