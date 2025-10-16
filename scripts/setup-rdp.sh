#!/bin/bash

################################################################################
# RDP Setup Script for Ubuntu on GitHub Actions
################################################################################

set -e

echo "=========================================="
echo "    RDP Configuration Script"
echo "=========================================="
echo ""

# Install desktop environment and RDP
echo "📦 Installing XFCE4 desktop environment..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    xrdp \
    xfce4 \
    xfce4-goodies \
    dbus-x11 \
    x11-utils \
    x11-xserver-utils

# Configure xRDP
echo "⚙️ Configuring xRDP..."
sudo systemctl enable xrdp
sudo systemctl start xrdp

# Configure firewall
echo "🔥 Configuring firewall..."
sudo ufw allow 3389/tcp 2>/dev/null || true

# Set XFCE as default session
echo "🖼️ Setting XFCE as default desktop..."
echo "xfce4-session" | sudo tee /etc/skel/.xsession

# Optimize xRDP settings
echo "🚀 Optimizing xRDP settings..."
sudo sed -i 's/max_bpp=32/max_bpp=128/g' /etc/xrdp/xrdp.ini
sudo sed -i 's/xserverbpp=24/xserverbpp=128/g' /etc/xrdp/xrdp.ini

# Restart services
echo "🔄 Restarting services..."
sudo systemctl restart xrdp

echo ""
echo "✅ RDP setup completed!"
echo "   RDP Port: 3389"
echo "   Desktop: XFCE4"
