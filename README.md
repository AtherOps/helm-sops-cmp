# helm-sops-cmp

ArgoCD Config Management Plugin (CMP) sidecar that renders Helm charts with SOPS/age-encrypted secret files.

**Image:** `ghcr.io/atherops/helm-sops-cmp:latest`

## What it does

Runs as a sidecar in `argocd-repo-server`. When ArgoCD syncs an app, this plugin:

1. Auto-discovers or reads an explicit list of value files
2. Decrypts any `secrets://`-prefixed files (or convention-matched files) using `sops` + `age`
3. Renders the Helm chart with `helm template` and returns manifests to ArgoCD

## Tools included

| Tool | Version |
|------|---------|
| helm | 3.17.3 |
| sops | 3.12.2 |
| age  | 1.3.1  |

## Usage

### 1. Store your age private key as a K8s secret

```bash
kubectl create secret generic helm-secrets-private-keys -n argocd \
  --from-file=key.txt=~/.config/sops/age/keys.txt
```

### 2. Patch argocd-repo-server

Use the standalone installer (works with any ArgoCD install):

```bash
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
  ./install/patch-repo-server.sh
```

Or add to your ArgoCD Helm values (`argo/argo-cd` chart):

```yaml
repoServer:
  volumes:
    - name: helm-secrets-private-keys
      secret:
        secretName: helm-secrets-private-keys
  extraContainers:
    - name: helm-sops-cmp
      command: [/var/run/argocd/argocd-cmp-server]
      image: ghcr.io/atherops/helm-sops-cmp:latest
      imagePullPolicy: Always
      env:
        - name: SOPS_AGE_KEY_FILE
          value: /helm-secrets-private-keys/key.txt
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: {drop: [ALL]}
        readOnlyRootFilesystem: true
        runAsNonRoot: true
        seccompProfile: {type: RuntimeDefault}
      volumeMounts:
        - {mountPath: /var/run/argocd,                 name: var-files}
        - {mountPath: /home/argocd/cmp-server/plugins, name: plugins}
        - {mountPath: /helm-secrets-private-keys/,     name: helm-secrets-private-keys}
        - {mountPath: /tmp,                            name: tmp}
```

### 3. Create ArgoCD Applications

**Auto-discovery mode** (zero config — recommended):

```yaml
source:
  path: my-app
  plugin:
    name: helm-secrets
```

The plugin automatically discovers value files by convention:

| File | Treatment |
|------|-----------|
| `../global-values.yaml` | Plain values (repo-wide) |
| `../global-secrets.yaml` | SOPS-decrypt (repo-wide secrets) |
| `values.yaml` | Plain values |
| `secrets/*.yaml` | SOPS-decrypt |
| `secrets.yaml` | SOPS-decrypt |

**Explicit mode** (full control):

```yaml
source:
  plugin:
    name: helm-secrets
    env:
      - name: HELM_VALUE_FILES
        value: "values.yaml|../shared.yaml|secrets://secrets/secret.yaml"
```

Format: pipe-separated list. Prefix `secrets://` to decrypt with sops.

## Encrypt a secret file

```bash
# .sops.yaml must be present with your age recipient
sops --encrypt secrets/secret.yaml > secrets/secret.yaml.enc
mv secrets/secret.yaml.enc secrets/secret.yaml
```

## Versioning

Images are tagged:
- `latest` — latest commit on main
- `v1.2.3` — semver release tag
- `sha-abc1234` — commit SHA

To pin a version in production, use a specific tag or SHA instead of `latest`.

## Building locally

```bash
docker build \
  --build-arg HELM_VERSION=3.17.3 \
  --build-arg SOPS_VERSION=3.12.2 \
  --build-arg AGE_VERSION=1.3.1 \
  -t helm-sops-cmp:local .
```
