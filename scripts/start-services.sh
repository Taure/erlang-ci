#!/usr/bin/env bash
# Starts optional service containers based on environment variables.
# Used by CI test jobs to set up services before running tests.
set -euo pipefail

if [ "${ENABLE_POSTGRES:-false}" = "true" ]; then
  echo "Starting PostgreSQL ${POSTGRES_VERSION}..."
  docker run -d --name postgres \
    -p "${PGPORT}:5432" \
    -e POSTGRES_USER="${PGUSER}" \
    -e POSTGRES_PASSWORD="${PGPASSWORD}" \
    -e POSTGRES_DB="${PGDATABASE}" \
    "postgres:${POSTGRES_VERSION}"

  echo "Waiting for PostgreSQL..."
  for i in $(seq 1 30); do
    docker exec postgres pg_isready -U "${PGUSER}" > /dev/null 2>&1 && break
    sleep 1
  done
  echo "PostgreSQL ready."
fi

if [ "${ENABLE_KAFKA:-false}" = "true" ]; then
  echo "Starting Kafka ${KAFKA_VERSION}..."
  docker run -d --name kafka \
    -p "${KAFKA_PORT}:9092" \
    -e KAFKA_NODE_ID=1 \
    -e KAFKA_PROCESS_ROLES=broker,controller \
    -e KAFKA_LISTENERS=PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093 \
    -e KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://localhost:"${KAFKA_PORT}" \
    -e KAFKA_CONTROLLER_QUORUM_VOTERS=1@localhost:9093 \
    -e KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER \
    -e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT \
    -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
    "apache/kafka:${KAFKA_VERSION}"

  echo "Waiting for Kafka..."
  for i in $(seq 1 30); do
    docker exec kafka /opt/kafka/bin/kafka-broker-api-versions.sh \
      --bootstrap-server localhost:9092 > /dev/null 2>&1 && break
    sleep 1
  done
  echo "Kafka ready."
fi
