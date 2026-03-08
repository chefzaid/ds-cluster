# ds-cluster

Infrastructure repository Dedicated Server (DS) cluster. It owns cluster prerequisites, infrastructure manifests, ingress/platform services, GitOps wiring, and infrastructure automation.

## 🛠 Technologies Used

### Infrastructure & DevOps
*   **Orchestration**: Kubernetes (K3s - Lightweight Kubernetes)
*   **Storage**: Longhorn (distributed block storage)
*   **Ingress**: Nginx Ingress Controller
*   **Containerization**: Docker
*   **CI/CD**: Jenkins (K8s-native build agents)
*   **GitOps**: ArgoCD
*   **Code Quality**: SonarQube
*   **Artifacts**: Nexus Repository Manager OSS
*   **Source Control**: GitLab
*   **Monitoring**: Prometheus, Grafana
*   **Logging**: ELK Stack (Elasticsearch, Logstash, Kibana)
*   **NoSQL Database**: MongoDB
*   **Automation**: Ansible

> **Note on Nexus**:
>
> *   ConfigMaps for `settings.xml` and `.npmrc` are deployed for Jenkins agents, but mirroring is disabled by default.
> *   **Setup Required**:
>     1.  Login to Nexus (`https://nexus.swirlit.dev`), retrieve admin password: `kubectl exec -n infrastructure deployment/nexus -- cat /nexus-data/admin.password`
>     2.  Create repositories: Maven `maven-public` (Group proxying Central), NPM `npm-group`, Docker hosted on port 5000.
>     3.  Update Jenkins ConfigMaps with credentials and uncomment Nexus mirror configuration.

## 🏗 Infrastructure Architecture

The cluster uses Nginx ingress for HTTPS traffic management and namespace isolation (`infrastructure` + `application`).

### Traffic Flow (Platform View)
1.  **Client/Browser** connects to **Nginx Ingress Controller** over HTTPS.
2.  Ingress routes infrastructure hosts (Keycloak, Jenkins, SonarQube, Nexus, GitLab, ArgoCD, Grafana, Kibana, Longhorn).
3.  App traffic routing and app workload manifests are owned by the application repository.

### Centralized Logging (ELK Stack)
*   **Logstash** collects logs from:
    *   **TCP input** (port 5000): application logs (JSON).
    *   **Kafka input**: order events from `order_topic` and `order_result_topic`.
*   **Elasticsearch** stores logs in `app-logs-*` indices.
*   **Kibana** provides search/visualization (`https://kibana.swirlit.dev`).

## 📦 Current Deployment

### Service Access

> Ingress public IP: **`51.68.232.240`**  
> Internal ClusterIP values below reflect the current cluster state and may change if services are recreated.

#### Infrastructure Services

| Service | Endpoint (Domain **or** IP:Port) | Access | Use |
|---------|----------------------------------|--------|-----|
| **GitLab** | `https://gitlab.swirlit.dev` | Public | Source code hosting and Git remote (`root` + initial password from pod) |
| **Jenkins** | `https://jenkins.swirlit.dev` | Public | CI/CD pipelines |
| **ArgoCD** | `https://argocd.swirlit.dev` | Public | GitOps sync and app delivery |
| **Nexus** | `https://nexus.swirlit.dev` | Public | Artifact repository |
| **SonarQube** | `https://sonarqube.swirlit.dev` | Public | Code quality and static analysis |
| **Keycloak** | `https://keycloak.swirlit.dev` | Public | OIDC provider (admin/admin by default) |
| **Grafana** | `https://grafana.swirlit.dev` | Public | Dashboards and monitoring UI |
| **Kibana** | `https://kibana.swirlit.dev` | Public | Log search and visualization |
| **Longhorn UI** | `https://longhorn.swirlit.dev` | Public | Persistent volume management |
| **PostgreSQL** | `10.43.129.209:5432` | Internal | Primary DB for user-app, order-app, and Keycloak |
| **MongoDB** | `mongodb.infrastructure.svc.cluster.local:27017` | Internal | Document database for infrastructure/application workloads |
| **Redis** | `10.43.206.215:6379` | Internal | Cache backend for application services |
| **Kafka** | `kafka.infrastructure.svc.cluster.local:9092` | Internal | Event bus for order saga events |
| **Zookeeper** | `zookeeper.infrastructure.svc.cluster.local:2181` | Internal | Coordination service for Kafka |
| **Elasticsearch** | `10.43.167.56:9200` | Internal | Log storage/indexing backend |
| **Logstash** | `10.43.57.31:5000` | Internal | Log/event ingestion pipeline |
| **Prometheus** | `10.43.43.138:9090` | Internal | Metrics scraping and storage |
| **Ingress (NGINX)** | `51.68.232.240:443` | Public | HTTPS entrypoint and host/path routing |

