sudo apt update && sudo apt upgrade -y
sudo apt install -y git python3-openstackclient \
  openvswitch-switch openvswitch-common

sudo useradd -s /bin/bash -d /opt/stack -m stack
echo "stack ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/stack
sudo chmod 0440 /etc/sudoers.d/stack
sudo usermod -aG stack www-data
sudo chmod +x /opt/stack
sudo chown -R stack:stack /opt/stack
sudo systemctl enable --now openvswitch-switch
