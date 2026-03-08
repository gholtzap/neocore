FROM rust:bookworm as builder

WORKDIR /app

COPY Cargo.toml ./
COPY src ./src

RUN cargo build --release

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/target/release/smsf /app/smsf

ENV RUST_LOG=info
ENV SBI_BIND_ADDR=0.0.0.0
ENV SBI_BIND_PORT=8085
ENV MONGODB_URI=mongodb://mongodb:27017
ENV NRF_URI=http://nrf:8081

EXPOSE 8085

CMD ["/app/smsf"]
