FROM eclipse-temurin:8-jre

ARG OTEL_JAVAAGENT_VERSION=2.6.0
ADD https://repo1.maven.org/maven2/io/opentelemetry/javaagent/opentelemetry-javaagent/${OTEL_JAVAAGENT_VERSION}/opentelemetry-javaagent-${OTEL_JAVAAGENT_VERSION}.jar /otel/opentelemetry-javaagent.jar

WORKDIR /app
COPY target/otel-springboot-demo-0.0.1-SNAPSHOT.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
