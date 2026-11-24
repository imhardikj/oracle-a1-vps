# oracle-a1-vps

Terraform for a **private-only** Oracle Cloud ARM (A1) VM: no public IP, no internet gateway, no inbound rules.
You reach it over [Tailscale](https://tailscale.com), which is installed and joined automatically at first boot.
`cloudflared` is installed as a package too, but not configured; you set up a tunnel yourself later if you want one.

```
tailnet device ──(Tailscale)──┐
                              ▼
internet ◄── NAT gateway ◄── private subnet (10.1.1.0/24) ── VM "vps"
(outbound only)                  ▲
Oracle services ◄── service gateway
```

What you get:

| | |
|---|---|
| OS | Ubuntu 24.04 (newest Canonical aarch64 image) |
| Shape | `VM.Standard.A1.Flex`, 4 OCPU / 24 GB RAM / 200 GB boot volume (the whole Always Free A1 allowance) |
| Login | one user, `username`, with passwordless sudo. The stock `ubuntu` user is not created |
| Auth | Tailscale SSH only. No SSH keys exist on the machine |
| Inbound from the internet | nothing, by design |
| Packages | git, curl, wget, vim, htop, tmux, jq, unzip, Tailscale, cloudflared |

## 1. Prerequisites (one-time)

Skip any step you have already done for another OCI project.

### 1.1 Tools (macOS shown)

```bash
brew install oci-cli
brew tap hashicorp/tap && brew install terraform   # or: mise install  (uses mise.toml)
```

### 1.2 OCI account and API access

You need an OCI tenancy (Pay As You Go is fine; Always Free resources cost nothing within the allowance).

```bash
oci setup config
```

It asks for your user OCID, tenancy OCID and region (see below for where to find them). Let it generate an API key
pair. The VM is created in the region you enter (e.g. `ap-hyderabad-1`).
Then upload the **public** key: Console -> *User settings* -> *API keys* -> *Add API key* -> paste
`~/.oci/oci_api_key_public.pem`. Test it:

```bash
oci os ns get            # prints your Object Storage namespace; note it for step 2
```

**Where to find your OCIDs**

- **Tenancy OCID** (`ocid1.tenancy.oc1..aaaa...`), needed again as `tenancy_ocid` in step 2:
  OCI Console -> profile icon (top right) -> **Tenancy: `<your tenancy name>`** -> copy the **OCID** field.
  Once `oci setup config` has run, it is also saved in `~/.oci/config`: `grep tenancy ~/.oci/config`.
- **User OCID** (`ocid1.user.oc1..aaaa...`): OCI Console -> profile icon -> **My profile** -> copy the **OCID** field.

### 1.3 Terraform state bucket

Terraform stores its state in an OCI Object Storage bucket (created once, reusable for many projects):

```bash
oci os bucket create --compartment-id <tenancy-ocid> --name terraform-state   # tenancy OCID from step 1.2
```

### 1.4 Tailscale: ACL rules and an auth key

1. Create a Tailscale account and install the app on the devices you will connect from.
2. In the admin console -> **Access controls**, make sure the policy contains a tag owner and an SSH rule
   (merge into your existing policy; do not replace it blindly):

   ```jsonc
   "tagOwners": {
     "tag:server": ["autogroup:admin"]
   },
   "ssh": [
     {
       "action": "accept",
       "src":    ["autogroup:member"],
       "dst":    ["tag:server"],
       "users":  ["autogroup:nonroot"]
     }
   ]
   ```

   Tagged devices never need key renewal, which is what you want for a server. Without an `ssh` rule matching the
   VM, Tailscale SSH will refuse every login.
3. **Settings -> Keys -> Generate auth key**: *Reusable* off, *Ephemeral* off, expiry ~1 hour, *Tags* = `tag:server`.
   Copy it (`tskey-auth-...`). You only need it for the first boot.

## 2. Configure

```bash
git clone <this repo> && cd oracle-a1-vps

cp terraform.tfvars.example terraform.tfvars   # set tenancy_ocid, instance_name, username
cp backend.hcl.example backend.hcl             # set namespace and key
```

- `tenancy_ocid`: your tenancy OCID, see "Where to find your OCIDs" in step 1.2.
- `namespace` (in `backend.hcl`): the value printed by `oci os ns get`.
- `key` (in `backend.hcl`): the path of the state file inside the bucket. **It must be unique.** Do not reuse a key
  that any other Terraform project in the same bucket already uses; they would share one state, and Terraform would
  try to modify or destroy the other project's resources. The default `vps/terraform.tfstate` is fine for a first
  machine. If you create a second machine from this repo, give it its own key (e.g. `vps2/terraform.tfstate`).

Both copied files are git-ignored. `username` must be a plain Linux username (not `root` or `ubuntu`). If you plan to use
Cloudflare browser SSH later, make it equal to your Cloudflare Access email prefix
(`you@example.com` -> `you`).

## 3. Deploy

The Tailscale auth key is a secret, so it is **not** read from `terraform.tfvars`. Terraform picks it up from the
`TF_VAR_tailscale_auth_key` environment variable. Set it in the same shell, right before running Terraform:

```bash
export TF_VAR_tailscale_auth_key='tskey-auth-...'   # the key from step 1.4; do not write it to any file

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

The variable only lives in that shell session. If you open a new terminal, export it again before every
`plan`/`apply` (Terraform will otherwise prompt for it). After the VM has joined the tailnet the key is spent, so you
can `unset TF_VAR_tailscale_auth_key`.

After apply finishes, the VM still needs a few minutes (package upgrade, Tailscale install) to appear in your tailnet.

## 4. Connect (first login)

From any device that is on your tailnet (Mac, iPhone, iPad, ...):

```bash
ssh username@vps        # MagicDNS name = instance_name; no SSH key involved
```

Tailscale SSH authenticates you by your tailnet identity, per the ACL rule above, so there are no keys to manage.
On iPhone/iPad, use any SSH app and connect to host `vps` as `username`. (This has not been tested with specific iOS
apps; the official Tailscale app is not an SSH client, so you need a separate one.)

This is the only way in: the VM has no public IP, no open ports, and no SSH keys. If Tailscale is down, use the
serial console (next section).

## 5. If it does not appear in Tailscale

The VM is unreachable from the internet by design, so use the **OCI serial console**:
Console -> Compute -> Instances -> your instance -> *Console connection* -> create one, then connect. In it, read
`/var/log/vps-bootstrap.log` and `/var/log/cloud-init-output.log`. Common causes: expired or already-used auth key,
tag not allowed (`tagOwners`), no outbound internet.

To re-run first boot with a fresh auth key:

```bash
export TF_VAR_tailscale_auth_key='tskey-auth-<new>'
terraform apply -replace=oci_core_instance.vps
```

## 6. Using cloudflared later

The `cloudflared` binary is installed but no tunnel is configured and no service is running. After you can SSH in,
follow Cloudflare's docs to create a tunnel and `sudo cloudflared service install <token>`. The VM already has
outbound internet through the NAT gateway, which is all a tunnel needs. Note that sshd has no authorised keys, so
SSH through a tunnel needs its own login method (e.g. Cloudflare short-lived certificates); that is not set up here.

## Variables

| Variable | Required | Default | Notes |
|---|---|---|---|
| `tenancy_ocid` | yes | | See "Where to find your OCIDs" in step 1.2 |
| `instance_name` | yes | | Display name, OCI hostname and Tailscale name |
| `username` | yes | | Login user |
| `tailscale_auth_key` | yes | | Only via the `TF_VAR_tailscale_auth_key` environment variable (section 3); sensitive |
| `ocpus` / `memory_in_gbs` / `boot_volume_size_in_gbs` | no | `4` / `24` / `200` | Boot volume can only grow later |
| `vcn_cidr` / `subnet_cidr` | no | `10.1.0.0/16` / `10.1.1.0/24` | Avoid overlap with your other networks |
| `compartment_ocid` | no | tenancy root | |
| `image_ocid` | no | newest Ubuntu 24.04 aarch64 | |

## Good to know

- **Re-applying is safe.** `lifecycle.ignore_changes` covers `metadata`, so changing cloud-init or rotating the auth key
  does not recreate the VM. Bootstrap is first-boot only.
- **Always Free limits.** The A1 allowance is 4 OCPU / 24 GB / 200 GB **per account**. A second A1 VM running at the
  same time is billed at pay-as-you-go rates. Lower `ocpus`, `memory_in_gbs` and `boot_volume_size_in_gbs` if you want
  to keep a second machine cheap. A stopped VM still bills its boot volume; destroy to stop all charges.
- **Image.** By default Terraform picks the newest `Canonical-Ubuntu-24.04-aarch64-*` image in your region. If it
  reports that none was found, list the images and pick one:

  ```bash
  oci compute image list --compartment-id <tenancy-ocid> --operating-system "Canonical Ubuntu" \
    --shape VM.Standard.A1.Flex --all --query 'data[].{name:"display-name",id:id}' --output table
  ```

  then set `image_ocid = "ocid1.image..."` in `terraform.tfvars`. Use a standard (not Minimal) Arm image.
- **Capacity.** A1 capacity is intermittent in some regions. `Out of host capacity` means try again later.
- **Secrets.** The auth key is placed in instance metadata for first boot and is removed from disk once Tailscale is up.
  Use a single-use key so the leftover metadata is worthless. Terraform state contains it too, so keep the state bucket
  private.
- **Host firewall** is left at the image defaults; the OCI security list has no ingress rules at all.

## Destroy

```bash
terraform destroy
```

Then remove the machine from the Tailscale admin console.

## Status

`terraform validate` passes and the rendered cloud-config is checked, but this has not yet been applied to a real VM.
Unverified until the first real boot: cloud-init without the default user, the image's default iptables behaviour,
and the Cloudflare apt repository line.