### K8s Namespaces

| Namespace | Contents |
|-----------|----------|
| `infrastructure` | PostgreSQL, MongoDB, Kafka, Zookeeper, Redis, Keycloak, Prometheus, Grafana, Jenkins, SonarQube, Nexus, GitLab, ArgoCD, Nginx Ingress, ELK (Elasticsearch, Logstash, Kibana) |
| `application` | Application services (owned/deployed from the application repo) |
| `longhorn-system` | Longhorn storage manager |

## 🚀 Quick Start (Fresh Server)

### Prerequisites
- Ubuntu 22.04+ server with 8+ CPUs, 16+ GB RAM, 100+ GB disk
- Sudo access

### Automated Installation (Recommended)

Use the combined one-click script:

```bash
chmod +x install-infrastructure.sh
./install-infrastructure.sh
```

### Manual Installation

#### 1. Install System Dependencies
```bash
sudo apt install -y openjdk-21-jdk maven docker.io ansible open-iscsi nfs-common curl jq
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt install -y nodejs
sudo usermod -aG docker $USER
sudo systemctl enable --now iscsid
```

#### 2. Install Kubernetes
```bash
curl -sfL https://get.k3s.io | sh -s - --disable traefik --write-kubeconfig-mode 644
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
```

#### 3. Install Helm & Longhorn
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm repo add longhorn https://charts.longhorn.io && helm repo update
helm install longhorn longhorn/longhorn --namespace longhorn-system --create-namespace \
    --set defaultSettings.defaultReplicaCount=1
kubectl patch storageclass longhorn -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

#### 4. Install Nginx Ingress (Helm)
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx --namespace infrastructure --create-namespace \
    --set controller.service.type=LoadBalancer \
    --set controller.service.enableHttp=true
```

#### 5. Deploy Infrastructure
```bash
kubectl create namespace infrastructure

# Create TLS secret for infrastructure ingress
kubectl create secret tls swirlit-dev-tls --cert=tls.crt --key=tls.key -n infrastructure --dry-run=client -o yaml | kubectl apply -f -

for f in postgres kafka redis mongodb keycloak monitoring elk jenkins sonarqube nexus gitlab ingress; do
    kubectl apply -f ${f}.yaml
done
```

#### 6. Install ArgoCD (Helm)
```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n infrastructure \
    --set server.service.type=ClusterIP \
    --set configs.params."server\.insecure"=true \
    --set redis.enabled=true
```

## 🔧 Post-Install Checklist (Infrastructure)

### 1. DNS Records in Cloudflare (Required)
Create these DNS records in your Cloudflare zone, all pointing to `51.68.232.240`:

| Type | Name | Value | Proxy |
|------|------|-------|-------|
| A | `keycloak` | `51.68.232.240` | Proxied |
| A | `jenkins` | `51.68.232.240` | Proxied |
| A | `sonarqube` | `51.68.232.240` | Proxied |
| A | `nexus` | `51.68.232.240` | Proxied |
| A | `gitlab` | `51.68.232.240` | Proxied |
| A | `argocd` | `51.68.232.240` | Proxied |
| A | `grafana` | `51.68.232.240` | Proxied |
| A | `kibana` | `51.68.232.240` | Proxied |
| A | `longhorn` | `51.68.232.240` | Proxied |

### 2. Replace Temporary Self-Signed Cert with Cloudflare Origin Certificate
The scripts create `swirlit-dev-tls` automatically with a self-signed cert. Replace it with Cloudflare Origin cert:

1. Cloudflare Dashboard → **SSL/TLS** → **Origin Server** → **Create Certificate**
2. Hostnames: `keycloak.swirlit.dev`, `jenkins.swirlit.dev`, `sonarqube.swirlit.dev`, `nexus.swirlit.dev`, `gitlab.swirlit.dev`, `argocd.swirlit.dev`, `grafana.swirlit.dev`, `kibana.swirlit.dev`, `longhorn.swirlit.dev`, `*.swirlit.dev`
3. Save certificate and private key as local files (`tls.crt`, `tls.key`)
4. Apply them:

```bash
kubectl create secret tls swirlit-dev-tls --cert=tls.crt --key=tls.key -n infrastructure --dry-run=client -o yaml | kubectl apply -f -
```

5. In Cloudflare SSL/TLS mode, select **Full (strict)**

### 3. Jenkins Setup (Required for CI/CD)
```bash
# Get initial admin password
kubectl exec -n infrastructure deployment/jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword

