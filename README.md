# siteblock

A free, open-source site blocker for macOS. It blocks adult, crypto, scam, malware, and phishing sites, plus any domains you add yourself (TeraBox, DiskWala, and so on).

It works at the system level, so the blocks apply in **every browser** (Safari, Chrome, Firefox, Brave, Arc, Edge) and in other apps too. There is no extension to install and no account to create.

## How it works

| Layer | What it blocks | How |
|---|---|---|
| `/etc/hosts` | Crypto (~1.3k) and scam (~8.5k) domains, and everything in `custom.txt` | Points each domain to `0.0.0.0` |
| `FamilyDNS.mobileconfig` | Adult and malware/phishing sites, including new ones | Encrypted DNS (DoH) to [Cloudflare for Families](https://one.one.one.one/family/) |
| Daily refresh | Keeps the lists up to date | A `launchd` job runs `siteblock.sh update` once a day |

The DNS profile is encrypted, so internet providers that intercept normal DNS (common in India) cannot get around it.

## Install

```bash
git clone https://github.com/LowkyFoolDev/siteblock.git
cd siteblock
sudo ./siteblock.sh install
```

Then install the DNS profile:

1. Double-click `FamilyDNS.mobileconfig`.
2. Open **System Settings → General → Device Management** (or **Privacy & Security → Profiles**).
3. Click **Install**.

Then turn off the browser settings that skip your system DNS:

- **Chrome / Brave / Edge:** Settings → Privacy and security → Security → "Use secure DNS" → **off**
- **Firefox:** Settings → Privacy & Security → DNS over HTTPS → **Off**
- **Safari:** turn off iCloud Private Relay

Finally, quit every browser with Cmd+Q and open it again.

## Block more sites

Add one domain per line to `custom.txt` (`www.` is added automatically). Then run:

```bash
sudo ./siteblock.sh install
```

## Uninstall

```bash
sudo ./siteblock.sh uninstall
```

Then remove the profile in **System Settings → General → Device Management**.

## Limits

- This is a self-control tool, not a lock. Anyone with your admin password can remove it.
- A VPN gets around the blocks.
- The hosts file cannot use wildcards. If a new mirror domain shows up, add it to `custom.txt`.

## Block list sources

- [The Block List Project](https://github.com/blocklistproject/Lists): crypto, scam
- [Cloudflare for Families](https://one.one.one.one/family/): adult, malware

## License

MIT
