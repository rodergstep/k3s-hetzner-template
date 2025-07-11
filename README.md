# Django on k3s with Hetzner Autoscaling

This project provides a complete Infrastructure as Code (IaC) solution for deploying a Django application on a k3s cluster in Hetzner Cloud. The infrastructure is designed to be scalable, cost-effective, and fully automated using GitOps principles.

## Core Components

This project uses a declarative, GitOps-first approach to manage all cluster components. The core services listed below are defined as Argo CD Applications and managed by ApplicationSets. This means the entire lifecycle of these components is automated based on the manifests in this Git repository.

| Component                 | Version        | Description                                                                     |
| ------------------------- | -------------- | ------------------------------------------------------------------------------- |
| Terraform hcloud Provider | `1.51.0`       | Manages the underlying cloud infrastructure on Hetzner Cloud.                   |
| k3s                       | `v1.32.6+k3s1` | A lightweight, production-ready Kubernetes distribution.                        |
| ArgoCD                    | `stable`       | A declarative, GitOps continuous delivery tool for Kubernetes.                  |
| cert-manager              | `v1.18.2`      | Automates the management and issuance of TLS certificates.                      |
| cloudnative-pg            | `0.24.0`       | A Kubernetes operator for PostgreSQL, providing a highly available database.    |
| hcloud-ccm                | `v1.26.0`      | The Hetzner Cloud Controller Manager, integrating the cluster with the cloud.   |
| hcloud-csi                | `v2.16.0`      | The Hetzner CSI driver, providing persistent storage for the cluster.           |
| ingress-nginx             | `4.13.0`       | An Ingress controller for Kubernetes using NGINX as a reverse proxy.            |
| kube-prometheus-stack     | `75.9.0`       | A collection of Kubernetes manifests, Grafana dashboards, and Prometheus rules. |
| sealed-secrets            | `2.17.3`       | A Kubernetes controller and tool for one-way encrypted Secrets.                 |
| Cluster Autoscaler        | `9.47.0`       | Automatically adjusts the size of the Kubernetes cluster.                       |
| Loki                      | `6.31.0`       | A horizontally-scalable, highly-available, multi-tenant log aggregation system. |
| Promtail                  | `6.17.0`       | An agent which ships the contents of local logs to a private Loki instance.     |

## Prerequisites

- A Hetzner Cloud account and API token.
- A domain name.
- `terraform` CLI installed.
- `ansible` CLI installed.
- `kubectl` CLI installed and configured to access your cluster.
- `kubeseal` CLI installed (see instructions below).
- A Git repository to store your Kubernetes manifests.
- Docker with `buildx` enabled (this is default on modern Docker Desktop).

## 1. Initial Setup

1.  **Clone this repository.**

2.  **Configure Hetzner Cloud:**

    - Create a new project in the Hetzner Cloud console.
    - Generate an API token and save it securely.

3.  **Configure Ansible:**

    - Make sure the dynamic inventory script is executable:
      ```bash
      chmod +x ansible/inventory.tf.py
      ```

## 2. Infrastructure Setup (Terraform Workspaces)

This project uses Terraform Workspaces to manage separate, parallel infrastructure for your `staging` and `production` environments. This ensures that your testing environment is completely isolated from your production environment.

### First-Time Setup

1.  **Navigate to the `terraform` directory:**

    ```bash
    cd terraform
    ```

2.  **Initialize Terraform:**

    ```bash
    terraform init
    ```

3.  **Create the Workspaces:**
    ```bash
    terraform workspace new staging
    terraform workspace new production
    ```

### Deploying an Environment

When you want to deploy or make changes to an environment, you must select the correct workspace first.

1.  **Select the Workspace:**

    - For staging:
      ```bash
      terraform workspace select staging
      ```
    - For production:
      ```bash
      terraform workspace select production
      ```

2.  **Create a `.tfvars` file for the environment:**

    - For staging, copy the `staging.tfvars` example:
      ```bash
      cp staging.tfvars.example staging.tfvars
      ```
    - For production, copy the `production.tfvars` example:
      ```bash
      cp production.tfvars.example production.tfvars
      ```
    - **Edit the `.tfvars` file** and fill in your details (Hetzner token, SSH key, etc.).

3.  **Apply the Configuration:**
    - **IMPORTANT:** You must tell Terraform which variables file to use for the selected workspace.
    - For staging:
      ```bash
      terraform apply -var-file="staging.tfvars"
      ```
    - For production:
      ```bash
      terraform apply -var-file="production.tfvars"
      ```

This workflow ensures that you are always applying the correct configuration to the correct environment.