# Access Jenkins at https://jenkins.swirlit.dev
# 1. Install suggested plugins + "Kubernetes" plugin
# 2. Configure Kubernetes cloud:
#    - Manage Jenkins → Clouds → New Cloud → Kubernetes
#    - Kubernetes URL: https://kubernetes.default.svc
#    - Jenkins URL: http://jenkins.infrastructure.svc.cluster.local:8080
#    - Jenkins tunnel: jenkins.infrastructure.svc.cluster.local:50000
#    - Namespace: infrastructure
# 3. Create a Pipeline job pointing to app repo
#    - SCM: Git → <application-repository-url>
#    - Script Path: Jenkinsfile
```

### 4. GitLab Setup (SCM)
```bash
# Access GitLab at https://gitlab.swirlit.dev
# First startup can take several minutes
kubectl wait --for=condition=ready pod -n infrastructure -l app=gitlab --timeout=1200s

# Get initial root password (username is: root)
kubectl exec -n infrastructure deployment/gitlab -- awk '/Password:/ {print $2}' /etc/gitlab/initial_root_password
```

### 5. ArgoCD Setup (GitOps)
```bash
# Get initial admin password
kubectl -n infrastructure get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Access ArgoCD at https://argocd.swirlit.dev
# Login with admin / <password from above>
# Two applications are pre-configured:
#   - Infrastructure application definitions are managed from the application repository
# ArgoCD auto-syncs on git push (self-heal enabled)
```

### 6. Change Default Passwords (Security)
```bash
# PostgreSQL: Update secret in postgres.yaml (base64 encoded)
# Change before production use!
echo -n 'YOUR_NEW_PASSWORD' | base64

# MongoDB: Update root username/password in mongodb.yaml (base64 encoded)
# Change before production use!
echo -n 'YOUR_NEW_MONGODB_PASSWORD' | base64

# Keycloak admin password: Update KEYCLOAK_ADMIN_PASSWORD in keycloak.yaml
# SonarQube: Change admin password on first login
# Grafana: Change admin password on first login
# Nexus: Retrieve and change on first login
```

## 🔀 Adding More Nodes

K8s makes it easy to scale horizontally:

```bash
# On the master node, get the join token:
sudo cat /var/lib/rancher/k3s/server/node-token

# On the new worker node:
curl -sfL https://get.k3s.io | K3S_URL=https://<MASTER_IP>:6443 K3S_TOKEN=<TOKEN> sh -

# Longhorn will automatically replicate data to new nodes.
# Increase replica count:
kubectl edit settings -n longhorn-system default-replica-count
# Change from 1 to 2 (or 3 for 3+ nodes)
```

## 📊 Monitoring & Logging

- **Prometheus** scrapes metrics from application services.
- **Grafana** connects to Prometheus and Elasticsearch datasources (auto-provisioned). Import Spring Boot dashboard ID `12900` for JVM metrics.
- **ELK Stack**: Application logs are shipped to Logstash, stored in Elasticsearch, and searchable via Kibana.
- **Kibana**: Access at `https://kibana.swirlit.dev`. Create index pattern `app-logs-*` to browse logs.

## 🔄 Deployment Methods: Script vs Ansible

### Combined Script (`install-infrastructure.sh`)
**Best for**: Fresh bare-metal installs, single-server setups, quick bootstrapping.  
This single script performs both prerequisite installation and infrastructure deployment.

### Ansible (`ansible/deploy.yml`)
**Best for**: Multi-node deployments, repeatable provisioning, team environments.

```bash
ansible-playbook ansible/deploy.yml
```

Ansible excels when managing multiple servers (inventory-based), enforcing idempotent state, and integrating with existing automation.

## License
GPL 3.0
