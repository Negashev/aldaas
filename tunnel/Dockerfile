FROM golang:alpine AS builder
# Build the binary.
RUN go install github.com/trazfr/tcp-over-websocket@latest

FROM scratch
# Copy our static executable.
COPY --from=builder /go/bin/tcp-over-websocket /go/bin/tcp-over-websocket
# Run the binary.
ENTRYPOINT ["/go/bin/tcp-over-websocket"]