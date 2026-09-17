FROM eclipse-temurin:25-jdk AS build
RUN apt-get update && apt-get install -y --no-install-recommends maven && rm -rf /var/lib/apt/lists/*
WORKDIR /build
COPY pom.xml ./
RUN mvn dependency:go-offline -q
COPY src src/
RUN mvn -q clean package -DskipTests

FROM eclipse-temurin:25-jre
# Lambda Web Adapter — translates HTTP <-> Lambda invocation protocol when deployed to AWS
COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:1.0.1 /lambda-adapter /opt/extensions/lambda-adapter
ENV PORT=8000
ENV AWS_LWA_INVOKE_MODE=response_stream
WORKDIR /opt
COPY --from=build /build/target/streaming-app-0.0.1-SNAPSHOT.jar app.jar
EXPOSE 8000
CMD ["java", "-jar", "app.jar", "--server.port=8000"]
