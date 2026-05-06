FROM python:3.12-slim-bookworm

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    unzip \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements (if exists)
COPY requirements.txt* ./

# Install Python dependencies
RUN if [ -f requirements.txt ]; then pip install -r requirements.txt; fi

# Copy application code
COPY src/services/edge/ids-pi/ /app/

# Create necessary directories
RUN mkdir -p /var/log/idps/pi /opt/idps/pi/scans

# Set environment variables
ENV PYTHONPATH=/app
ENV SERVICE_MODE=edge

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run the application
CMD ["python", "app.py"]
