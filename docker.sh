#!/bin/bash

# Array of Docker images to pull from Docker Hub
DOCKER_HUB_IMAGES=(
    "aipowerbot/de-de"
    "aipowerbot/cs-cz"
    "aipowerbot/bg-bg"
    "aipowerbot/da-dk"
    "aipowerbot/el-gr"
    "aipowerbot/en-us"
    "aipowerbot/es-es"
    "aipowerbot/fi-fi"
    "aipowerbot/fr-fr"
    "aipowerbot/hu-hu"
    "aipowerbot/it-it"
    "aipowerbot/nl-nl"
    # "aipowerbot/pl-pl"
    # "aipowerbot/pt-pt"
    # "aipowerbot/ro-ro"
    # "aipowerbot/sk-sk"
    # "aipowerbot/sl-si"
    # "aipowerbot/sv-se"
    # "rocker/ml:4.2.0"
    # "rocker/ml:4.2.0-cuda10.1"
    # "rocker/ml:4.1.0"
    # "rocker/ml:4.1.0-cuda10.1"
    # "rocker/ml:4.0.3-cuda11.1"
    # "rocker/ml:4.0.3"
    # "rocker/ml:4.0.1"
    # "rocker/ml:cuda10.1"
    # "rocker/ml:4-cuda11.1"
    # "rocker/ml:3.6.1"
)

# Specify your private registry URL
REGISTRY_URL="ab-harbor.dynamic1001.com/hc"

# Function to pull and tag a Docker image
pull_and_tag_image() {
    local image=$1
    local image_name=$(basename "$image" | cut -d ':' -f 1)
    local image_tag=$(basename "$image" | cut -d ':' -f 2)

    # Pull the image from Docker Hub
    echo "Pulling image: $image"
    docker pull "$image"

    # Tag the image for the specific registry
    echo "Tagging image: $image to $REGISTRY_URL/$image_name:$image_tag"
    docker tag "$image" "$REGISTRY_URL/$image_name:$image_tag"
}

# Process each image and pull/tag sequentially
for image in "${DOCKER_HUB_IMAGES[@]}"; do
    pull_and_tag_image "$image"
done

echo "All images pulled and tagged."
# Base dimensions for each terminal
base_width=30   # Width of each terminal
base_height=10  # Height of each terminal

# Function to push a Docker image in a new terminal
push_image() {
    local image=$1
    local position=$2
    local image_name=$(basename "$image" | cut -d ':' -f 1)
    local image_tag=$(basename "$image" | cut -d ':' -f 2)

    # Open a new terminal and push the image
    echo "Opening new terminal to push image: $REGISTRY_URL/$image_name:$image_tag"
    
    # Calculate X position based on the index (position) of the terminal
    local x_position=$((position * base_width * 10))  # Multiplied by 10 for better spacing
    
    # Open a new terminal and run the push command with specific geometry
    gnome-terminal --geometry=${base_width}x${base_height}+${x_position}+0 -- bash -c "docker push $REGISTRY_URL/$image_name:$image_tag; read -p 'Press Enter to close this terminal...'"
}

# Loop through each image and open a new terminal for each
for i in "${!DOCKER_HUB_IMAGES[@]}"; do
    push_image "${DOCKER_HUB_IMAGES[$i]}" "$i"
done

echo "All push commands initiated."
