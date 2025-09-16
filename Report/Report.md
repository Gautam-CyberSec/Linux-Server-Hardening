# Analysis Report — Linux Server Hardening

## Executive Summary
This project demonstrates hardening of a Kali Linux VM by creating a sudo user broskieshub, enforcing SSH public-key authentication, disabling direct root SSH login, and activating UFW firewall rules to block unused ports. All changes were documented with before/after evidence.

## Step by Step Process

#### 1. Create a New User and Modidying user permissions
  
  ```sudo adduser broskieshub```

  ```sudo usermod -aG sudo broskieshub```

  <img width="719" height="372" alt="Image" src="https://github.com/Gautam-CyberSec/Linux-Server-Hardening/blob/main/Screenshots/Screenshot%202025-09-16%20152339.png" />


#### 2. Check open ports and services

  ```sudo ss -tuln```

<img width="719" height="372" alt="Image" src="https://github.com/Gautam-CyberSec/Linux-Server-Hardening/blob/main/Screenshots/Screenshot%202025-09-16%20152402.png" />

#### 3. Checking SSH config

  ```sudo cat /etc/ssh/sshd_config```

<img width="719" height="372" alt="Image" src="https://github.com/Gautam-CyberSec/Linux-Server-Hardening/blob/main/Screenshots/Screenshot%202025-09-16%20152557.png" />

#### 4. Generated SSH key

  ```ssh-keygen -t ed25519 -C "broskieshub-key"```

<img width="719" height="372" alt="Image" src="https://github.com/Gautam-CyberSec/Linux-Server-Hardening/blob/main/Screenshots/Screenshot%202025-09-16%20152802.png" />

#### 5. Copied public key to server

  ```ssh-copy-id -i /home/kali/broskieshub-key.pub broskieshub@192.168.1775.128```

<img width="719" height="372" alt="Image" src="https://github.com/Gautam-CyberSec/Linux-Server-Hardening/blob/main/Screenshots/Screenshot%202025-09-16%20153536.png" />

#### 6. Tested login

  ```ssh broskieshub@192.168.175.128```

<img width="719" height="372" alt="Image" src="https://github.com/Gautam-CyberSec/Linux-Server-Hardening/blob/main/Screenshots/Screenshot%202025-09-16%20155121.png" />


#### 7. Edited SSH config to disable root login

  ```sudo nano /etc/ssh/sshd_config```

<img width="719" height="372" alt="Image" src="https://github.com/Gautam-CyberSec/Linux-Server-Hardening/blob/main/Screenshots/Screenshot%202025-09-16%20155349.png" />

#### 8. Restarted SSH service

  ```systemctl restart ssh```

<img width="719" height="372" alt="Image" src="https://github.com/Gautam-CyberSec/Linux-Server-Hardening/blob/main/Screenshots/Screenshot%202025-09-16%20155500.png" />

#### 9. Configure Firewall

  ```sudo apt install ufw```
  
  ```sudo ufw default deny incoming```
  
  ```sudo ufw default allow outgoing```
  
  ```sudo ufw allow 22/tcp```
  
  ```sudo ufw --force enable```
  
  ```sudo ufw status verbose```

<img width="719" height="372" alt="Image" src="https://github.com/Gautam-CyberSec/Linux-Server-Hardening/blob/main/Screenshots/Screenshot%202025-09-16%20155543.png" />


#### 10. Verifing Firewall

  ```Sudo ss -tuln```

<img width="719" height="372" alt="Image" src="https://github.com/Gautam-CyberSec/Linux-Server-Hardening/blob/main/Screenshots/Screenshot%202025-09-16%20155803.png" />








  
