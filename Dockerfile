FROM alpine:3.20

ARG HELM_VERSION=3.17.3
ARG SOPS_VERSION=3.12.2
ARG AGE_VERSION=1.3.1
ARG TARGETARCH=amd64

LABEL org.opencontainers.image.source="https://github.com/AtherOps/helm-sops-cmp" \
      org.opencontainers.image.description="ArgoCD CMP sidecar: helm + sops/age secrets decryption with auto-discovery" \
      org.opencontainers.image.licenses="MIT"

RUN apk add --no-cache curl tar gzip ca-certificates

# helm
RUN curl -sSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" \
    | tar xz -C /usr/local/bin --strip-components=1 "linux-${TARGETARCH}/helm"

# sops
RUN curl -sSL "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.${TARGETARCH}" \
    -o /usr/local/bin/sops && chmod +x /usr/local/bin/sops

# age
RUN curl -sSL "https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-${TARGETARCH}.tar.gz" \
    | tar xz -C /usr/local/bin --strip-components=1 age/age age/age-keygen

# argocd user — UID 999 matches ArgoCD's default for socket compatibility
# Alpine 3.20 uses GID 999 for the ping group, so we use GID 1000 instead
RUN addgroup -g 1000 argocd \
    && adduser -D -u 999 -G argocd argocd \
    && mkdir -p /home/argocd/cmp-server/config /home/argocd/cmp-server/plugins \
    && chown -R argocd:argocd /home/argocd

COPY --chown=argocd:argocd plugin.yaml /home/argocd/cmp-server/config/plugin.yaml
COPY --chown=argocd:argocd generate.sh /usr/local/bin/generate.sh
RUN chmod +x /usr/local/bin/generate.sh

USER 999

# argocd-cmp-server is bind-mounted at runtime via the var-files emptyDir volume
# populated by the copyutil initContainer already present in argocd-repo-server
ENTRYPOINT ["/var/run/argocd/argocd-cmp-server"]
