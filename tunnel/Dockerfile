FROM golang:alpine AS builder
# Build the binary.
RUN go install github.com/trazfr/tcp-over-websocket@latest

FROM alpine as argo
ADD https://github.com/argoproj/argo-workflows/releases/download/v3.5.2/argo-linux-amd64.gz /argo-linux-amd64.gz
RUN gunzip /argo-linux-amd64.gz
RUN chmod +x argo-linux-amd64

ADD aldaas.sh /aldaas
RUN chmod +x /aldaas

FROM alpine as aldaas
# Copy our static executable.
COPY --from=builder /go/bin/tcp-over-websocket /bin/tcp-over-websocket
COPY --from=argo /argo-linux-amd64 /bin/argo
COPY --from=argo /aldaas /bin/aldaas
# Run the binary.
ENTRYPOINT ["/bin/aldaas"]