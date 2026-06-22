# Overview & Architecture
## Overview
This is a repo to deploy TOS on GCP with terraform
This repo focus on the scenario of Standalone TOS (1 Data Node, No Worker Node, No RC)

## Doc Reference
- [Tufin - Prepare a GCP VM Instance](https://forum.tufin.com/support/kc/latest/Content/ST2/ManagingTOS/Prepare-GCP.htm)
- [Tufin - Install TOS](https://forum.tufin.com/support/kc/aurora/Content/ST2/ManagingTOS/InstallTOS.htm)
- [Tufin - Add GCP](https://forum.tufin.com/support/kc/latest/Content/Suite/Add_GCP.htm)

# Prepare Google Cloud CLI

<details><summary><Sol 1> Install Google Cloud CLI (Windows + Powershell)</summary>
    
1.  Download & Insatll [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) for you local host.
    Run the below codes in Windows Powershell, other OS reference [doc](https://cloud.google.com/sdk/docs/install)
    ```powershell
    (New-Object Net.WebClient).DownloadFile("https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe", "$env:Temp\GoogleCloudSDKInstaller.exe")
    
    & $env:Temp\GoogleCloudSDKInstaller.exe 
    ```
    
    My preference are
    1. (Options) Turn on screen reader mode, Next
    2. (EULA) I agree
    3. (Install Tier) Check 'All user', Next
    4. (Install Path) Next
    5. (Options) Next
    6. (Install) Next
    7. (Next Steps options)Finish
    
2.  Initialize Google Cloud CLI
    ```powershell
    gcloud init
    ```
    
    My preference are
    1. (Powershell) Would you like to sign in: y
    2. (Browser) Login
    3. (Browser) Click Allow
    4. (Powershell) Select project
    5. (Powershell) Confiugre default compute region/zone: n
    

3.  Confirm gcloud installed success
    ```powershell
    gcloud -v
    ```

4.  Download & Insatll [Terraform](https://developer.hashicorp.com/terraform/install) for you local host.
    Run the below codes in Windows Powershell, other OS reference [doc](https://developer.hashicorp.com/terraform/install)

    ```powershell
    winget install HashiCorp.Terraform
    ```

5.  Confirm terraform installed success
    ```powershell
    terraform -v
    ```

6.  Download & Insatll [Git](https://git-scm.com/) for you local host.
    Run the below codes in Windows Powershell, other OS reference [doc](https://git-scm.com/)
    ```powershell
    winget install --id Git.Git -e --source winget
    ```

7.  Confirm git installed success
    ```powershell
    git -v
    ```
</details>

<details><summary><Sol 2> Directly use Cloud Shell (Linux)</summary>

> Note that in this scenario, we can't use temporary proxy to access webui, since Cloud Shell only offer http and not support https

1. Open Cloud Shell which at top-right of [Google Cloud Console](https://console.cloud.google.com/)
</details>


# Deploy
## 0. Login

```bash
gcloud auth application-default login
```

## 1. Fetch Repo
<details><summary><Case 1> Powershell</summary>

```powershell
# Repo Variables
$GIT_DIR = "terraform-google-tufin-tos"
$GIT_REPO = "https://github.com/chumicat/$GIT_DIR.git"

# Fetch Repo at v0.1
# git clone --branch v0.1 --depth 1 ${GIT_REPO} "${HOME}/${GIT_DIR}"
git clone ${GIT_REPO} "${HOME}/${GIT_DIR}"
Set-Location -Path "${HOME}/${GIT_DIR}"
```
</details>
    
<details><summary><Case 2> Linux</summary>

```bash
# Repo Variables
GIT_DIR="terraform-google-tufin-tos"
GIT_REPO="https://github.com/chumicat/${GIT_DIR}.git"

# Fetch Repo
# git clone --branch v0.1 --depth 1 ${GIT_REPO} "${HOME}/${GIT_DIR}"
git clone ${GIT_REPO} "${HOME}/${GIT_DIR}"
cd "${HOME}/${GIT_DIR}"
```
</details>

## 2. Config Variables File

### 2-1 Prepare Variable File
Copy config file from `prod.tfvars.template` to `prod.tfvars` to use.
To make config variable file process faster, let's use a cheatcode.
The following cheatcode config 'current project' + 'tos_5.1.00' package url to $TF_ARGS file directly.
    
<details><summary><Case 1> Powershell</summary>

```powershell
# Config Variables
$TF_ARGS = "prod.tfvars"
$PROJECT_ID = (gcloud config get-value project 2>$null).Trim()
Copy-Item -Path "${TF_ARGS}.template" -Destination ${TF_ARGS}

# Cheatcode Update Variables File
$content = Get-Content -Path "${TF_ARGS}" -Raw
$content = [regex]::Replace($content, '(?m)^(\s*project_id\s*=\s*)"[^"]*"', { param($m) $m.Groups[1].Value + '"' + ${PROJECT_ID} + '"' })
[System.IO.File]::WriteAllText((Resolve-Path ${TF_ARGS}), $content, [System.Text.UTF8Encoding]::new($false))

# Show Current Variables File
Write-Host "`n`n========== CURRENT VARS FILE =========="
Get-Content -Path $TF_ARGS | ForEach-Object { if ($_ -match '^#') { Write-Host $_ } else { Write-Host $_ -ForegroundColor Yellow }}
```
</details>
    
<details><summary><Case 2> Linux</summary>

```bash
# Config Variables
TF_ARGS="prod.tfvars"
PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
cp ${TF_ARGS}.template ${TF_ARGS}

# Cheatcode Update Variables File
sed -i -E "s|^([[:space:]]*project_id[[:space:]]*=[[:space:]]*)\"[^\"]*\"|\1\"${PROJECT_ID}\"|" ${TF_ARGS}

# Show Current Variables File
echo -e "\n\n========== CURRENT VARS FILE =========="
awk '/^#/ {print; next} {print "\033[33m" $0 "\033[0m"}' ${TF_ARGS}
```
</details>

<details><summary>Customize Cheatcode</summary>

```powershell
# Config Variables
$TF_ARGS = "prod.tfvars"
$SUBNET_CIDR = "10.177.111.0/24"
$PROXY_SUBNET_CIDR = "10.177.112.0/24"

# Cheatcode Update Variables File
$content = Get-Content -Path "${TF_ARGS}" -Raw
$content = [regex]::Replace($content, '(?m)^(\s*subnet_cidr\s*=\s*)"[^"]*"', { param($m) $m.Groups[1].Value + '"' + ${SUBNET_CIDR} + '"' })
$content = [regex]::Replace($content, '(?m)^(\s*proxy_subnet_cidr\s*=\s*)"[^"]*"', { param($m) $m.Groups[1].Value + '"' + ${PROXY_SUBNET_CIDR} + '"' })
[System.IO.File]::WriteAllText((Resolve-Path ${TF_ARGS}), $content, [System.Text.UTF8Encoding]::new($false))

# Show Current Variables File
Write-Host "`n`n========== CURRENT VARS FILE =========="
Get-Content -Path $TF_ARGS | ForEach-Object { if ($_ -match '^#') { Write-Host $_ } else { Write-Host $_ -ForegroundColor Yellow }}
```
</details>


### 2-2 Config Region & Zone

<details><summary><Case 1-1> Powershell (us-central1-a)</summary>

```powershell
# Config Variables
$TF_ARGS = "prod.tfvars"
$REGION = "us-central1"
$ZONE = "us-central1-a"

# Cheatcode Update Variables File
$content = Get-Content -Path "${TF_ARGS}" -Raw
$content = [regex]::Replace($content, '(?m)^(\s*region\s*=\s*)"[^"]*"', { param($m) $m.Groups[1].Value + '"' + ${REGION} + '"' })
$content = [regex]::Replace($content, '(?m)^(\s*zone\s*=\s*)"[^"]*"', { param($m) $m.Groups[1].Value + '"' + ${ZONE} + '"' })
[System.IO.File]::WriteAllText((Resolve-Path ${TF_ARGS}), $content, [System.Text.UTF8Encoding]::new($false))

# Show Current Variables File
Write-Host "`n`n========== CURRENT VARS FILE =========="
Get-Content -Path $TF_ARGS | ForEach-Object { if ($_ -match '^#') { Write-Host $_ } else { Write-Host $_ -ForegroundColor Yellow }}
```
</details>

<details><summary><Case 1-2> Powershell (asia-east1-c)</summary>

```powershell
# Config Variables
$TF_ARGS = "prod.tfvars"
$REGION = "asia-east1"
$ZONE = "asia-east1-c"

# Cheatcode Update Variables File
$content = Get-Content -Path "${TF_ARGS}" -Raw
$content = [regex]::Replace($content, '(?m)^(\s*region\s*=\s*)"[^"]*"', { param($m) $m.Groups[1].Value + '"' + ${REGION} + '"' })
$content = [regex]::Replace($content, '(?m)^(\s*zone\s*=\s*)"[^"]*"', { param($m) $m.Groups[1].Value + '"' + ${ZONE} + '"' })
[System.IO.File]::WriteAllText((Resolve-Path ${TF_ARGS}), $content, [System.Text.UTF8Encoding]::new($false))

# Show Current Variables File
Write-Host "`n`n========== CURRENT VARS FILE =========="
Get-Content -Path $TF_ARGS | ForEach-Object { if ($_ -match '^#') { Write-Host $_ } else { Write-Host $_ -ForegroundColor Yellow }}
```
</details>

<details><summary><Case 2-1> Linux (us-central1-a)</summary>

```bash
# Config Variables
TF_ARGS="prod.tfvars"
REGION="us-central1"
ZONE="us-central1-a"

# Cheatcode Update Variables File
sed -i -E "s|^([[:space:]]*region[[:space:]]*=[[:space:]]*)\"[^\"]*\"|\1\"${REGION}\"|" ${TF_ARGS}
sed -i -E "s|^([[:space:]]*zone[[:space:]]*=[[:space:]]*)\"[^\"]*\"|\1\"${ZONE}\"|" ${TF_ARGS}

# Show Current Variables File
echo -e "\n\n========== CURRENT VARS FILE =========="
awk '/^#/ {print; next} {print "\033[33m" $0 "\033[0m"}' ${TF_ARGS}
```
</details>

<details><summary><Case 2-2> Linux (asia-east1-c)</summary>

```bash
# Config Variables
TF_ARGS="prod.tfvars"
REGION="asia-east1"
ZONE="asia-east1-c"

# Cheatcode Update Variables File
sed -i -E "s|^([[:space:]]*region[[:space:]]*=[[:space:]]*)\"[^\"]*\"|\1\"${REGION}\"|" ${TF_ARGS}
sed -i -E "s|^([[:space:]]*zone[[:space:]]*=[[:space:]]*)\"[^\"]*\"|\1\"${ZONE}\"|" ${TF_ARGS}

# Show Current Variables File
echo -e "\n\n========== CURRENT VARS FILE =========="
awk '/^#/ {print; next} {print "\033[33m" $0 "\033[0m"}' ${TF_ARGS}
```
</details>

### 2-3 Config Package

<details><summary><Case 1-1> Powershell (TOS 5.1.00)</summary>

```powershell
# Config Variables
$TF_ARGS = "prod.tfvars"
$TOS_PACK_URL = "https://storage.googleapis.com/files.tufin.com/tos_5.1.00-final-34281.run.tgz"

# Cheatcode Update Variables File
$content = Get-Content -Path "${TF_ARGS}" -Raw
$content = [regex]::Replace($content, '(?m)^(\s*tos_package_url\s*=\s*)"[^"]*"', { param($m) $m.Groups[1].Value + '"' + ${TOS_PACK_URL} + '"' })
[System.IO.File]::WriteAllText((Resolve-Path ${TF_ARGS}), $content, [System.Text.UTF8Encoding]::new($false))

# Show Current Variables File
Write-Host "`n`n========== CURRENT VARS FILE =========="
Get-Content -Path $TF_ARGS | ForEach-Object { if ($_ -match '^#') { Write-Host $_ } else { Write-Host $_ -ForegroundColor Yellow }}
```
</details>

<details><summary><Case 1-2> Powershell (TOS 25-2 HF4.0.0)</summary>

```powershell
# Config Variables
$TF_ARGS = "prod.tfvars"
$TOS_PACK_URL = "https://storage.googleapis.com/files.tufin.com/tos_25-2-phf4.0.0-final-34144.run.tgz"

# Cheatcode Update Variables File
$content = Get-Content -Path "${TF_ARGS}" -Raw
$content = [regex]::Replace($content, '(?m)^(\s*tos_package_url\s*=\s*)"[^"]*"', { param($m) $m.Groups[1].Value + '"' + ${TOS_PACK_URL} + '"' })
[System.IO.File]::WriteAllText((Resolve-Path ${TF_ARGS}), $content, [System.Text.UTF8Encoding]::new($false))

# Show Current Variables File
Write-Host "`n`n========== CURRENT VARS FILE =========="
Get-Content -Path $TF_ARGS | ForEach-Object { if ($_ -match '^#') { Write-Host $_ } else { Write-Host $_ -ForegroundColor Yellow }}
```
</details>
    
<details><summary><Case 2> Linux (TOS 5.1.00)</summary>

```bash
# Config Variables
TF_ARGS="prod.tfvars"
PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
TOS_PACK_URL="https://storage.googleapis.com/files.tufin.com/tos_5.1.00-final-34281.run.tgz"

# Cheatcode Update Variables File
ESCAPED_TOS_PACK_URL=$(printf '%s\n' "$TOS_PACK_URL" | sed 's/[&/\]/\\&/g')
sed -i -E "s|^([[:space:]]*tos_package_url[[:space:]]*=[[:space:]]*)\"[^\"]*\"|\1\"${ESCAPED_TOS_PACK_URL}\"|" ${TF_ARGS}

# Show Current Variables File
echo -e "\n\n========== CURRENT VARS FILE =========="
awk '/^#/ {print; next} {print "\033[33m" $0 "\033[0m"}' ${TF_ARGS}
```
</details>

<details><summary><Case 2> Linux (TOS 25-2 HF4.0.0)</summary>

```bash
# Config Variables
TF_ARGS="prod.tfvars"
PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
TOS_PACK_URL="https://storage.googleapis.com/files.tufin.com/tos_25-2-phf4.0.0-final-34144.run.tgz"

# Cheatcode Update Variables File
ESCAPED_TOS_PACK_URL=$(printf '%s\n' "$TOS_PACK_URL" | sed 's/[&/\]/\\&/g')
sed -i -E "s|^([[:space:]]*tos_package_url[[:space:]]*=[[:space:]]*)\"[^\"]*\"|\1\"${ESCAPED_TOS_PACK_URL}\"|" ${TF_ARGS}

# Show Current Variables File
echo -e "\n\n========== CURRENT VARS FILE =========="
awk '/^#/ {print; next} {print "\033[33m" $0 "\033[0m"}' ${TF_ARGS}
```
</details>

### 2-4 Compute Capacity
Keep update `prod.tfvars`. In this part, we config compute capacity on requirement.
The following table is a simple reference for what attribute is required.
Also, feel free to use cheat code if no customize is required.

| Scale | vcpu | memory_mb | boot_disk_size_gb | etcd_disk_size_gb |
| --- | ----- | --- | --- | --- | 
| Test Startup Script<br>Insuff. resources | 2 | 4096 | 100 | 50 |
| model=small  | 20 | 81920 | 650 | 50 |
| model=medium | 24 | 98304 | 1024 | 50 |

<details><summary><Case 1-1> Powershell (Test Startup Script)</summary>

```powershell
# Config Variables
$TF_ARGS = "prod.tfvars"
$VCPU = 2
$MEMORY_MB = 4096
$BOOT_DISK_SIZE_GB = 100
$ETCD_DISK_SIZE_GB = 50

# Cheatcode Update Variables File
$content = Get-Content -Path "${TF_ARGS}" -Raw
$content = [regex]::Replace($content, '(?m)^(\s*vcpu\s*=\s*)\d+', { param($m) $m.Groups[1].Value + $VCPU })
$content = [regex]::Replace($content, '(?m)^(\s*memory_mb\s*=\s*)\d+', { param($m) $m.Groups[1].Value + $MEMORY_MB })
$content = [regex]::Replace($content, '(?m)^(\s*boot_disk_size_gb\s*=\s*)\d+', { param($m) $m.Groups[1].Value + $BOOT_DISK_SIZE_GB })
$content = [regex]::Replace($content, '(?m)^(\s*etcd_disk_size_gb\s*=\s*)\d+', { param($m) $m.Groups[1].Value + $ETCD_DISK_SIZE_GB })
[System.IO.File]::WriteAllText((Resolve-Path ${TF_ARGS}), $content, [System.Text.UTF8Encoding]::new($false))

# Show Current Variables File
Write-Host "`n`n========== CURRENT VARS FILE =========="
Get-Content -Path $TF_ARGS | ForEach-Object { if ($_ -match '^#') { Write-Host $_ } else { Write-Host $_ -ForegroundColor Yellow }}
```
</details>

<details><summary><Case 1-2> Powershell (model=small)</summary>

```powershell
# Config Variables
$TF_ARGS = "prod.tfvars"
$VCPU = 20
$MEMORY_MB = 81920
$BOOT_DISK_SIZE_GB = 650
$ETCD_DISK_SIZE_GB = 50

# Cheatcode Update Variables File
$content = Get-Content -Path "${TF_ARGS}" -Raw
$content = [regex]::Replace($content, '(?m)^(\s*vcpu\s*=\s*)\d+', { param($m) $m.Groups[1].Value + $VCPU })
$content = [regex]::Replace($content, '(?m)^(\s*memory_mb\s*=\s*)\d+', { param($m) $m.Groups[1].Value + $MEMORY_MB })
$content = [regex]::Replace($content, '(?m)^(\s*boot_disk_size_gb\s*=\s*)\d+', { param($m) $m.Groups[1].Value + $BOOT_DISK_SIZE_GB })
$content = [regex]::Replace($content, '(?m)^(\s*etcd_disk_size_gb\s*=\s*)\d+', { param($m) $m.Groups[1].Value + $ETCD_DISK_SIZE_GB })
[System.IO.File]::WriteAllText((Resolve-Path ${TF_ARGS}), $content, [System.Text.UTF8Encoding]::new($false))

# Show Current Variables File
Write-Host "`n`n========== CURRENT VARS FILE =========="
Get-Content -Path $TF_ARGS | ForEach-Object { if ($_ -match '^#') { Write-Host $_ } else { Write-Host $_ -ForegroundColor Yellow }}
```
</details>

<details><summary><Case 1-3> Powershell (model=medium)</summary>

```powershell
# Config Variables
$TF_ARGS = "prod.tfvars"
$VCPU = 24
$MEMORY_MB = 98304
$BOOT_DISK_SIZE_GB = 1024
$ETCD_DISK_SIZE_GB = 50

# Cheatcode Update Variables File
$content = Get-Content -Path "${TF_ARGS}" -Raw
$content = [regex]::Replace($content, '(?m)^(\s*vcpu\s*=\s*)\d+', { param($m) $m.Groups[1].Value + $VCPU })
$content = [regex]::Replace($content, '(?m)^(\s*memory_mb\s*=\s*)\d+', { param($m) $m.Groups[1].Value + $MEMORY_MB })
$content = [regex]::Replace($content, '(?m)^(\s*boot_disk_size_gb\s*=\s*)\d+', { param($m) $m.Groups[1].Value + $BOOT_DISK_SIZE_GB })
$content = [regex]::Replace($content, '(?m)^(\s*etcd_disk_size_gb\s*=\s*)\d+', { param($m) $m.Groups[1].Value + $ETCD_DISK_SIZE_GB })
[System.IO.File]::WriteAllText((Resolve-Path ${TF_ARGS}), $content, [System.Text.UTF8Encoding]::new($false))

# Show Current Variables File
Write-Host "`n`n========== CURRENT VARS FILE =========="
Get-Content -Path $TF_ARGS | ForEach-Object { if ($_ -match '^#') { Write-Host $_ } else { Write-Host $_ -ForegroundColor Yellow }}
```
</details>

<details><summary><Case 2-1> Linux (Test Startup Script)</summary>

```bash
# Config Variables
TF_ARGS="prod.tfvars"
VCPU=2
MEMORY_MB=4096
BOOT_DISK_SIZE_GB=100
ETCD_DISK_SIZE_GB=50

# Cheatcode Update Variables File
sed -i -E "s|^([[:space:]]*vcpu[[:space:]]*=[[:space:]]*)[0-9]+|\1${VCPU}|" "${TF_ARGS}"
sed -i -E "s|^([[:space:]]*memory_mb[[:space:]]*=[[:space:]]*)[0-9]+|\1${MEMORY_MB}|" "${TF_ARGS}"
sed -i -E "s|^([[:space:]]*boot_disk_size_gb[[:space:]]*=[[:space:]]*)[0-9]+|\1${BOOT_DISK_SIZE_GB}|" "${TF_ARGS}"
sed -i -E "s|^([[:space:]]*etcd_disk_size_gb[[:space:]]*=[[:space:]]*)[0-9]+|\1${ETCD_DISK_SIZE_GB}|" "${TF_ARGS}"

# Show Current Variables File
echo -e "\n\n========== CURRENT VARS FILE =========="
awk '/^#/ {print; next} {print "\033[33m" $0 "\033[0m"}' ${TF_ARGS}
```
</details>

<details><summary><Case 2-2> Linux (model=small)</summary>

```bash
# Config Variables
TF_ARGS="prod.tfvars"
VCPU=20
MEMORY_MB=81920
BOOT_DISK_SIZE_GB=650
ETCD_DISK_SIZE_GB=50

# Cheatcode Update Variables File
sed -i -E "s|^([[:space:]]*vcpu[[:space:]]*=[[:space:]]*)[0-9]+|\1${VCPU}|" "${TF_ARGS}"
sed -i -E "s|^([[:space:]]*memory_mb[[:space:]]*=[[:space:]]*)[0-9]+|\1${MEMORY_MB}|" "${TF_ARGS}"
sed -i -E "s|^([[:space:]]*boot_disk_size_gb[[:space:]]*=[[:space:]]*)[0-9]+|\1${BOOT_DISK_SIZE_GB}|" "${TF_ARGS}"
sed -i -E "s|^([[:space:]]*etcd_disk_size_gb[[:space:]]*=[[:space:]]*)[0-9]+|\1${ETCD_DISK_SIZE_GB}|" "${TF_ARGS}"

# Show Current Variables File
echo -e "\n\n========== CURRENT VARS FILE =========="
awk '/^#/ {print; next} {print "\033[33m" $0 "\033[0m"}' ${TF_ARGS}
```
</details>

<details><summary><Case 2-3> Linux (model=medium)</summary>

```bash
# Config Variables
TF_ARGS="prod.tfvars"
VCPU=24
MEMORY_MB=98304
BOOT_DISK_SIZE_GB=1024
ETCD_DISK_SIZE_GB=50

# Cheatcode Update Variables File
sed -i -E "s|^([[:space:]]*vcpu[[:space:]]*=[[:space:]]*)[0-9]+|\1${VCPU}|" "${TF_ARGS}"
sed -i -E "s|^([[:space:]]*memory_mb[[:space:]]*=[[:space:]]*)[0-9]+|\1${MEMORY_MB}|" "${TF_ARGS}"
sed -i -E "s|^([[:space:]]*boot_disk_size_gb[[:space:]]*=[[:space:]]*)[0-9]+|\1${BOOT_DISK_SIZE_GB}|" "${TF_ARGS}"
sed -i -E "s|^([[:space:]]*etcd_disk_size_gb[[:space:]]*=[[:space:]]*)[0-9]+|\1${ETCD_DISK_SIZE_GB}|" "${TF_ARGS}"

# Show Current Variables File
echo -e "\n\n========== CURRENT VARS FILE =========="
awk '/^#/ {print; next} {print "\033[33m" $0 "\033[0m"}' ${TF_ARGS}
```
</details>

## 3. Deploy

<details><summary><Case 1> Powershell</summary>

```powershell
# Config Variables
$TF_ARGS = "prod.tfvars"

# Deploy with terraform
terraform init
terraform plan "-var-file=$TF_ARGS" "-out=tos-plan"
terraform apply "tos-plan"
```
</details>

<details><summary><Case 2> Linux</summary>

```bash
# Config Variables
TF_ARGS="prod.tfvars"

# Deploy with terraform
terraform init
terraform plan -var-file=${TF_ARGS} -out="tos-plan"
terraform apply "tos-plan"
```
</details>

## 4. Connect and verify

<details><summary> Linux</summary>

1.  Wait 3 minutes after apply with terraform
    
    The startup script will reboot automatically.
    Wait 3 minutes for terraform deploy finished.
    Wait another 3 minutes to for startup script reboot VM Instance.
    Note that after reboot, the startup script will still running for about 10 minutes.
    
2.  Connect to Compute Engine VM Instance
    
    Open Multiple tabs, each connect to the VM Instance.
    
    ```bash
    gcloud compute ssh tos-primary --zone $ZONE --tunnel-through-iap
    ```

3.  Monitor Status
    
    Each tab run a following commands to monitor the startup script status.

    ```bash
    export P1="/etc/tufin-init-phase1-done"
    export FIN="/etc/tufin-init-done"
    watch -n 1 -c 'if [ ! -e "$P1" ]; then printf "\033[33mPhase 0\033[0m\n"; elif [ ! -e "$FIN" ]; then printf "\033[33mPhase 1\033[0m\n"; else printf "\033[32mFINISH\033[0m\n"; fi'
    ```
    ```bash
    watch tail -5 /var/log/tufin-init.log
    ```
    ```bash
    watch ls -al /opt/misc
    ```
    
    And other validations
    
    ```bash
    # Disk related
    echo -e "\033[36m=== Lsblk ===\033[0m" && lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
    echo -e "\033[36m=== Parted ===\033[0m" && sudo parted /dev/sda print && sudo parted /dev/sdb print
    echo -e "\033[36m=== Permission ===\033[0m" && ls -l /dev/disk/by-id/google-*    
    echo -e "\033[36m=== Time ===\033[0m" && timedatectl | grep zone && chronyc sources -v
    echo -e "\033[36m=== DNS ===\033[0m" && nslookup google.com
    
    echo -e "\033[36m=== Sentinels ===\033[0m" && ls /etc/tufin-init* 2>/dev/null || echo "MISSING"
    echo -e "\033[36m=== SELinux ===\033[0m" && getenforce
    echo -e "\033[36m=== Firewalld ===\033[0m" && systemctl is-active firewalld
    echo -e "\033[36m=== Wireguard ===\033[0m" && lsmod | grep -c wireguard
    echo -e "\033[36m=== etcd mount ===\033[0m" && mount | grep rancher | awk '{print $1, $3}'
    echo -e "\033[36m=== ip_forward ===\033[0m" && sysctl -n net.ipv4.ip_forward
    echo -e "\033[36m=== TOS CLI ===\033[0m" && ls /usr/local/bin/tos 2>/dev/null || echo "MISSING"
    ```
</details>
    
## 5. Install TOS (Tufin Orchestration Suite)

<details><summary> Linux</summary>

```bash
# Raise
sudo su
tmux new-session -s tosinstall
cd /opt/misc

# Install TOS (Tufin Orchestration Suite)
tos install --dry-run --modules=ST,SC --primary-vip=external --services-network=10.100.0.0/24 --load-model=small -d --accept-eula
tos install --dry-run --modules=ST,SC --primary-vip=external --services-network=10.100.0.0/24 --load-model=medium -d --accept-eula
```

```bash
# Check Health 
watch curl -k https://localhost:31443
```
</details>

## 6. Access WebGUI

<details><summary><Case 1> Powershell</summary>

```powershell
# Get LB IP, choose one to run
terraform output lb_ip
gcloud compute forwarding-rules list --regions us-central1

# Open an SSH tunnel through the VM (with LB)
$lb_ip = $(terraform output -raw lb_ip)
gcloud compute ssh tos-primary --zone=$ZONE --tunnel-through-iap --ssh-flag="-L 127.0.0.1:443:${lb_ip}:443" --ssh-flag="-N"

# Open an SSH tunnel through the VM (without LB, direct VM Instance)
gcloud compute ssh tos-primary --zone=$ZONE --tunnel-through-iap --ssh-flag="-L 127.0.0.1:443:127.0.0.1:31443" --ssh-flag="-N"

# Access
https://localhost

# Check Health 
curl -k https://localhost:31443
```
</details>
    
<details><summary><Case 2> Linux</summary>

```bash
# Get LB IP, choose one to run
terraform output lb_ip
gcloud compute forwarding-rules list --regions us-central1

# Open an SSH tunnel through the VM (with LB)
lb_ip=$(terraform output -raw lb_ip)
gcloud compute ssh tos-primary \
  --zone $ZONE \
  --tunnel-through-iap \
  -- -L 443:$lb_ip:443 -N

# Open an SSH tunnel through the VM (without LB, direct VM Instance)
gcloud compute ssh tos-primary \
  --zone $ZONE \
  --tunnel-through-iap \
  -- -L 443:127.0.0.1:31443 -N

# Access
https://localhost:8443

# Check Health 
curl -k https://localhost:31443
```
</details>



## 7. Destroy & Cleanup

<details><summary><Case 1> Powershell</summary>

```powershell
# Variables
$GIT_DIR = "terraform-google-tufin-tos"
$TF_ARGS = "prod.tfvars"

# Destroy
cd "$HOME/${GIT_DIR}"
do {
    terraform destroy "-var-file=$TF_ARGS" "-parallelism=3" "-auto-approve"

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Destroy failed. Retrying in 10 seconds..."
        Start-Sleep -Seconds 10
    }
} until ($LASTEXITCODE -eq 0)

# Cleanup
cd $HOME
Remove-Item -Recurse -Force "$HOME/${GIT_DIR}"
if (Test-Path -LiteralPath "$HOME/$GIT_DIR") { Write-Host "hadn't clear" -ForegroundColor Red } else { Write-Host "clear" -ForegroundColor Green }
```
</details>

<details><summary><Case 2> Linux</summary>

```bash
# Variables
GIT_DIR="terraform-google-tufin-tos"
TF_ARGS="prod.tfvars"

# Destroy
cd "~/${GIT_DIR}"
until terraform destroy -var-file=${TF_ARGS} -parallelism=3 -auto-approve; do
    echo "Destroy failed. Retrying in 10 seconds..."
    sleep 10
done

# Cleanup
cd ~
rm -rf ~/${GIT_DIR}
if [ -e "$HOME/${GIT_DIR}" ]; then echo -e "\033[31mhadn't clear\033[0m"; else echo -e "\033[32mclear\033[0m"; fi
```
</details>