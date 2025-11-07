#!/bin/bash

# 更新 DNS 配置，使用正确的 Zone ID
sudo tee /etc/acme/dns-config > /dev/null <<'EOF'
export CF_Token="TDSYt1qY66F3HT8W7X-l0IYDOdke4eQgnvTLUjNZ"
export CF_Zone_ID="da1da2d464d3a84c9592b7c5b58bfd2c"
export CF_Account_ID="08982882ca1428a8a058cc8d21fc1e00"
EOF

sudo chmod 644 /etc/acme/dns-config

echo "DNS 配置已更新，现在重新尝试："
echo "sudo acme-add biubiuniu.com dns"
