# Django on k3s with Hetzner Autoscaling

This project provides a complete Infrastructure as Code (IaC) solution for deploying a Django application on a k3s cluster in Hetzner Cloud. The infrastructure is designed to be scalable, cost-effective, and fully automated using GitOps principles.

## Core Components

| Component                 | Version        | Description                                                                 |
| ------------------------- | -------------- | --------------------------------------------------------------------------- |
| Terraform hcloud Provider | `1.51.0`       | Manages the underlying cloud infrastructure on Hetzner Cloud.               |
| k3s                       | `v1.32.6+k3s1` | A lightweight, production-ready Kubernetes distribution.                    |
| ArgoCD                    | `stable`       | A declarative, GitOps continuous delivery tool for Kubernetes.              |
| cert-manager              | `v1.18.2`      | Automates the management and issuance of TLS certificates.                  |
| cloudnative-pg            | `0.24.0`       | A Kubernetes operator for PostgreSQL, providing a highly available database. |
| hcloud-ccm                | `v1.24.0`      | The Hetzner Cloud Controller Manager, integrating the cluster with the cloud. |
| hcloud-csi                | `v2.16.0`      | The Hetzner CSI driver, providing persistent storage for the cluster.       |
| ingress-nginx             | `4.13.0`       | An Ingress controller for Kubernetes using NGINX as a reverse proxy.        |
| kube-prometheus-stack     | `75.9.0`       | A collection of Kubernetes manifests, Grafana dashboards, and Prometheus rules. |
| sealed-secrets            | `2.17.3`       | A Kubernetes controller and tool for one-way encrypted Secrets.             |
| Cluster Autoscaler        | `9.36.0`       | Automatically adjusts the size of the Kubernetes cluster.                   |
| Loki                      | `6.6.1`        | A horizontally-scalable, highly-available, multi-tenant log aggregation system. |
| Promtail                  | `6.15.5`       | An agent which ships the contents of local logs to a private Loki instance. |

## Prerequisites

- A Hetzner Cloud account and API token.
- A domain name.
- `terraform` CLI installed.
- `ansible` CLI installed.
- `kubectl` CLI installed and configured to access your cluster.
- `kubeseal` CLI installed (see instructions below).
- A Git repository to store your Kubernetes manifests.
- Docker with `buildx` enabled (this is default on modern Docker Desktop).

## 1. Setup

1.  **Clone this repository.**

2.  **Configure Hetzner Cloud:**

    - Create a new project in the Hetzner Cloud console.
    - Generate an API token and save it securely.

3.  **Configure Terraform:**

    - Navigate to the `terraform` directory.
    - Create a `terraform.tfvars` file by copying the example:
      ```bash
      cp terraform.tfvars.example terraform.tfvars
      ```
    - Edit `terraform/terraform.tfvars` and fill in your details. This file includes your Hetzner token, desired server types, SSH key information, and your local IP for firewall access.

4.  **Configure Ansible:**

    - Make sure the dynamic inventory script is executable:
      ```bash
      chmod +x ansible/inventory.tf.py
      ```

5.  **Configure Kubernetes Manifests:**
    - The Kubernetes manifests are now managed by Kustomize to make configuration easier and less error-prone. Instead of editing individual files, you will update the `kustomization.yaml` files.
    - **Root Application:** In `kubernetes/kustomization.yaml`, `root-app.yaml`, replace the placeholder Git repository URL (`https://github.com/your-repo/k3s-infra.git`) with your own.
    - **Django Application:** In `kubernetes/apps/django/kustomization.yaml`, replace the placeholder Docker image and domain name with your own. Update the `kubernetes/apps/django/configmap.yaml` with your project's settings.
    - In `kubernetes/apps/postgres/cluster.yaml`, replace `your_db_name` and `your_db_user` with your desired database name and user.

## 2. Building Your Docker Images (For Mac M1/M2/M3 Users)

Because your local machine (ARM64) has a different architecture than your Hetzner servers (AMD64), you must create multi-platform Docker images. You will also need two separate images: one for your Django application and one for the Nginx static server.

