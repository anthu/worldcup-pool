# Stage 1: Build React frontend
FROM node:20-alpine AS frontend

WORKDIR /build
COPY ui/package.json ui/package-lock.json* ./
RUN npm ci --ignore-scripts
COPY ui/ ./
RUN npm run build

# Stage 2: Python backend
FROM python:3.11-slim AS backend

# System deps for snowflake-connector-python
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python deps
COPY app/container/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy backend app code
COPY app/container/worldcup_app/ /app/worldcup_app/

# Copy built frontend from stage 1
COPY --from=frontend /build/dist /app/web_dist

EXPOSE 8000

CMD ["uvicorn", "worldcup_app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
