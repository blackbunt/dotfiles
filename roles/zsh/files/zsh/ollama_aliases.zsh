#!/usr/bin/env zsh

ollama() {
    if ! docker ps --format '{{.Names}}' | grep -q '^ollama$'; then
        echo "Starte Ollama..."
        docker compose -f ~/Repo/local-ai/docker-compose.yml up -d
        echo "Warte auf Ollama..."
        until docker exec ollama ollama list &>/dev/null 2>&1; do
            sleep 1
        done
        echo "Ollama bereit!"
    fi
    docker exec -it ollama ollama "$@"
}
