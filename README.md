# Django on k3s with Hetzner Autoscaling

This project provides a complete Infrastructure as Code (IaC) solution for deploying a Django application on a k3s cluster in Hetzner Cloud. The infrastructure is designed to be scalable, cost-effective, and fully automated using GitOps principles.

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
    - Create a `terraform.tfvars` file and add your Hetzner Cloud API token and SSH key name:
      ```
      hcloud_token = "your-hetzner-cloud-api-token"
      ssh_key_name = "your-ssh-key-name"
      ```
    - In `terraform/main.tf`, replace `YOUR_IP_ADDRESS/32` with your actual IP address.

4.  **Configure Ansible:**
    - Make sure the dynamic inventory script is executable:
      ```bash
      chmod +x ansible/inventory.tf.py
      ```

5.  **Configure Kubernetes Manifests:**
    - In `kubernetes/root-app.yaml`, replace `YOUR_GIT_REPO_URL` with the URL of your Git repository.
    - In `kubernetes/apps/django/deployment.yaml`, `kubernetes/apps/celery-worker/deployment.yaml`, and `kubernetes/apps/celery-beat/statefulset.yaml`, replace `your-docker-image/django-app:latest` with the name of your Docker image.
    - In `kubernetes/apps/django/ingress.yaml`, replace `your-domain.com` with your actual domain name.
    - In `kubernetes/apps/celery-worker/deployment.yaml` and `kubernetes/apps/celery-beat/statefulset.yaml`, replace `your_project_name` with the name of your Django project.
    - In `kubernetes/apps/django/deployment.yaml`, replace `/healthz` with your actual health check endpoint.
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
    - Navigate to the `ansible` directory and run:
      ```bash
      HCLOUD_TOKEN="your-hetzner-cloud-api-token" ansible-playbook -i inventory.tf.py playbook.yml
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
      kubectl apply -f kubernetes/root-app.yaml
      ```

## 4. Managing Secrets with Sealed Secrets

Your application secrets are managed securely using Sealed Secrets. This allows you to store encrypted secrets safely in your Git repository.

**First-time setup:**
- Install the `kubeseal` CLI on your local machine. On macOS: `brew install kubeseal`.

**How to generate and update your secrets:**

1.  Create a standard Kubernetes secret file on your local machine. **DO NOT** commit this file.
    ```yaml
    # local-secrets.yaml (DO NOT COMMIT THIS FILE)
    apiVersion: v1
    kind: Secret
    metadata:
      name: django-secrets
      namespace: default
    stringData:
      SECRET_KEY: "your-super-long-and-random-secret-key"
      ALLOWED_HOSTS: "your-domain.com,www.your-domain.com"
    ```

2.  Run the `kubeseal` command. This will connect to the Sealed Secrets controller in your cluster, fetch the public key, and encrypt your `local-secrets.yaml` file.
    ```bash
    kubeseal --format=yaml < local-secrets.yaml > kubernetes/apps/django/sealed-secret.yaml
    ```

3.  The command above will overwrite the `sealed-secret.yaml` file with your new encrypted secrets. This file is safe to commit to your Git repository.

4.  Commit and push the updated `sealed-secret.yaml` file. Argo CD will automatically apply it, and the Sealed Secrets controller will decrypt it into a standard Kubernetes secret that your application can use.

## 5. Accessing Your Application

- Once Argo CD has synced your applications, your Django application will be available at the domain you configured in the Ingress.
- You can access the Grafana dashboard by port-forwarding the Grafana service:
  ```bash
  kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 8080:80
  ```
  Then, open `http://localhost:8080` in your browser.

