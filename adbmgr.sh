#!/bin/bash

# Define colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BRIGHT_CYAN='\033[1;36m'
BRIGHT_YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if adb is installed
if ! command -v adb &>/dev/null; then
  echo "ADB is not installed. Please install ADB and try again."
  exit 1
fi

# List connected devices and extract device names only
adb devices
devices=$(adb devices | grep -w "device" | awk '{print $1}')
device_count=$(echo "$devices" | wc -l)

# If no devices are connected
if [ $device_count -eq 0 ]; then
  echo "No devices/emulators found. Please connect a device and try again."
  exit 1
fi

# Display number of connected devices
echo -e "${GREEN}Number of devices connected: $device_count${NC}"

# If only one device is connected, automatically select it
if [ $device_count -eq 1 ]; then
  selected_device=$(echo "$devices" | head -n 1)
else
  # If multiple devices are connected, ask the user to select one
  echo -e "\n${GREEN}Connected Devices:${NC}"
  echo "$devices" | nl
  read -rp "Select device number (1-$device_count): " device_choice
  
  if [[ "$device_choice" -ge 1 && "$device_choice" -le "$device_count" ]]; then
    selected_device=$(echo "$devices" | sed -n "${device_choice}p")
  else
    echo "Invalid selection. Exiting."
    exit 1
  fi
fi

# Set the selected device for adb commands
adb -s "$selected_device" start-server

# Check for root (su) availability
check_root() {
  adb -s "$selected_device" shell "which su" &>/dev/null
  return $?
}

# Function to ask if root should be used for file management
use_root() {
  read -rp "Root permissions are available. Do you want to use root for file operations? (y/n): " choice
  if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
    ROOT_CMD="su"
    echo -e "${RED}Root mode enabled. Note: Push commands will not work in root mode. Pull commands will work but in an isolated environment.${NC}"
  else
    ROOT_CMD=""
  fi
}

#ADB shell function
start_device_shell() {
  echo -e "\n${GREEN}Device Local Shell:${NC}"
  adb -s "$selected_device" shell
}

# Function to retrieve device information in a user-friendly format
get_device_info() {
  echo -e "\n${GREEN}Device Information:${NC}"
  
  model=$(adb -s "$selected_device" shell getprop ro.product.model)
  android_version=$(adb -s "$selected_device" shell getprop ro.build.version.release)
  build_date=$(adb -s "$selected_device" shell getprop ro.build.date)
  security_patch=$(adb -s "$selected_device" shell getprop ro.build.version.security_patch)
  manufacturer=$(adb -s "$selected_device" shell getprop ro.product.manufacturer)
  brand=$(adb -s "$selected_device" shell getprop ro.product.brand)
  
  echo -e "Android Version: $android_version"
  echo -e "Build Date: $build_date"
  echo -e "Security Patch: $security_patch"
  echo -e "Device Model: $model"
  echo -e "Manufacturer: $manufacturer"
  echo -e "Brand: $brand"
}