1.  **Build the Django App Image:**

    ```bash
    docker buildx build --platform linux/amd64,linux/arm64 -t your-docker-hub-username/django-app:latest -f src/Dockerfile.django --push .
    ```

2.  **Build the Nginx Static Image:**
    ```bash
    docker buildx build --platform linux/amd64,linux/arm64 -t your-docker-hub-username/nginx-static:latest -f src/Dockerfile.nginx --push .
    ```

**IMPORTANT NOTES:**

- Replace `your-docker-hub-username/django-app:latest` and `your-docker-hub-username/nginx-static:latest` with your actual image names.
- The `--push` flag is required for multi-platform builds. It builds and pushes the image to your container registry at the same time.
- You must be logged into your Docker registry (`docker login`) before running these commands.

## 3. Deployment

1.  **Provision Infrastructure:**

    - Navigate to the `terraform` directory and run:
      ```bash
      terraform init
      terraform apply
      ```

2.  **Install k3s:**

    - Navigate to the `ansible` directory and run the playbook. This will install k3s on the master node using the `k3s` role and then join the workers to the cluster.
      ```bash
      ansible-playbook -i inventory.tf.py playbook.yml
      ```

3.  **Setup GitOps with Argo CD:**
    - **Install Argo CD:**
      ```bash
      kubectl create namespace argocd
      kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
      ```
    - **Push your Kubernetes manifests to your Git repository.**
    - **Bootstrap the infrastructure:**
      ```bash
      kubectl apply -k kubernetes/
      ```

## 4. Managing Secrets with Sealed Secrets

Your application secrets are managed securely using Sealed Secrets. This allows you to store encrypted secrets safely in your Git repository.

### First-Time Setup

