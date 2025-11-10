#!/bin/zsh

set -e
set -o pipefail

# Config
KERNEL_REPO="https://github.com/microsoft/WSL2-Linux-Kernel.git"
KERNEL_BRANCH="linux-msft-wsl-6.6.y"
CONFIG_URL="https://raw.githubusercontent.com/Malafet/WSL2/main/.config"

OUT_DIR="/mnt/wsl_staged/WSL-Kernel-Update"
RAMBUILD="/mnt/rambuild"
SRC_DIR="$RAMBUILD/WSL2-Linux-Kernel"

MODULES_DIR="$SRC_DIR/build/linux-mods"
MODULES_VHDX="$SRC_DIR/build/linux-module/modules.vhdx"
BZIMAGE_SRC="$SRC_DIR/arch/x86/boot/bzImage"

BZIMAGE_OUT="$OUT_DIR/wsl-custom-bzImage"
MODULES_OUT="$OUT_DIR/wsl-modules.vhdx"

# Install deps
sudo apt update
sudo apt install -y \
  build-essential flex bison dwarves libssl-dev libelf-dev bc python3 pahole \
  cpio qemu-utils git libncurses-dev clang lld wget

export CC=clang
export LD=ld.lld

# Prepare dirs
sudo mkdir -p "$OUT_DIR" "$RAMBUILD"

# Mount tmpfs for fast build (if not already)
if ! mountpoint -q "$RAMBUILD"; then
  sudo mount -t tmpfs -o size=32G tmpfs "$RAMBUILD"
fi

# Always start clean
rm -rf "$SRC_DIR"
git clone --depth=1 -b "$KERNEL_BRANCH" "$KERNEL_REPO" "$SRC_DIR"

cd "$SRC_DIR"
mkdir -p build/linux-mods build/linux-module build/linux-kernel

# Get custom config
echo "Downloading custom kernel configuration..."
wget -q -O .config "$CONFIG_URL"

# Sync config + build
make olddefconfig
make -j"$(nproc)"

# Modules → vhdx
sudo make modules_install INSTALL_MOD_PATH="$MODULES_DIR"
sudo ./Microsoft/scripts/gen_modules_vhdx.sh \
  "$MODULES_DIR" "$(make -s kernelrelease)" "$MODULES_VHDX"

# Copy artifacts to final location
cp "$BZIMAGE_SRC" "build/linux-kernel/Custom-bzImage"
sudo cp "$MODULES_VHDX" "$MODULES_OUT"
sudo cp "build/linux-kernel/Custom-bzImage" "$BZIMAGE_OUT"

# Cleanup
cd /
rm -rf "$SRC_DIR"
sudo umount "$RAMBUILD" || echo "Note: $RAMBUILD was busy or already unmounted."

echo "WSL2 kernel and modules have been built and copied to $OUT_DIR - Kernel: wsl-custom-bzImage, Modules: wsl-modules.vhdx"