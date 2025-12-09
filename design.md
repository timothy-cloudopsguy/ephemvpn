You are an expert DevOps engineer and Python backend developer.

I want you to design and implement a Docker-based OpenVPN server with a small Python API for managing VPN clients.

**Requirements:**

1. **Dockerfile / Image**
   - Use a lightweight Linux base image.
   - Install and configure OpenVPN.
   - Install Python 3 and any required dependencies for the API using FastAPI and Poetry for pip management.
   - Expose the necessary ports for:
     - OpenVPN (default is UDP 1194, but this can be configurable)
     - The Python API (default is HTTPS on port 443, but this can be configurable).

2. **Python API**
   - Implement a minimal REST API with endpoints to:
     - `POST /clients` – generate a new OpenVPN client configuration (and underlying cert/key if needed).
     - `GET /clients` – list existing client configurations.
     - `DELETE /clients/{client_id}` – revoke/delete a client configuration.
   - Store client configs in a directory inside the container (e.g., `/etc/openvpn/clients`) as well as in SSM paramters.
   - Use a simple, clear structure so the API service could later be split out if needed.

3. **AWS SSM Parameter Store Integration**
   - On container startup, the entrypoint script should:
     - Fetch the Python FastAPI API Key from AWS SSM Parameter Store, or create one if it doesn't exist and push it to SSM Paramter Store.
     - Fetch the OpenVPN **server certificates/keys** from AWS SSM Parameter Store, or create it if it doesn't exist and push it to SSM Paramater Store.
     - Fetch the OpenVPN **server config** (e.g., `server.conf`) from SSM, or create it if it doesn't exist and push it to SSM Paramater Store.
     - Fetch any **existing client configs** from SSM (if you think that’s appropriate) and materialize them into the correct directory.
   - Assume the container has an IAM role or AWS credentials injected so it can call SSM.
   - Use the AWS SDK for Python (`boto3`) or the AWS CLI (if you think that’s cleaner) to retrieve the parameters.
   - Write all fetched configs/certs into the correct paths expected by OpenVPN (e.g., `/etc/openvpn/server.conf`, `/etc/openvpn/certs`, etc.).

4. **Entrypoint Behavior**
   - Implement an entrypoint script that:
     1. Fetches and writes all required configs/certs from AWS SSM.
     2. Starts the Python API **in the background** (e.g., `uvicorn api:app --host 0.0.0.0 --port 8000 &`).
     3. Starts OpenVPN **in the foreground** as PID 1 so the container lifecycle is tied to the OpenVPN process.
   - The container should exit if OpenVPN exits.

5. **Deliverables**
   - A complete `Dockerfile`.
   - The entrypoint script (e.g., `entrypoint.sh`).
   - The Python API code (one or more files).
   - Example SSM parameter names and how they map to files in the container.
   - Instructions/notes on:
     - How to build and run the image.
     - What environment variables are expected (e.g., SSM parameter names, AWS region).
     - How to call the API endpoints to manage clients.

Please generate all code files in full (Dockerfile, entrypoint script, and Python app), plus any configuration examples needed.
