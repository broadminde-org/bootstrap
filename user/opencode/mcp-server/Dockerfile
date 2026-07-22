FROM python:3.13-slim

WORKDIR /app

COPY pyproject.toml ./
COPY src/ /app/src/

RUN pip install --no-cache-dir .

ENV MCP_HOST=0.0.0.0
ENV MCP_PORT=8766
ENV PYTHONUNBUFFERED=1

RUN groupadd --system mcp && useradd --system --no-create-home --gid mcp mcp
USER mcp

EXPOSE 8766

HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8766/mcp', timeout=3)"

ENTRYPOINT ["python3", "-m", "host_standards"]
