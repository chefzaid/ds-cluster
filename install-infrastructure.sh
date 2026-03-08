#!/bin/bash
# ==============================================================================
# install-infrastructure.sh
# Installs prerequisites and deploys infrastructure components
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR/deployments"
AUTO_APPROVE=false
SERVER_IP="${SERVER_IP:-51.68.232.240}"

for arg in "$@"; do
    case "$arg" in
        -y|--yes|--auto-approve)
            AUTO_APPROVE=true
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: $0 [--yes]"
            exit 1
            ;;
    esac
done

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()  { echo -e "${BLUE}[STEP]${NC}  $*"; }

ask() {
    local prompt="$1"
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        info "Auto-approve enabled: $prompt"
        return 0
    fi
    read -rp "$(echo -e "${YELLOW}$prompt [y/N]${NC} ")" answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

ask_default_no() {
    local prompt="$1"
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        return 1
    fi
    read -rp "$(echo -e "${YELLOW}$prompt [y/N]${NC} ")" answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

ensure_tls_secret() {
    local namespace="$1"
    local secret_name="$2"
    shift 2
    local domains=("$@")

    if kubectl get secret "$secret_name" -n "$namespace" >/dev/null 2>&1; then
        warn "TLS secret '$secret_name' already exists in namespace '$namespace', reusing it."
        return 0
    fi

    local tmpdir openssl_config cert key
    tmpdir="$(mktemp -d)"
    openssl_config="$tmpdir/openssl.cnf"
    cert="$tmpdir/tls.crt"
    key="$tmpdir/tls.key"

    {
        echo "[req]"
        echo "distinguished_name = req_distinguished_name"
        echo "x509_extensions = v3_req"
        echo "prompt = no"
        echo ""
        echo "[req_distinguished_name]"
        echo "CN = ${domains[0]}"
        echo ""
        echo "[v3_req]"
        echo "subjectAltName = @alt_names"
        echo ""
        echo "[alt_names]"
        local i=1
        for domain in "${domains[@]}"; do
            echo "DNS.$i = $domain"
            i=$((i + 1))
        done
    } > "$openssl_config"

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$key" \
        -out "$cert" \
        -config "$openssl_config" >/dev/null 2>&1

    kubectl create secret tls "$secret_name" \
        --cert="$cert" \
        --key="$key" \
        -n "$namespace" >/dev/null

    rm -rf "$tmpdir"
    info "Created TLS secret '$secret_name' in namespace '$namespace'."
}

check_dns_records() {
    local hosts=(
        "keycloak.swirlit.dev"
        "jenkins.swirlit.dev"
        "sonarqube.swirlit.dev"
        "nexus.swirlit.dev"
        "argocd.swirlit.dev"
        "grafana.swirlit.dev"
        "kibana.swirlit.dev"
        "gitlab.swirlit.dev"
        "longhorn.swirlit.dev"
    )

    for host in "${hosts[@]}"; do
        local resolved
        resolved="$(getent hosts "$host" 2>/dev/null | awk '{print $1}' | head -1 || true)"
        if [[ "$resolved" != "$SERVER_IP" ]]; then
            warn "DNS check: $host -> ${resolved:-<missing>} (expected $SERVER_IP)"
        fi
    done
}

# ---------- Combined pre-flight checks -----------------------------------------
[[ $EUID -eq 0 ]] && error "Do not run as root. The script uses sudo when needed."

info "============================================="
info " Infrastructure Installer"
info "============================================="
echo ""
echo "This script will:"
echo "  1. Install prerequisites (Java, Maven, Node.js, Docker, Ansible, K3s, Helm, Longhorn)"
echo "  2. Deploy infrastructure services (ingress, data, IAM, monitoring, logging, CI/CD, GitOps)"
echo ""

ask "Proceed with installation and deployment?" || { info "Aborted."; exit 0; }

# ---------- Prerequisites section ----------------------------------------------
step "Installing system prerequisites..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    openjdk-21-jdk \
    maven \
    docker.io \
    ansible \
    open-iscsi \
    nfs-common \
    curl \
    jq \
    git \
    > /dev/null

if ! command -v node &>/dev/null || [[ "$(node -v)" != v24* ]]; then
    info "Installing Node.js 24..."
    curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash - > /dev/null 2>&1
    sudo apt-get install -y -qq nodejs > /dev/null
fi

if ! groups "$USER" | grep -q docker; then
    info "Adding $USER to docker group (re-login required for non-sudo docker)..."
    sudo usermod -aG docker "$USER"
fi

sudo systemctl enable --now iscsid > /dev/null 2>&1

export MAVEN_OPTS="-Dhttp.proxyHost= -Dhttps.proxyHost="
grep -q "MAVEN_OPTS" ~/.bashrc 2>/dev/null || \
    echo 'export MAVEN_OPTS="-Dhttp.proxyHost= -Dhttps.proxyHost="' >> ~/.bashrc

if command -v k3s &>/dev/null; then
    warn "K3s already installed: $(k3s --version | head -1)"
    ask_default_no "Reinstall K3s?" && INSTALL_K3S=true || INSTALL_K3S=false
else
    INSTALL_K3S=true
fi

if [[ "$INSTALL_K3S" == "true" ]]; then
    info "Installing K3s (disabling Traefik, using Nginx Ingress instead)..."
    curl -sfL https://get.k3s.io | sh -s - \
        --disable traefik \
        --write-kubeconfig-mode 644

    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown "$USER":"$USER" ~/.kube/config
    export KUBECONFIG=~/.kube/config
    grep -q "KUBECONFIG" ~/.bashrc 2>/dev/null || \
        echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc

    kubectl wait --for=condition=Ready node --all --timeout=120s
fi

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

if ! command -v helm &>/dev/null; then
    info "Installing Helm 3..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash > /dev/null 2>&1
fi

if helm list -n longhorn-system 2>/dev/null | grep -q longhorn; then
    warn "Longhorn already installed."
else
    info "Installing Longhorn..."
    helm repo add longhorn https://charts.longhorn.io 2>/dev/null || true
    helm repo update > /dev/null 2>&1

    helm install longhorn longhorn/longhorn \
        --namespace longhorn-system \
        --create-namespace \
        --set defaultSettings.defaultReplicaCount=1 \
        --wait --timeout 300s

    kubectl patch storageclass longhorn -p \
        '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    kubectl patch storageclass local-path -p \
        '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' 2>/dev/null || true

    kubectl wait --for=condition=ready pod -l app=longhorn-manager \
        -n longhorn-system --timeout=180s
fi

# ---------- Infrastructure section ---------------------------------------------
command -v kubectl &>/dev/null || error "kubectl not found after prerequisites."
command -v helm &>/dev/null    || error "helm not found after prerequisites."
command -v openssl &>/dev/null || error "openssl not found after prerequisites."
kubectl cluster-info &>/dev/null || error "Cannot reach K8s cluster."

step "Creating infrastructure namespace..."
kubectl create namespace infrastructure 2>/dev/null || true

step "Ensuring HTTPS TLS secret..."
ensure_tls_secret infrastructure swirlit-dev-tls \
    keycloak.swirlit.dev \
    jenkins.swirlit.dev \
    sonarqube.swirlit.dev \
    nexus.swirlit.dev \
    argocd.swirlit.dev \
    grafana.swirlit.dev \
    kibana.swirlit.dev \
    gitlab.swirlit.dev \
    longhorn.swirlit.dev

step "Installing Nginx Ingress Controller..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo update > /dev/null 2>&1
if helm list -n infrastructure 2>/dev/null | grep -q ingress-nginx; then
    helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
        --namespace infrastructure \
        --set controller.service.type=LoadBalancer \
        --set controller.service.enableHttp=true \
        --wait --timeout 120s
else
    helm install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace infrastructure \
        --set controller.service.type=LoadBalancer \
        --set controller.service.enableHttp=true \
        --wait --timeout 120s
fi

step "Deploying core data stores..."
kubectl apply -f "$DEPLOY_DIR/postgres.yaml"
kubectl apply -f "$DEPLOY_DIR/kafka.yaml"
kubectl apply -f "$DEPLOY_DIR/redis.yaml"
kubectl apply -f "$DEPLOY_DIR/mongodb.yaml"

kubectl wait --for=condition=ready pod -l app=postgres  -n infrastructure --timeout=180s
kubectl wait --for=condition=ready pod -l app=redis     -n infrastructure --timeout=120s
kubectl wait --for=condition=ready pod -l app=mongodb   -n infrastructure --timeout=180s
kubectl wait --for=condition=ready pod -l app=zookeeper -n infrastructure --timeout=180s
kubectl wait --for=condition=ready pod -l app=kafka     -n infrastructure --timeout=180s

step "Deploying platform services..."
for f in keycloak.yaml monitoring.yaml elk.yaml jenkins.yaml sonarqube.yaml nexus.yaml gitlab.yaml ingress.yaml; do
    kubectl apply -f "$DEPLOY_DIR/$f"
done

step "Installing ArgoCD..."
if helm list -n infrastructure 2>/dev/null | grep -q argocd; then
    helm upgrade argocd argo/argo-cd \
        --namespace infrastructure \
        --set server.service.type=ClusterIP \
        --set configs.params."server\\.insecure"=true \
        --set redis.enabled=true \
        --wait --timeout 300s
else
    helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
    helm repo update > /dev/null 2>&1
    helm install argocd argo/argo-cd \
        --namespace infrastructure \
        --set server.service.type=ClusterIP \
        --set configs.params."server\\.insecure"=true \
        --set redis.enabled=true \
        --wait --timeout 300s
fi

kubectl wait --for=condition=ready pod -l app=keycloak      -n infrastructure --timeout=180s 2>/dev/null || warn "Keycloak still starting..."
kubectl wait --for=condition=ready pod -l app=jenkins        -n infrastructure --timeout=180s 2>/dev/null || warn "Jenkins still starting..."
kubectl wait --for=condition=ready pod -l app=elasticsearch  -n infrastructure --timeout=180s 2>/dev/null || warn "Elasticsearch still starting..."
kubectl wait --for=condition=ready pod -l app=kibana         -n infrastructure --timeout=180s 2>/dev/null || warn "Kibana still starting..."
kubectl wait --for=condition=ready pod -l app=logstash       -n infrastructure --timeout=180s 2>/dev/null || warn "Logstash still starting..."
kubectl wait --for=condition=ready pod -l app=gitlab         -n infrastructure --timeout=900s 2>/dev/null || warn "GitLab still starting..."

info ""
info "============================================="
info " Infrastructure installation complete!"
info "============================================="

echo ""
echo "Installed versions:"
echo "  Java: $(java -version 2>&1 | head -1)"
echo "  Maven: $(mvn -version 2>&1 | head -1)"
echo "  Node: $(node -v)"
echo "  Docker: $(docker --version)"
LONGHORN_VERSION="$(helm list -n longhorn-system -o json 2>/dev/null | jq -r '.[0].app_version // "unknown"')"
echo "  Longhorn: ${LONGHORN_VERSION}"
echo ""
echo "Service access (HTTPS via domain):"
echo "  Keycloak   https://keycloak.swirlit.dev"
echo "  Jenkins    https://jenkins.swirlit.dev"
echo "  SonarQube  https://sonarqube.swirlit.dev"
echo "  Grafana    https://grafana.swirlit.dev"
echo "  Nexus      https://nexus.swirlit.dev"
echo "  ArgoCD     https://argocd.swirlit.dev"
echo "  Kibana     https://kibana.swirlit.dev"
echo "  GitLab     https://gitlab.swirlit.dev"
echo "  Longhorn   https://longhorn.swirlit.dev"
echo ""
echo "Expected DNS target IP: $SERVER_IP"
check_dns_records

echo ""
echo "Retrieve credentials:"
echo "  Jenkins:  kubectl exec -n infrastructure deployment/jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword"
echo "  ArgoCD:   kubectl -n infrastructure get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo "  Nexus:    kubectl exec -n infrastructure deployment/nexus -- cat /nexus-data/admin.password"
echo "  GitLab:   kubectl exec -n infrastructure deployment/gitlab -- grep 'Password:' /etc/gitlab/initial_root_password"
echo "  MongoDB:  kubectl get secret -n infrastructure mongodb-secret -o jsonpath='{.data.MONGO_INITDB_ROOT_PASSWORD}' | base64 -d"
echo ""

echo "Pod status:"
kubectl get pods -n infrastructure --no-headers 2>&1 | awk '{printf "  %-50s %s\n", $1, $2}'
