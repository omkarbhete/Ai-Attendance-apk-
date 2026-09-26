# Multi-stage build for SnapClass AI Attendance Application
FROM python:3.9-slim as builder

# Set working directory
WORKDIR /app

# Install system dependencies for dlib and face recognition
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    libopenblas-dev \
    liblapack-dev \
    libx11-dev \
    libgtk-3-dev \
    libboost-python-dev \
    libboost-system-dev \
    libsndfile1 \
    ffmpeg \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Production stage
FROM python:3.9-slim

# Install runtime dependencies only
RUN apt-get update && apt-get install -y \
    libopenblas0 \
    liblapack3 \
    libx11-6 \
    libgtk-3-0 \
    libsndfile1 \
    ffmpeg \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -u 1000 snapclass && \
    mkdir -p /app /var/log/snapclass && \
    chown -R snapclass:snapclass /app /var/log/snapclass

# Set working directory
WORKDIR /app

# Copy Python packages from builder
COPY --from=builder /usr/local/lib/python3.9/site-packages /usr/local/lib/python3.9/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy application code
COPY --chown=snapclass:snapclass . .

# Switch to non-root user
USER snapclass

# Expose ports
EXPOSE 8501 8502

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8502/healthz || exit 1

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    STREAMLIT_SERVER_PORT=8501 \
    STREAMLIT_SERVER_ADDRESS=0.0.0.0 \
    STREAMLIT_SERVER_HEADLESS=true

# Start both health check and main application
CMD python healthcheck.py & streamlit run app.py

# Made with Bob
