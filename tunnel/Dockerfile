FROM golang:alpine AS builder
# Build the binary.
RUN go install github.com/trazfr/tcp-over-websocket@latest

FROM alpine as argo
ADD https://github.com/argoproj/argo-workflows/releases/download/v4.0.6/argo-linux-amd64.gz /argo-linux-amd64.gz
RUN gunzip /argo-linux-amd64.gz
RUN chmod +x argo-linux-amd64

ADD aldaas.sh /aldaas
RUN chmod +x /aldaas

FROM alpine as kubectl
ADD https://dl.k8s.io/release/v1.33.0/bin/linux/amd64/kubectl /bin/kubectl
RUN chmod +x /bin/kubectl

FROM alpine as aldaas
RUN apk add --update curl
# Copy our static executable.
COPY --from=builder /go/bin/tcp-over-websocket /bin/tcp-over-websocket
COPY --from=argo /argo-linux-amd64 /bin/argo
COPY --from=argo /aldaas /bin/aldaas
COPY --from=kubectl /bin/kubectl /bin/kubectl
# Run the binary.
ENTRYPOINT ["/bin/aldaas"]