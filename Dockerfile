# Multi-stage build for zmin Docker image
FROM alpine:3.18 AS build

# Install Zig and build dependencies
RUN apk add --no-cache \
    curl \
    xz \
    musl-dev \
    linux-headers

# Install Zig
ARG ZIG_VERSION=0.14.1
RUN curl -sSL "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz" | tar -xJ -C /opt && \
    ln -s /opt/zig-linux-x86_64-${ZIG_VERSION}/zig /usr/local/bin/zig

# Set working directory
WORKDIR /build

# Copy source code
COPY . .

# Build zmin
RUN zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-musl

# Runtime stage
FROM alpine:3.18

# Install runtime dependencies
RUN apk add --no-cache ca-certificates

# Create non-root user
RUN addgroup -g 1001 -S zmin && \
    adduser -u 1001 -S zmin -G zmin

# Copy binary from build stage
COPY --from=build /build/zig-out/bin/zmin /usr/local/bin/zmin
COPY --from=build /build/zig-out/bin/zmin-cli /usr/local/bin/zmin-cli
COPY --from=build /build/zig-out/bin/zmin-format /usr/local/bin/zmin-format
COPY --from=build /build/zig-out/bin/zmin-validate /usr/local/bin/zmin-validate

# Set proper permissions
RUN chmod +x /usr/local/bin/zmin* && \
    chown root:root /usr/local/bin/zmin*

# Switch to non-root user
USER zmin

# Set entrypoint
ENTRYPOINT ["zmin"]

# Default command shows help
CMD ["--help"]

# Metadata
LABEL org.opencontainers.image.title="zmin"
LABEL org.opencontainers.image.description="High-performance JSON minifier"
LABEL org.opencontainers.image.url="https://github.com/hydepwns/zmin"
LABEL org.opencontainers.image.documentation="https://github.com/hydepwns/zmin"
LABEL org.opencontainers.image.vendor="zmin"
LABEL org.opencontainers.image.licenses="MIT"