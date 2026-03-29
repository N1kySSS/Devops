# Stage 1: build native Quarkus application
FROM quay.io/quarkus/ubi9-quarkus-mandrel-builder-image:jdk-25 AS builder

WORKDIR /build

COPY --chmod=0755 gradlew .
COPY gradle gradle
COPY build.gradle settings.gradle ./

RUN ./gradlew --no-daemon dependencies

COPY src src

RUN ./gradlew --no-daemon \
    --build-cache \
    build \
    -x test \
    -Dquarkus.native.enabled=true \
    -Dquarkus.native.remote-container-build=false \
    -Dquarkus.package.jar.enabled=false

# Stage 2: minimal runtime image with more libs included
FROM registry.access.redhat.com/ubi9/ubi-minimal

WORKDIR /work/

COPY --from=builder /build/build/*-runner /work/application

EXPOSE 8080

ENV APP_API_LIMIT=130
ENV APP_API_TIMEOUT=4000

ENTRYPOINT ["./application", "-Dquarkus.http.host=0.0.0.0"]