# Linux Server Hardening

## Objective
Harden the Kali VM by disabling direct root SSH login, enforcing key-based SSH authentication for user, applying a basic firewall policy to block unused ports, and capture before/after state evidence.

## Tools Used
- OS: Kali Linux (VMware)
- User created for SSH
- SSH keypairs used
- Firewall: UFW

## Folder Content

[Report](https://github.com/Gautam-CyberSec/Linux-Server-Hardening/blob/main/Report/Report.md)

[Screenshots](https://github.com/Gautam-CyberSec/Linux-Server-Hardening/tree/main/Screenshots)

## Conclusion
The Linux server was successfully hardened by creating a non-root sudo user, enforcing key-based SSH authentication, disabling root and password logins, and applying firewall rules with UFW. Before/after evidence confirms reduced attack surface and secure remote access. These steps form the baseline of server hardening and can be extended with additional measures like fail2ban, SSH rate limiting, and automated security updates for production environments.

## Contact

For questions, please contact me at https://discord.gg/zZHyANFq
