# Dotfiles Configuration Guide

## Quick Start

1. Copy the example configuration:
   ```bash
   cp .dotfiles.conf.example ~/.dotfiles.conf
   ```

2. Edit `~/.dotfiles.conf` with your settings:
   ```bash
   nano ~/.dotfiles.conf
   # or
   vim ~/.dotfiles.conf
   ```

3. Run dotfiles:
   ```bash
   ./bin/dotfiles
   ```

## Configuration Options

### Git Repository Settings

**For Private Repositories:**
```bash
DOTFILES_REPO="git@github.com:yourusername/dotfiles.git"
DOTFILES_REPO_HTTPS="https://github.com/yourusername/dotfiles.git"
```

**Using Environment Variables:**
```bash
DOTFILES_REPO="git@gitlab.com:user/dotfiles.git" ./bin/dotfiles
```

**Using Different Branch:**
```bash
DOTFILES_BRANCH="develop"  # Test changes on develop branch
```

### Locale Configuration

Example for US English with metric system:
```bash
LOCALE_LANG="en_US.UTF-8"
LOCALE_NUMERIC="en_US.UTF-8"
LOCALE_TIME="en_US.UTF-8"
LOCALE_MONETARY="en_US.UTF-8"
LOCALE_PAPER="en_US.UTF-8"
LOCALE_MEASUREMENT="en_US.UTF-8"
```

Example for German:
```bash
LOCALE_LANG="de_DE.UTF-8"
LOCALE_NUMERIC="de_DE.UTF-8"
LOCALE_TIME="de_DE.UTF-8"
LOCALE_MONETARY="de_DE.UTF-8"
LOCALE_PAPER="de_DE.UTF-8"
LOCALE_MEASUREMENT="de_DE.UTF-8"
```

### Optional Features

**Skip sudo password prompt** (requires NOPASSWD sudo):
```bash
SKIP_BECOME_PASS=true
```

**Skip LastPass authentication** (for systems without LastPass):
```bash
SKIP_LASTPASS_CHECK=true
```

**Enable debug mode:**
```bash
DEBUG=true
```

**Keep log file after successful run:**
```bash
KEEP_LOG=true
```

## Priority Order

Configuration values are loaded in this priority order (highest to lowest):

1. **Environment variables** - Set before running the script
   ```bash
   DEBUG=true ./bin/dotfiles
   ```

2. **`~/.dotfiles.conf`** - User configuration file
   ```bash
   DEBUG=true
   ```

3. **Default values** - Hardcoded in the script

## Multi-Machine Setup

### Host-Specific Configurations

For different machines, you can use different config files:

**Laptop:**
```bash
# ~/.dotfiles.conf on laptop
DOTFILES_BRANCH="main"
SKIP_LASTPASS_CHECK=false
LOCALE_LANG="en_GB.UTF-8"
```

**Server:**
```bash
# ~/.dotfiles.conf on server
DOTFILES_BRANCH="main"
SKIP_LASTPASS_CHECK=true  # No GUI, no LastPass
LOCALE_LANG="en_US.UTF-8"
```

### Branch Strategy

You can use branches for different purposes:

- `main` - Production-ready configuration
- `testing` - Test changes before applying to main
- `laptop` - Laptop-specific overrides (optional)
- `server` - Server-specific overrides (optional)

Example:
```bash
# On testing machine
DOTFILES_BRANCH="testing"
```

## Troubleshooting

### SSH Clone Fails

If SSH clone fails, the script automatically falls back to HTTPS. To debug:

```bash
# Test SSH connection
ssh -T git@github.com

# Check SSH key
ls -la ~/.ssh/

# Add SSH key to agent
ssh-add ~/.ssh/id_ed25519
```

### LastPass Issues

Skip LastPass check temporarily:
```bash
SKIP_LASTPASS_CHECK=true ./bin/dotfiles
```

Or permanently in `~/.dotfiles.conf`:
```bash
SKIP_LASTPASS_CHECK=true
```

### Debug Mode

Enable verbose output:
```bash
DEBUG=true ./bin/dotfiles
```

Or in `~/.dotfiles.conf`:
```bash
DEBUG=true
KEEP_LOG=true  # Keep log file after run
```

## Examples

### Private Repository Setup

```bash
# ~/.dotfiles.conf
DOTFILES_REPO="git@github.com:myusername/private-dotfiles.git"
DOTFILES_REPO_HTTPS="https://github.com/myusername/private-dotfiles.git"
DOTFILES_BRANCH="main"
```

### Minimal Server Setup

```bash
# ~/.dotfiles.conf for server
SKIP_LASTPASS_CHECK=true
LOCALE_LANG="en_US.UTF-8"
LOCALE_NUMERIC="en_US.UTF-8"
LOCALE_TIME="en_US.UTF-8"
```

### Testing Environment

```bash
# ~/.dotfiles.conf for testing
DOTFILES_BRANCH="testing"
DEBUG=true
KEEP_LOG=true
```

## Security Notes

- `~/.dotfiles.conf` is in `.gitignore` - won't be committed
- Contains no secrets (uses LastPass for sensitive data)
- SSH keys should be properly secured (`chmod 600 ~/.ssh/id_*`)
