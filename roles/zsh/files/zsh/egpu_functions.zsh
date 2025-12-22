#!/usr/bin/env zsh

# AMD eGPU Check and Activation Function
# Universal eGPU detection with Ansible-like task visualization
# Compatible with any AMD GPU over Thunderbolt 3

# State tracking
typeset -i TASK_COUNT=0
typeset -i ERROR_COUNT=0
typeset -i WARNING_COUNT=0
typeset -i SUCCESS_COUNT=0
typeset -A EGPU_INFO
typeset -i __COMPACT_MODE=0

# ============================================================================
# Task Management Functions (Ansible-like)
# ============================================================================

__egpu_task() {
  [[ $__COMPACT_MODE -eq 1 ]] && return
  local msg="$*"
  TASK_COUNT=$((TASK_COUNT + 1))
  printf "${LBLUE}  [*]  Task ${TASK_COUNT}: ${msg}${NC}\n"
}

__egpu_task_ok() {
  [[ $__COMPACT_MODE -eq 1 ]] && { SUCCESS_COUNT=$((SUCCESS_COUNT + 1)); return; }
  local msg="${*:-Success}"
  printf "${OVERWRITE}${LGREEN}  [✓]  Task ${TASK_COUNT}: ${msg}${NC}\n"
  SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
}

__egpu_task_fail() {
  [[ $__COMPACT_MODE -eq 1 ]] && { ERROR_COUNT=$((ERROR_COUNT + 1)); return; }
  local msg="${*:-Failed}"
  printf "${OVERWRITE}${LRED}  [✗]  Task ${TASK_COUNT}: ${msg}${NC}\n"
  ERROR_COUNT=$((ERROR_COUNT + 1))
}

__egpu_task_warn() {
  [[ $__COMPACT_MODE -eq 1 ]] && { WARNING_COUNT=$((WARNING_COUNT + 1)); return; }
  local msg="${*:-Warning}"
  printf "${OVERWRITE}${LYELLOW}  [!]  Task ${TASK_COUNT}: ${msg}${NC}\n"
  WARNING_COUNT=$((WARNING_COUNT + 1))
}

__egpu_debug() {
  [[ $__COMPACT_MODE -eq 1 ]] && return
  local msg="$*"
  printf "${LBLACK}      └─ ${msg}${NC}\n"
}

