#!/bin/bash

# Check if adb is installed
if ! command -v adb &>/dev/null; then
  echo "ADB is not installed. Please install ADB and try again."
  exit 1
fi

# Connect to the device via ADB
echo -e "\n${GREEN}List of devices attached${NC}"
adb devices
if [ $? -ne 0 ]; then
  echo "Failed to connect to the device. Ensure that USB debugging is enabled."
  exit 1
fi

# Define colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to display and navigate directories
function navigate_directories() {
  local current_dir="$1"
  local pull_store_dir="."

  while true; do
    echo -e "\n${GREEN}Current Directory: $current_dir${NC}"
    echo "--------------------------------"
    
    # List contents in the current directory using adb shell and number each item
    contents=($(adb shell "ls \"$current_dir\""))
    if [ "${#contents[@]}" -eq 0 ]; then
      echo "No contents found in $current_dir."
    else
      for i in "${!contents[@]}"; do
        echo -e "${GREEN}$((i + 1))) ${contents[$i]}${NC}"
      done
    fi

    echo -e "${RED}0) Go back to previous directory${NC}"
    echo "--------------------------------"
    echo -e "${GREEN}Options:${NC}"
    echo -e "  [Enter Number] - Enter subdirectory"
    echo -e "  [CTRL+A]       - Push/Pull files"
    echo -e "  [Q]            - Quit"
    
    # Get user input
    read -rp "Select an option: " choice
    
    # Process user input
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
      if [ "$choice" -eq 0 ]; then
        # Go back to the previous directory
        current_dir=$(dirname "$current_dir")
      elif [ "$choice" -ge 1 ] && [ "$choice" -le "${#contents[@]}" ]; then
        selected_item="${contents[$((choice - 1))]}"
        current_dir="$current_dir/$selected_item"
      else
        echo "Invalid selection. Please enter a valid number."
      fi
    elif [[ "$choice" == $'\001' ]]; then  # CTRL+A is ASCII SOH character
      push_pull_menu "$current_dir" "${contents[@]}"
    elif [[ "$choice" =~ ^[Qq]$ ]]; then
      echo "Exiting file manager."
      break
    else
      echo "Invalid option. Please try again."
    fi
  done
}

# Function to display Push/Pull options
function push_pull_menu() {
  local current_dir="$1"
  shift
  local contents=("$@")

  echo -e "\n${GREEN}Push/Pull Menu${NC}"
  echo -e "${GREEN}1) Pull file from current directory${NC}"
  echo -e "${GREEN}2) Manually enter directory to pull from${NC}"
  echo -e "${GREEN}3) Push file to $current_dir${NC}"
  echo -e "${GREEN}4) Cancel${NC}"

  read -rp "Select an option: " pp_choice

  case $pp_choice in
    1)
      if [ "${#contents[@]}" -eq 0 ]; then
        echo "No contents to pull."
        return
      fi
      
      echo "Select the number of the file or directory to pull:"
      for i in "${!contents[@]}"; do
        echo -e "${GREEN}$((i + 1))) ${contents[$i]}${NC}"
      done

      read -rp "Enter the number: " pull_choice
      if [[ "$pull_choice" =~ ^[0-9]+$ ]] && [ "$pull_choice" -ge 1 ] && [ "$pull_choice" -le "${#contents[@]}" ]; then
        pull_file="${contents[$((pull_choice - 1))]}"
        echo -n "Enter the directory to store the pulled file (default: current directory): "
        read -r pull_store_dir
        pull_store_dir=${pull_store_dir:-"."} # Default to current directory if empty
        adb pull "$current_dir/$pull_file" "$pull_store_dir/"
      else
        echo "Invalid selection. Please enter a valid number."
      fi
      ;;
    2)
      read -rp "Enter the full path of the directory to pull from: " manual_dir
      echo "Contents of $manual_dir:"
      adb shell "ls \"$manual_dir\""
      read -rp "Select the number of the file or directory to pull from $manual_dir: " pull_choice_manual
      contents_manual=($(adb shell "ls \"$manual_dir\""))
      if [[ "$pull_choice_manual" =~ ^[0-9]+$ ]] && [ "$pull_choice_manual" -ge 1 ] && [ "$pull_choice_manual" -le "${#contents_manual[@]}" ]; then
        pull_file_manual="${contents_manual[$((pull_choice_manual - 1))]}"
        echo -n "Enter the directory to store the pulled file (default: current directory): "
        read -r pull_store_dir
        pull_store_dir=${pull_store_dir:-"."} # Default to current directory if empty
        adb pull "$manual_dir/$pull_file_manual" "$pull_store_dir/"
      else
        echo "Invalid selection. Please enter a valid number."
      fi
      ;;
    3)
      read -rp "Enter the path of the file to push: " push_path
      adb push "$push_path" "$current_dir"
      ;;
    4)
      echo "Returning to directory navigation."
      ;;
    *)
      echo "Invalid option."
      ;;
  esac
}

# Start navigation from /sdcard directory
navigate_directories "/sdcard"
