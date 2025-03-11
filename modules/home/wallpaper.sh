#!/usr/bin/env bash

# Base URL for raw GitHub content
BASE_URL="https://raw.githubusercontent.com/adi1090x/dynamic-wallpaper/master/images"

# List of available themes
THEMES=(
    "aurora" "beach" "bitday" "chihuahuan" "cliffs" "colony" 
    "desert" "earth" "exodus" "factory" "firewatch" "forest" 
    "gradient" "home" "island" "lake" "lakeside" "market" 
    "mojave" "moon" "mountains" "room" "sahara" "street" "tokyo"
)

# Initialize swww if not already running
if ! pgrep -x "swww" > /dev/null; then
    swww init
fi

# Function to get random theme
get_random_theme() {
    local random_index=$(( RANDOM % ${#THEMES[@]} ))
    echo "${THEMES[$random_index]}"
}

# Main loop
while true; do
    # Get random theme
    theme=$(get_random_theme)
    
    # Generate random number between 1 and 10 for image selection
    # Most themes have 6-10 images
    random_number=$(( (RANDOM % 10) + 1 ))
    
    # Construct the URL
    wallpaper_url="$BASE_URL/$theme/$random_number.jpg"
    
    # Set the wallpaper
    swww img "$wallpaper_url" \
        --transition-type grow \
        --transition-pos "$(hyprctl cursorpos)" \
        --transition-duration 2
    
    # Wait for 10 minutes before next change
    sleep 600
done