## 3. Deployment Workflow (GitOps with Argo CD)

This project uses a modern GitOps workflow centered around a single **App of Apps**, which manages the entire cluster state declaratively.

The core of this workflow is the `root-app.yaml` file, which deploys three main categories of applications:

1.  **Infrastructure Components:** Managed by an `ApplicationSet` in `kubernetes/infrastructure/`. This includes core services like `cert-manager`, `ingress-nginx`, and the `hcloud-csi-driver`.
2.  **Monitoring Stack:** Managed by an `ApplicationSet` in `kubernetes/monitoring/`. This includes `kube-prometheus-stack`, `loki`, and `promtail`.
3.  **Your Applications:** The Django application and its dependencies, defined in `kubernetes/apps/`.

This structure provides a clear separation of concerns and makes the cluster easy to manage. To add, remove, or update any component, you simply modify its definition in the corresponding directory, and Argo CD will automatically synchronize the changes.

The CI/CD pipeline for your Django application remains the same, with automated deployments to `staging` and manual promotion to `production` by updating the image tag in the Kustomize overlay.

### Automated Staging Deployment

1.  **Push Code:** When you push a code change to the `main` branch, the GitHub Actions CI pipeline is triggered.
2.  **Build and Push:** The CI pipeline builds new Docker images and tags them with the Git commit SHA.
3.  **Update Staging Manifest:** The CI pipeline then automatically commits an update to the `kubernetes/overlays/staging/kustomization.yaml` file, changing the `newTag` to the new Git commit SHA.
4.  **Argo CD Deploys:** Argo CD detects the change in the Git repository and automatically deploys the new image to the `staging` environment.

### Manual Production Deployment (Promotion)

Deploying to production is a manual, deliberate step. This ensures that only tested and approved changes are released to your users.

1.  **Verify in Staging:** After the automated deployment to `staging`, thoroughly test your application to ensure it is working as expected.
2.  **Promote to Production:** Once you are confident that the new version is stable, you can promote it to production by manually updating the `kubernetes/overlays/production/kustomization.yaml` file.
    - Change the `newTag` for the images to the Git commit SHA of the version you have tested in staging.
    - Commit and push this change to the `main` branch.
3.  **Argo CD Deploys:** Argo CD will detect the change and deploy the new version to the `production` environment.

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

    - Contains the Django `SECRET_KEY` and any other sensitive application settings. The `ALLOWED_HOSTS` should be configured via the Kustomize overlay, not here.
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
        # Note: ALLOWED_HOSTS is managed in your production overlay, not here.
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
    - **Target file:** `kubernetes/infrastructure/controllers/hcloud-cluster-autoscaler/sealed-secret.yaml`
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

## 6. Configuring Your Application (Kustomize Overlays)

This project uses Kustomize to manage Kubernetes manifests, separating the base configuration from environment-specific settings. This is a best practice that prevents sensitive information from being committed to Git.

### How it Works

- **Base Configuration (`kubernetes/apps/`):** This directory contains the generic, non-sensitive Kubernetes manifests for your applications (Django, Celery, etc.). This `base` is safe to commit to your Git repository.
- **Overlays (`kubernetes/overlays/`):** This directory is where you will store your environment-specific configurations. Each overlay contains a `kustomization.yaml` that specifies how to patch the `base` configuration.
- **Name Suffixes:** Each overlay uses a `nameSuffix` (e.g., `-staging`, `-production`) to automatically rename all resources. This is the key to creating truly separate deployments for each environment.
- **`.gitignore`:** The `kubernetes/overlays` directory is listed in the `.gitignore` file. **This is the most important part.** It ensures that your sensitive production configuration is never accidentally committed to your Git repository.

### Configuration Steps

1.  **Configure the Base:**

    - **Root Application:** In `kubernetes/root-app.yaml`, replace the placeholder Git repository URL (`your-repo-url`) with your own.
    - **ConfigMaps:** Review and update any `ConfigMap` files (e.g., `kubernetes/apps/django/configmap.yaml`) with your application's non-sensitive settings.

2.  **Configure the Overlays:**
    - **Production:** Navigate to `kubernetes/overlays/production/kustomization.yaml` and replace the placeholder values for your domain, TLS secret, and Docker image tags.
    - **Staging:** Navigate to `kubernetes/overlays/staging/kustomization.yaml` and replace the placeholder values for your domain, TLS secret, and Docker image tags. This overlay is also configured to use a separate database and Redis instance.

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

    - Add `corsheaders` to your `INSTALLED_APPS`:`
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
