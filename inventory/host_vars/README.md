---
# ============================================================================
# Host Variables - Hostname-based Configuration
# ============================================================================
# This directory contains host-specific and category-specific configurations
#
# File naming conventions:
#   1. Exact hostname match:     <hostname>.yml
#   2. Category/group match:     <category>.yml
#
# Priority (highest to lowest):
#   1. Exact hostname (e.g., bernie-laptop.yml)
#   2. Category file (e.g., laptop.yml, desktop.yml, server.yml)
#   3. group_vars/all.yml (fallback)
#
# ============================================================================

# Example structure:
#
# host_vars/
#   ├── README.md                    # This file
#   │
#   ├── bernie-laptop.yml            # Specific device
#   ├── work-desktop.yml             # Specific device
#   ├── home-server.yml              # Specific device
#   │
#   ├── laptop.yml                   # All laptops
#   ├── desktop.yml                  # All desktops
#   ├── server.yml                   # All servers
#   │
#   └── *.example                    # Example templates

# ============================================================================
# How to use:
# ============================================================================

# 1. Get your hostname:
#    $ hostname
#    bernie-laptop

# 2. Create your host file:
#    $ cp laptop.yml.example bernie-laptop.yml

# 3. Customize it:
#    Edit bernie-laptop.yml with your specific settings

# 4. Run dotfiles:
#    The script automatically loads: bernie-laptop.yml → laptop.yml → all.yml

# ============================================================================
# What to configure:
# ============================================================================

# - default_roles: Which roles to run on this host
# - exclude_roles: Which roles to skip
# - Host-specific variables (display settings, hardware config, etc.)
# - Application-specific settings

# ============================================================================
# Security Note:
# ============================================================================

# Hostname files (e.g., bernie-laptop.yml) are NOT in .gitignore
# Make sure they don't contain:
#   - Passwords or API keys (use LastPass)
#   - Private information
#   - Personal data

# If you need secrets, use LastPass references:
#   my_secret: "op://vault/item/field"
