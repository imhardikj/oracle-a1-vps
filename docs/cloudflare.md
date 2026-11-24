# Cloudflare: tunnel + SSH from any browser or `cloudflared`

Optional second way in, on top of Tailscale. It gives you:

- **Browser SSH**: open `https://<ssh-hostname>` in any browser and get a terminal (emergency access).
- **`cloudflared access ssh`**: normal `ssh` from a machine that has `cloudflared` installed.

Both use one Cloudflare Access application and one tunnel. **Nothing is opened on the VM or in OCI.** The tunnel is an
outbound connection from the VM, and the VM already has outbound internet through the NAT gateway.

```
browser / ssh ──► Cloudflare Access (login) ──► Cloudflare ◄── tunnel (outbound) ── VM: cloudflared ──► sshd 127.0.0.1:22
```

Authentication is a **short-lived SSH certificate** that Cloudflare issues after you pass Access. The VM has no SSH keys,
so sshd is told to trust Cloudflare's certificate authority instead.

Placeholders used below: `<domain>` is your Cloudflare-managed domain, `<ssh-hostname>` is the hostname you pick
(e.g. `ssh-vps.<domain>`), `<username>` is the Linux user you set in `terraform.tfvars`, `<your-email>` is the email you
log in to Cloudflare Access with.

## Read this first

- **The Linux username must equal your email prefix.** Browser SSH requires it: `you@gmail.com` -> user `you`.
  If `<username>` differs, browser SSH will not log you in.
- **Whoever passes the Access policy gets a shell as `<username>`, which has passwordless sudo.** Keep the policy to
  exactly your own email, and prefer a login method with MFA.
- **Use a new hostname.** If an older machine already serves `<ssh-hostname>` through its own tunnel, a hostname can point
  at only one tunnel. Pick a different name now and move the old one over when you cut over.
- Cloudflare marks the short-lived-certificate method used here as *legacy / not recommended for new deployments* and
  points to "Access for Infrastructure". As far as the docs read when this was written, browser-rendered SSH is
  documented only for the legacy method, and Access for Infrastructure uses the Cloudflare One client instead of a
  browser terminal. Check the current docs if you want to avoid the legacy method.
- Tailscale keeps working independently. Don't remove it.

## Part 1: Cloudflare dashboard

1. **Create the tunnel.** Zero Trust -> Networking -> Tunnels -> *Create a tunnel* -> *Cloudflared*, name it (e.g. `vps`).
   On the install screen, **copy the token** (the long string in the install command) but do **not** run that command;
   Part 2 installs it in a safer way. Treat the token like a password.
2. **Add the route.** In the tunnel, *Routes* -> *Add route* -> *Published application*: pick your domain and
   subdomain (`<ssh-hostname>`), set the service to **SSH** and `localhost:22`. This creates the DNS record.
3. **Create the Access application.** Zero Trust -> Access controls -> Applications -> *Add an application* ->
   *Self-hosted*. Use the same hostname. Add one **Allow** policy with *Emails* = `<your-email>`. (Browser-rendered apps
   accept only Allow or Block policies.)
4. **Turn on browser rendering.** Edit the application -> enable *Allow access through browser-based RDP, SSH, or VNC
   sessions* -> choose **SSH** -> save.
5. **Generate the certificate authority.** Zero Trust -> Access controls -> *Service credentials* -> *SSH* ->
   *Add a certificate* -> choose the application -> *Generate certificate*. Select the new row and **copy the CA public
   key** (one line, starts with `ecdsa-sha2-...`).

## Part 2: On the VM

SSH in over Tailscale (`ssh <username>@<instance_name>`) and **keep that session open** until everything below is
tested, so a mistake can't lock you out.

**a. Run the tunnel as a service** (the token is stored in a root-only file, not on the command line):

```bash
sudo install -d -m 0755 /etc/cloudflared
sudo bash -c 'umask 077; read -rsp "Tunnel token: " T; echo; printf "%s" "$T" > /etc/cloudflared/token'

sudo tee /etc/systemd/system/cloudflared.service >/dev/null <<EOF
[Unit]
Description=Cloudflare Tunnel client
After=network-online.target
Wants=network-online.target

[Service]
TimeoutStartSec=15
Type=notify
ExecStart=$(command -v cloudflared) --no-autoupdate tunnel run --token-file /etc/cloudflared/token
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now cloudflared
systemctl status cloudflared --no-pager
```

The tunnel should show **Healthy** in the dashboard within a minute. (`--no-autoupdate` because apt updates the
package.)

**b. Make sshd trust the Cloudflare CA:**

```bash
sudo tee /etc/ssh/ca.pub >/dev/null      # paste the CA public key, press Enter, then Ctrl-D

printf 'PubkeyAuthentication yes\nTrustedUserCAKeys /etc/ssh/ca.pub\n' | sudo tee /etc/ssh/sshd_config.d/10-cloudflare.conf >/dev/null

sudo sshd -t && sudo systemctl reload ssh
sudo sshd -T | grep -i trustedusercakeys     # should print /etc/ssh/ca.pub
```

If `sshd -t` prints an error, fix it before reloading. Password logins stay disabled.

## Part 3: Test

1. **Browser:** open `https://<ssh-hostname>`, log in through Access, and you should get a terminal as `<username>`.
2. **From a Mac (or any machine with `cloudflared`):**

   ```bash
   cloudflared access ssh-config --hostname <ssh-hostname> --short-lived-cert
   ```

   Add the printed block to `~/.ssh/config`, then `ssh <username>@<ssh-hostname>`. A browser window opens for the Access
   login, and `cloudflared` obtains a certificate for you.
3. Confirm Tailscale SSH still works from another terminal.

## If something fails

- **Browser says it can't connect / tunnel not healthy:** `journalctl -u cloudflared -n 50 --no-pager` on the VM
  (via Tailscale). Check that the token was pasted whole and the route's service is `SSH` -> `localhost:22`.
- **Login loops or "permission denied (publickey)":** usually the CA key or the username. Verify the output of
  `sshd -T | grep -i trustedusercakeys`, that `/etc/ssh/ca.pub` holds the CA key from *this* application, and that the
  Linux username equals your email prefix. `sudo journalctl -u ssh -n 50 --no-pager` shows why sshd refused.
- **To remove it all:** `sudo systemctl disable --now cloudflared`, delete the files above, and delete the tunnel, route,
  application and certificate in the dashboard.