1.  **Install the `kubeseal` CLI:**
    - On macOS: `brew install kubeseal`
    - For other platforms, see the [official documentation](https://github.com/bitnami-labs/sealed-secrets#installation).

2.  **Fetch the Sealing Key:**
    - Once the Sealed Secrets controller is running in your cluster (deployed via ArgoCD), you can fetch the public key required for sealing your secrets. You only need to do this once.
    ```bash
    kubeseal --fetch-cert > pub-sealed-secrets.pem
    ```
    - It is recommended to save this `pub-sealed-secrets.pem` file in a secure location outside the project repository. **Do not commit this file to Git.**

### How to Create and Update Secrets

The process is the same for all secrets. You create a standard Kubernetes `Secret` in a local YAML file, and then use `kubeseal` to encrypt it.

**General Workflow:**

```bash
# Create a standard Kubernetes secret file (e.g., local-secret.yaml)
# DO NOT COMMIT THIS FILE

# Seal the secret using the public key
kubeseal --cert pub-sealed-secrets.pem --format=yaml < local-secret.yaml > sealed-secret.yaml

# Commit the new sealed-secret.yaml file to your Git repository
```

### Project Secrets

This project requires the following secrets to be created:

1.  **Django Application Secrets (`django-secrets`):**
    - Contains the Django `SECRET_KEY`, `ALLOWED_HOSTS`, and any other sensitive application settings.
    - **Target file:** `kubernetes/apps/django/sealed-secret.yaml`
    - **Example `local-secret.yaml`:**
      ```yaml
      apiVersion: v1
      kind: Secret
      metadata:
        name: django-secrets
        namespace: default
      stringData:
        SECRET_KEY: "your-super-long-and-random-secret-key"
        ALLOWED_HOSTS: "your-domain.com,www.your-domain.com"
      ```

2.  **PostgreSQL Backup Credentials (`postgres-backup-credentials`):**
    - Contains the credentials for your Hetzner Storage Box.
    - **Target file:** `kubernetes/apps/postgres/backup-credentials-sealed.yaml`
    - **Example `local-secret.yaml`:**
      ```yaml
      apiVersion: v1
      kind: Secret
      metadata:
        name: postgres-backup-credentials
        namespace: default
      stringData:
        AWS_ACCESS_KEY_ID: "<your-storage-box-username>"
        AWS_SECRET_ACCESS_KEY: "<your-storage-box-password>"
      ```

3.  **Hetzner API Token (`hcloud-api-token`):**
    - Contains your Hetzner Cloud API token for the Cluster Autoscaler.
    - **Target file:** `kubernetes/argocd/hcloud-api-token-sealed.yaml`
    - **Example `local-secret.yaml`:**
      ```yaml
      apiVersion: v1
      kind: Secret
      metadata:
        name: hcloud-api-token
        namespace: kube-system
      stringData:
        token: "<your-hetzner-cloud-api-token>"
      ```

After creating and sealing each of these secrets, commit the resulting `sealed-secret.yaml` files to your repository. Argo CD will automatically sync them, and the Sealed Secrets controller will decrypt them into usable Kubernetes secrets in the cluster.

## 5. PostgreSQL Backups

The `cloudnative-pg` operator is configured to perform daily backups to a Hetzner Storage Box. This provides an off-site, S3-compatible destination for your database backups.

**You must create the Storage Box manually:**

1.  Log in to your **Hetzner Robot** account (this is separate from the Cloud Console).
2.  Navigate to "Storage Boxes" and order one. The smallest size is sufficient to start.
3.  Once the Storage Box is active, note its connection details (hostname/endpoint, username, and password).

**Next, configure Kubernetes:**

1.  Update the `data` section in `kubernetes/apps/postgres/backup-configmap.yaml` with your Storage Box endpoint and desired S3 bucket path.
2.  Create a `SealedSecret` named `postgres-backup-credentials` in the `default` namespace containing your Storage Box username and password as the `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` respectively.

## 7. Security

This project is configured with several security best practices:

- **Pod Security Context:** All application pods (Django, Celery, Nginx) are configured to run as non-root users with a read-only root filesystem and no privilege escalation. This significantly reduces the attack surface.
- **Network Policies:** Kubernetes network policies are in place to restrict traffic between components to only what is necessary.
- **Sealed Secrets:** All secrets are encrypted using Sealed Secrets, allowing them to be safely stored in a Git repository.

## 8. CORS Configuration (Critical for Web Clients)

For a web browser to be able to access your `/graphql` or other API endpoints from a different domain (e.g., a React frontend), you must configure Cross-Origin Resource Sharing (CORS) in your Django application.

1.  **Install `django-cors-headers`:**
    ```bash
    pip install django-cors-headers
    ```
    - Add `django-cors-headers` to your `requirements.txt` file.

2.  **Update `settings.py`:**
    - Add `corsheaders` to your `INSTALLED_APPS`:
      ```python
      INSTALLED_APPS = [
          ...
          'corsheaders',
          ...
      ]
      ```
    - Add `corsheaders.middleware.CorsMiddleware` to your `MIDDLEWARE` list. It should be placed as high as possible, especially before any middleware that can generate responses such as Django's `CommonMiddleware` or Whitenoise's `WhiteNoiseMiddleware`.
      ```python
      MIDDLEWARE = [
          'corsheaders.middleware.CorsMiddleware',
          'django.middleware.common.CommonMiddleware',
          ...
      ]
      ```
    - **Configure the allowed origins.** You can either allow all origins (less secure, good for development) or specify a list of allowed domains.
      ```python
      # For development (allow all)
      CORS_ALLOW_ALL_ORIGINS = True

      # For production (recommended)
      CORS_ALLOWED_ORIGINS = [
          "https://your-frontend-domain.com",
          "https://www.your-frontend-domain.com",
      ]
      ```

Without this configuration, you will likely see errors in your browser's developer console about requests being blocked by CORS policy.

## 9. Accessing Your Application

- Once Argo CD has synced your applications, your Django application will be available at the domain you configured in the Ingress.
- You can access the Grafana dashboard by port-forwarding the Grafana service:
  ```bash
  kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 8080:80
  ```
  Then, open `http://localhost:8080` in your browser. You can now view logs from your applications in the "Explore" section by selecting the "Loki" data source.
