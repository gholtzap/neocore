FROM rust:bookworm AS builder

WORKDIR /app

COPY Cargo.toml ./

RUN mkdir src && echo "fn main() {}" > src/main.rs && cargo build --release && rm -rf src

COPY . .

RUN touch src/main.rs && cargo build --release

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    iproute2 \
    iptables \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/target/release/upf /app/upf

EXPOSE 8080 2152/udp 8806/udp

CMD ["./upf"]