__egpu_header() {
  [[ $__COMPACT_MODE -eq 1 ]] && return
  local title="$*"
  echo ""
  printf "${LBLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  printf "${LBLUE}  ${title}${NC}\n"
  printf "${LBLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

__egpu_section() {
  [[ $__COMPACT_MODE -eq 1 ]] && return
  local title="$*"
  printf "${LCYAN}▶ ${title}${NC}\n"
}

# ============================================================================
# Hardware Detection Functions
# ============================================================================

__detect_amd_gpus() {
  local gpus=()
  local lspci_output
  
  __egpu_task "Detecting GPUs"
  
  # Search for GPU devices (any VGA/Display controllers)
  lspci_output=$(lspci | grep -iE "vga.*controller|display.*controller|3d.*controller" 2>/dev/null || true)
  
  if [[ -z "$lspci_output" ]]; then
    __egpu_task_fail "No GPUs detected"
    return 1
  fi
  
  # Parse GPU information
  while IFS= read -r line; do
    if [[ -n "$line" ]]; then
      local pci_id=$(echo "$line" | awk '{print $1}')
      # Extract the GPU model name from brackets (e.g., "Radeon RX 6800")
      local gpu_name=$(echo "$line" | sed 's/.*\[//; s/\].*//')
      
      gpus+=("$pci_id:$gpu_name")
      EGPU_INFO[gpu_name]="$gpu_name"
      EGPU_INFO[pci_id]="$pci_id"
      __egpu_debug "Found: $gpu_name ($pci_id)"
    fi
  done <<< "$lspci_output"
  
  # Try to get exact GPU name from vulkaninfo or glxinfo
  __detect_exact_gpu_name
  
  if [[ ${#gpus[@]} -gt 0 ]]; then
    EGPU_INFO[gpu_count]=${#gpus[@]}
    EGPU_INFO[gpus]="${(j:|:)gpus[@]}"
    __egpu_task_ok "Detected ${#gpus[@]} GPU(s)"
    return 0
  else
    __egpu_task_fail "Failed to parse GPU information"
    return 1
  fi
}

__detect_exact_gpu_name() {
  # For eGPU detection, prioritize DRI_PRIME=1 (which targets external GPU)
  # This ensures we get the eGPU name, not the integrated GPU
  
  if command -v glxinfo &>/dev/null; then
    local opengl_name
    opengl_name=$(DRI_PRIME=1 glxinfo 2>/dev/null | grep "OpenGL renderer string" | sed 's/.*OpenGL renderer string: //' | sed 's/ (.*$//' | xargs)
    if [[ -n "$opengl_name" && "$opengl_name" != "" ]]; then
      # Check if it's AMD (should be for eGPU)
      if [[ "$opengl_name" =~ "AMD" || "$opengl_name" =~ "Radeon" || "$opengl_name" =~ "RADEON" ]]; then
        EGPU_INFO[gpu_name]="$opengl_name"
        __egpu_debug "eGPU detected (via DRI_PRIME=1): $opengl_name"
        return 0
      fi
    fi
  fi
  
  # Fallback to vulkaninfo for external AMD GPU only
  if command -v vulkaninfo &>/dev/null; then
    local vulkan_name
    # Explicitly search for AMD/Radeon devices
    vulkan_name=$(vulkaninfo 2>/dev/null | awk '/deviceName.*=.*AMD|deviceName.*=.*Radeon|deviceName.*=.*RADEON/ {print; exit}' | sed 's/.*deviceName \+= //' | xargs)
    if [[ -n "$vulkan_name" && "$vulkan_name" != "" ]]; then
      EGPU_INFO[gpu_name]="$vulkan_name"
      __egpu_debug "eGPU detected (via Vulkan): $vulkan_name"
      return 0
    fi
  fi
}

__detect_thunderbolt() {
  __egpu_task "Checking external device connections"
  
  if ! command -v boltctl &>/dev/null; then
    __egpu_task_warn "boltctl not available (Thunderbolt support optional)"
    return 1
  fi
  
  local devices
  devices=$(boltctl list 2>/dev/null)
  
  if [[ -z "$devices" ]]; then
    __egpu_task_warn "No Thunderbolt devices found"
    __egpu_debug "Connect device and power on enclosure"
    return 1
  fi
  
  # Check authorization status
  local authorized=0
  local unauthorized=0
  
  # Count devices by checking for authorization symbols
  while IFS= read -r line; do
    if [[ "$line" =~ "✓" ]]; then
      ((authorized++))
    elif [[ "$line" =~ "○" ]]; then
      ((unauthorized++))
    fi
  done <<< "$devices"
  
  EGPU_INFO[tb_authorized]=$authorized
  EGPU_INFO[tb_unauthorized]=$unauthorized
  
  if (( unauthorized > 0 )); then
    __egpu_task_warn "Found $unauthorized unauthorized device(s)"
    return 1
  else
    if (( authorized > 0 )); then
      __egpu_task_ok "All devices authorized ($authorized device(s))"
    else
      __egpu_task_warn "No devices found to authorize"
    fi
    return 0
  fi
}

__detect_kernel_driver() {
  __egpu_task "Checking GPU kernel driver"
  
  if lsmod | grep -q "^amdgpu"; then
    EGPU_INFO[driver_loaded]="yes"
    __egpu_task_ok "amdgpu driver loaded"
    return 0
  elif lsmod | grep -q "^nvidia"; then
    EGPU_INFO[driver_loaded]="yes"
    EGPU_INFO[driver_type]="nvidia"
    __egpu_task_ok "nvidia driver loaded"
    return 0
  else
    EGPU_INFO[driver_loaded]="no"
    __egpu_task_warn "Expected driver not loaded"
    return 1
  fi
}

__detect_dri_devices() {
  __egpu_task "Detecting DRI devices"
  
  local card_count=0
  local render_count=0
  
  if ls /dev/dri/card* &>/dev/null 2>&1; then
    card_count=$(ls /dev/dri/card* 2>/dev/null | wc -l)
    EGPU_INFO[dri_cards]=$card_count
    __egpu_debug "Found $card_count DRI card device(s)"
  else
    __egpu_task_warn "No DRI card devices found"
    return 1
  fi
  
  if ls /dev/dri/renderD* &>/dev/null 2>&1; then
    render_count=$(ls /dev/dri/renderD* 2>/dev/null | wc -l)
    EGPU_INFO[dri_renders]=$render_count
    __egpu_debug "Found $render_count DRI render device(s)"
  fi
  
  if (( card_count > 0 )); then
    __egpu_task_ok "DRI devices available"
    return 0
  fi
  
  return 1
}

__detect_vulkan() {
  __egpu_task "Checking Vulkan support"
  
  if ! command -v vulkaninfo &>/dev/null; then
    __egpu_task_warn "vulkaninfo not installed (install: pacman -S vulkan-tools)"
    return 1
  fi
  
  if ! pacman -Qi vulkan-radeon &>/dev/null 2>&1; then
    __egpu_task_warn "vulkan-radeon not installed (install: pacman -S vulkan-radeon)"
    return 1
  fi
  
  local vulkan_devices
  vulkan_devices=$(vulkaninfo 2>/dev/null | grep "deviceName" || true)
  
  if [[ -z "$vulkan_devices" ]]; then
    __egpu_task_warn "Could not detect Vulkan devices"
    return 1
  fi
  
  if echo "$vulkan_devices" | grep -qi "amd\|radeon"; then
    EGPU_INFO[vulkan_ok]="yes"
    __egpu_task_ok "AMD GPU Vulkan support detected"
    return 0
  else
    __egpu_task_warn "Vulkan available but AMD GPU not primary device"
    return 1
  fi
}

__detect_opengl() {
  __egpu_task "Checking OpenGL support"
  
  if ! command -v glxinfo &>/dev/null; then
    __egpu_task_warn "glxinfo not installed (install: pacman -S mesa-utils)"
    return 1
  fi
  
  local gl_renderer
  gl_renderer=$(DRI_PRIME=1 glxinfo 2>/dev/null | grep "OpenGL renderer" || true)
  
  if [[ -z "$gl_renderer" ]]; then
    __egpu_task_warn "Could not query OpenGL renderer"
    return 1
  fi
  
  if echo "$gl_renderer" | grep -qi "amd\|radeon"; then
    EGPU_INFO[opengl_ok]="yes"
    __egpu_task_ok "AMD GPU OpenGL support detected"
    __egpu_debug "$gl_renderer"
    return 0
  else
    __egpu_task_warn "OpenGL renderer not AMD GPU: $gl_renderer"
    return 1
  fi
}

__detect_vram() {
  __egpu_task "Detecting GPU VRAM"
  
  local vram_info
  vram_info=$(dmesg 2>/dev/null | grep -i "amdgpu.*vram" | tail -1 || true)
  
  if [[ -n "$vram_info" ]]; then
    EGPU_INFO[vram]="$vram_info"
    __egpu_task_ok "VRAM information detected"
    __egpu_debug "${vram_info:0:80}..."
    return 0
  else
    __egpu_task_warn "Could not determine VRAM size"
    return 1
  fi
}

# ============================================================================
# Authorization Function
# ============================================================================

__authorize_thunderbolt() {
  __egpu_task "Authorizing Thunderbolt device"
  
  if ! command -v boltctl &>/dev/null; then
    __egpu_task_fail "boltctl not available"
    return 1
  fi
  
  # Get first unauthorized device
  local device_uuid
  device_uuid=$(boltctl list 2>/dev/null | grep "○" -A 5 | grep "UUID:" | awk '{print $2}' | head -1 || true)
  
  if [[ -z "$device_uuid" ]]; then
    __egpu_task_warn "No unauthorized Thunderbolt devices found"
    return 1
  fi
  
  __egpu_debug "Authorizing device: $device_uuid"
  
  if sudo boltctl authorize "$device_uuid" 2>&1; then
    __egpu_task_ok "Device authorized successfully"
    sleep 2  # Allow device recognition
    return 0
  else
    __egpu_task_fail "Authorization failed"
    return 1
  fi
}

__load_amdgpu_driver() {
  __egpu_task "Loading amdgpu kernel module"
  
  if sudo modprobe amdgpu 2>&1; then
    sleep 1
    if lsmod | grep -q "^amdgpu"; then
      EGPU_INFO[driver_loaded]="yes"
      __egpu_task_ok "amdgpu module loaded successfully"
      return 0
    else
      __egpu_task_fail "Module load verification failed"
      return 1
    fi
  else
    __egpu_task_fail "modprobe failed"
    return 1
  fi
}

# ============================================================================
# Summary and Report
# ============================================================================

__print_summary() {
  local ready="yes"
  
  [[ $__COMPACT_MODE -eq 0 ]] && __egpu_header "Summary"
  
  [[ $__COMPACT_MODE -eq 0 ]] && __egpu_section "Detection Results"
  [[ $__COMPACT_MODE -eq 0 ]] && printf "${LGREEN}  [+] Successful: ${SUCCESS_COUNT}${NC}\n"
  [[ $__COMPACT_MODE -eq 0 ]] && printf "${LYELLOW}  [!] Warnings:  ${WARNING_COUNT}${NC}\n"
  [[ $__COMPACT_MODE -eq 0 ]] && printf "${LRED}  [×] Errors:    ${ERROR_COUNT}${NC}\n"
  [[ $__COMPACT_MODE -eq 0 ]] && echo ""
  
  if [[ -n "${EGPU_INFO[gpu_count]}" ]]; then
    [[ $__COMPACT_MODE -eq 0 ]] && printf "${LGREEN}  ✓ GPU Detection:${NC} ${EGPU_INFO[gpu_count]} GPU(s) found\n"
  else
    [[ $__COMPACT_MODE -eq 0 ]] && printf "${LRED}  ✗ GPU Detection:${NC} No GPUs found\n"
    ready="no"
  fi
  
  if [[ "${EGPU_INFO[driver_loaded]}" == "yes" ]]; then
    [[ $__COMPACT_MODE -eq 0 ]] && printf "${LGREEN}  ✓ Driver:${NC} amdgpu loaded\n"
  else
    [[ $__COMPACT_MODE -eq 0 ]] && printf "${LYELLOW}  ! Driver:${NC} amdgpu not loaded\n"
  fi
  
  if [[ -n "${EGPU_INFO[dri_cards]}" ]]; then
    [[ $__COMPACT_MODE -eq 0 ]] && printf "${LGREEN}  ✓ DRI Devices:${NC} ${EGPU_INFO[dri_cards]} card(s)\n"
  else
    [[ $__COMPACT_MODE -eq 0 ]] && printf "${LRED}  ✗ DRI Devices:${NC} None found\n"
  fi
  
  if [[ "${EGPU_INFO[vulkan_ok]}" == "yes" ]]; then
    [[ $__COMPACT_MODE -eq 0 ]] && printf "${LGREEN}  ✓ Vulkan:${NC} AMD GPU ready\n"
  else
    [[ $__COMPACT_MODE -eq 0 ]] && printf "${LYELLOW}  ! Vulkan:${NC} Not fully configured\n"
  fi
  
  if [[ "${EGPU_INFO[opengl_ok]}" == "yes" ]]; then
    [[ $__COMPACT_MODE -eq 0 ]] && printf "${LGREEN}  ✓ OpenGL:${NC} AMD GPU ready\n"
  else
    [[ $__COMPACT_MODE -eq 0 ]] && printf "${LYELLOW}  ! OpenGL:${NC} Not fully configured\n"
  fi
  
  echo ""
  
  # Compact mode summary
  if [[ $__COMPACT_MODE -eq 1 ]]; then
    local gpu_display="${EGPU_INFO[gpu_name]:-eGPU}"
    if [[ "$ready" == "yes" && $ERROR_COUNT -eq 0 ]]; then
      printf "${LGREEN}✓${NC} ${LBLACK}${gpu_display}${NC} ${LGREEN}ready${NC} (${SUCCESS_COUNT}✓ ${WARNING_COUNT}! ${ERROR_COUNT}✗)\n"
      return 0
    else
      printf "${LRED}✗${NC} ${LBLACK}${gpu_display}${NC} ${LRED}not ready${NC} (${SUCCESS_COUNT}✓ ${WARNING_COUNT}! ${ERROR_COUNT}✗)\n"
      return 1
    fi
  fi
  
  # Full mode summary
  [[ $__COMPACT_MODE -eq 0 ]] && __egpu_section "Quick Start"
  
  if [[ "$ready" == "yes" ]]; then
    [[ $__COMPACT_MODE -eq 0 ]] && printf "${LGREEN}✓${NC} Your eGPU is ready for gaming!\n"
    [[ $__COMPACT_MODE -eq 0 ]] && echo ""
    [[ $__COMPACT_MODE -eq 0 ]] && printf "  ${CYAN}For gaming, use:${NC}\n"
    [[ $__COMPACT_MODE -eq 0 ]] && printf "    ${BOLD}DRI_PRIME=1 <game-command>${NC}\n"
    [[ $__COMPACT_MODE -eq 0 ]] && echo ""
    [[ $__COMPACT_MODE -eq 0 ]] && printf "  ${CYAN}Example:${NC}\n"
    [[ $__COMPACT_MODE -eq 0 ]] && printf "    ${BOLD}DRI_PRIME=1 vulkaninfo${NC}  (test Vulkan)\n"
    [[ $__COMPACT_MODE -eq 0 ]] && printf "    ${BOLD}DRI_PRIME=1 glxinfo | grep renderer${NC}  (test OpenGL)\n"
  else
    [[ $__COMPACT_MODE -eq 0 ]] && printf "${LRED}✗${NC} Some checks failed. Review tasks above.\n"
    [[ $__COMPACT_MODE -eq 0 ]] && echo ""
    [[ $__COMPACT_MODE -eq 0 ]] && printf "  ${CYELLOW}Quick fixes:${NC}\n"
    [[ $__COMPACT_MODE -eq 0 ]] && printf "    • Load driver: ${BOLD}egpu-check authorize${NC}\n"
    [[ $__COMPACT_MODE -eq 0 ]] && printf "    • Install Vulkan: ${BOLD}sudo pacman -S vulkan-radeon${NC}\n"
    [[ $__COMPACT_MODE -eq 0 ]] && printf "    • Install OpenGL: ${BOLD}sudo pacman -S mesa-utils${NC}\n"
  fi
  
  [[ $__COMPACT_MODE -eq 0 ]] && echo ""
}

# ============================================================================
# Main Function
# ============================================================================

egpu() {
  local action="check"
  local verbose=0
  
  # Parse all arguments
  for arg in "$@"; do
    case "$arg" in
      --help|-h)
        printf "${BOLD}${LCYAN}egpu${NC} - AMD eGPU Status & Detection Tool\n\n"
        printf "${CYAN}Usage:${NC}\n"
        printf "  ${BOLD}egpu${NC}              Check eGPU status (compact view, default)\n"
        printf "  ${BOLD}egpu --verbose${NC}    Detailed hardware detection\n"
        printf "  ${BOLD}egpu authorize${NC}    Authorize Thunderbolt device\n"
        printf "  ${BOLD}egpu driver${NC}       Load amdgpu kernel module\n"
        printf "  ${BOLD}egpu --help${NC}       Show this help message\n"
        echo ""
        printf "${CYAN}Examples:${NC}\n"
        printf "  ${BOLD}egpu${NC}              # Quick status check\n"
        printf "  ${BOLD}egpu --verbose${NC}    # Full diagnostic output\n"
        printf "  ${BOLD}egpu authorize${NC}    # Authorize TB device\n"
        echo ""
        printf "${CYAN}Usage with games:${NC}\n"
        printf "  ${BOLD}DRI_PRIME=1 gamename${NC}\n"
        return 0
        ;;
      --verbose|-v)
        verbose=1
        ;;
      authorize|driver)
        action="$arg"
        ;;
      *)
        printf "${LRED}Unknown option: ${arg}${NC}\n"
        printf "Use ${BOLD}egpu --help${NC} for usage information\n"
        return 1
        ;;
    esac
  done
  
  # Reset state
  TASK_COUNT=0
  ERROR_COUNT=0
  WARNING_COUNT=0
  SUCCESS_COUNT=0
  __COMPACT_MODE=$((1 - verbose))
  
  # Banner (skip in compact mode)
  if [[ $__COMPACT_MODE -eq 0 ]]; then
    echo ""
    printf "${BOLD}${LBLUE}"
    printf "╔════════════════════════════════════════════════════════════════╗\n"
    printf "║              External GPU Status & Detection Tool              ║\n"
    printf "║         Hardware Detection & Diagnostics                       ║\n"
    printf "╚════════════════════════════════════════════════════════════════╝\n"
    printf "${NC}\n"
  fi
  
  case "$action" in
    check)
      __egpu_header "Hardware Detection"
      __detect_amd_gpus
      __detect_thunderbolt
      __detect_kernel_driver
      __detect_dri_devices
      __detect_vulkan
      __detect_opengl
      __detect_vram
      __print_summary
      ;;
    authorize)
      __egpu_header "Thunderbolt Authorization"
      __authorize_thunderbolt
      sleep 2
      __egpu_header "Re-checking Hardware"
      __detect_amd_gpus
      __detect_thunderbolt
      __detect_kernel_driver
      __detect_dri_devices
      __print_summary
      ;;
    driver)
      __egpu_header "Driver Management"
      __load_amdgpu_driver
      sleep 2
      __egpu_header "Re-checking Hardware"
      __detect_amd_gpus
      __detect_kernel_driver
      __detect_dri_devices
      __print_summary
      ;;
  esac
  
  [[ $ERROR_COUNT -eq 0 ]] && return 0 || return 1
}