# Function to install multiple APKs
install_multiple_apks() {
  read -rp "Enter the directory containing APKs: " apk_dir
  
  if [ ! -d "$apk_dir" ]; then
    echo "Directory not found. Please enter a valid directory."
    return
  fi

  for apk in "$apk_dir"/*.apk; do
    adb -s "$selected_device" install "$apk"
    echo "Installed: $apk"
  done
  echo -e "${GREEN}All APKs installed.${NC}"
}

# Function to list installed APKs
list_installed_apks() {
  echo -e "\n${GREEN}Installed APKs:${NC}"
  adb -s "$selected_device" shell pm list packages | sed 's/package://'
}


# Function to pull a file
pull_file() {
  local remote_path="$1"
  local local_path="$2"
  
  # Directly pull the file/folder to the local machine
  adb -s "$selected_device" pull "$remote_path" "$local_path"

  echo "File or folder has been pulled to $local_path."
}
pull_file_root_mode() {
  local remote_path="$1"
  local local_path="$2"

  # Create temporary directory on the device
  tmp_dir="/sdcard/tmp_pulled_files"
  adb -s "$selected_device" shell "su -c 'mkdir -p $tmp_dir'"

  # Copy file/folder to the temporary directory
  adb -s "$selected_device" shell "su -c 'cp -r \"$remote_path\" \"$tmp_dir\"'"

  # Pull the file/folder from the temporary directory to the local machine
  adb -s "$selected_device" pull "$tmp_dir/$(basename "$remote_path")" "$local_path"

  # Clean up the temporary directory on the device
  adb -s "$selected_device" shell "su -c 'rm -rf $tmp_dir'"

  echo "File or folder has been pulled to $local_path."
}

# Function to push a file to the device
push_file() {
  local local_path="$1"
  local remote_path="$2"

  # If remote_path is empty, use the current directory
  if [ -z "$remote_path" ]; then
    remote_path="$current_dir"
  fi

  # Push the file to the device
  adb push "$local_path" "$remote_path" || { echo "Failed to push file."; return; }
  echo "File pushed successfully to $remote_path"
}


# Function to navigate directories on the device
navigate_directories() {
  local current_dir="/sdcard"
  
  if check_root; then
    use_root
  fi
  
  while true; do
    echo -e "\n${GREEN}Current Directory: $current_dir${NC}"
    echo "--------------------------------"
    
    if [ -n "$ROOT_CMD" ]; then
      contents=($(adb -s "$selected_device" shell "su -c 'ls -a \"$current_dir\"'"))
    else
      contents=($(adb -s "$selected_device" shell "ls -a \"$current_dir\""))
    fi

    if [ "${#contents[@]}" -eq 0 ]; then
      echo "No contents found in $current_dir."
    else
      for i in "${!contents[@]}"; do
        if adb -s "$selected_device" shell "[ -d \"$current_dir/${contents[$i]}\" ]"; then
          echo -e "${BLUE}$((i + 1))) ${contents[$i]}${NC}"
        else
          echo -e "${GREEN}$((i + 1))) ${contents[$i]}${NC}"
        fi
      done
    fi

    echo -e "${BRIGHT_YELLOW}0) Go back to previous directory${NC}"
    echo -e "${BRIGHT_YELLOW}D) Delete a file/directory${NC}"
    if [ -n "$ROOT_CMD" ]; then
      echo -e "${BRIGHT_YELLOW}P) Pull a file (Root mode only)${NC}"
    else
      echo -e "${BRIGHT_YELLOW}P) Pull a file${NC}"
      echo -e "${BRIGHT_YELLOW}U) Push a file${NC}"
    fi
    echo "--------------------------------"
    echo -e "${GREEN}Options:${NC}"
    echo -e "  [Enter Number] - Enter subdirectory"
    echo -e "  [Q]            - Quit"

    read -rp "Select an option: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]]; then
      if [ "$choice" -eq 0 ]; then
        current_dir=$(dirname "$current_dir")
      elif [ "$choice" -ge 1 ] && [ "$choice" -le "${#contents[@]}" ]; then
        selected_item="${contents[$((choice - 1))]}"
        current_dir="$current_dir/$selected_item"
      else
        echo "Invalid selection."
      fi
    elif [[ "$choice" =~ ^[Qq]$ ]]; then
      break
    elif [[ "$choice" == "D" || "$choice" == "d" ]]; then
      echo "Select the file or directory to delete:"
      for i in "${!contents[@]}"; do
        echo -e "${RED}$((i + 1))) ${contents[$i]}${NC}"
      done
      read -rp "Enter the number to delete: " delete_choice
      if [[ "$delete_choice" =~ ^[0-9]+$ ]] && [ "$delete_choice" -ge 1 ] && [ "$delete_choice" -le "${#contents[@]}" ]; then
        selected_item="${contents[$((delete_choice - 1))]}"
        adb -s "$selected_device" shell "su -c 'rm -rf \"$current_dir/$selected_item\"'"
        echo "Deleted $selected_item."
      else
        echo "Invalid selection."
      fi
    elif [[ "$choice" == "P" || "$choice" == "p" ]]; then
      echo "Select the file to pull:"
      for i in "${!contents[@]}"; do
        if adb -s "$selected_device" shell "[ -f \"$current_dir/${contents[$i]}\" ]"; then
          echo -e "${GREEN}$((i + 1))) ${contents[$i]}${NC}"
        fi
      done
      read -rp "Enter the number to pull: " pull_choice
      if [[ "$pull_choice" =~ ^[0-9]+$ ]] && [ "$pull_choice" -ge 1 ] && [ "$pull_choice" -le "${#contents[@]}" ]; then
        pull_file="${contents[$((pull_choice - 1))]}"
        read -rp "Enter the local path to save the file: " local_path
        pull_file_root_mode "$current_dir/$pull_file" "$local_path"
      else
        echo "Invalid selection."
      fi
    elif [[ "$choice" == "U" || "$choice" == "u" ]]; then
      read -rp "Enter the local path of the file to push: " local_path
      read -rp "Enter the device path where to push the file: " remote_path
      push_file "$local_path" "$remote_path"
    else
      echo "Invalid option."
    fi
  done
}

# Main menu
while true; do
  echo -e "\n${GREEN}Main Menu:${NC}"
  echo "--------------------------------"
  echo -e "${BRIGHT_CYAN}1) Device Information${NC}"
  echo -e "${BRIGHT_CYAN}2) Install Multiple APKs${NC}"
  echo -e "${BRIGHT_CYAN}3) List Installed APKs${NC}"
  echo -e "${BRIGHT_CYAN}4) Navigate Device Directories${NC}"
  echo -e "${BRIGHT_CYAN}5) ADB SHELL${NC}"
  echo -e "${BRIGHT_CYAN}Q) Quit${NC}"
  
  read -rp "Select an option: " menu_choice
  
  case "$menu_choice" in
    1) get_device_info ;;
    2) install_multiple_apks ;;
    3) list_installed_apks ;;
    4) navigate_directories ;;
    5) start_device_shell ;;
    [Qq]) echo "Exiting."; exit ;;
    *) echo "Invalid option." ;;
  esac
done
