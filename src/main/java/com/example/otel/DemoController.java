package com.example.otel;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.api.metrics.DoubleHistogram;
import io.opentelemetry.api.metrics.LongCounter;
import io.opentelemetry.api.metrics.Meter;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Random;
import java.util.concurrent.TimeUnit;

@RestController
public class DemoController {

    private static final AttributeKey<String> STATUS = AttributeKey.stringKey("status");
    private static final AttributeKey<String> ROUTE = AttributeKey.stringKey("route");

    private final Random random = new Random();
    private final LongCounter orderCounter;
    private final LongCounter errorCounter;
    private final DoubleHistogram orderLatency;

    public DemoController() {
        Meter meter = GlobalOpenTelemetry.getMeter("agentspace.otel.demo");
        this.orderCounter = meter.counterBuilder("demo_orders")
                .setDescription("Number of demo orders handled by the application")
                .setUnit("1")
                .build();
        this.errorCounter = meter.counterBuilder("demo_errors")
                .setDescription("Number of intentionally generated demo errors")
                .setUnit("1")
                .build();
        this.orderLatency = meter.histogramBuilder("demo_order_latency")
                .setDescription("Simulated order processing latency")
                .setUnit("ms")
                .build();
    }

    @GetMapping("/")
    public Map<String, Object> index() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("service", "otel-springboot-demo");
        body.put("time", Instant.now().toString());
        body.put("try", new String[]{"/api/hello", "/api/orders/1001", "/api/load?count=20", "/api/error"});
        body.put("metrics", "/actuator/prometheus");
        return body;
    }

    @GetMapping("/api/hello")
    public Map<String, Object> hello() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("message", "hello opentelemetry");
        body.put("time", Instant.now().toString());
        return body;
    }

    @GetMapping("/api/orders/{id}")
    public ResponseEntity<Map<String, Object>> order(@PathVariable String id) throws InterruptedException {
        long started = System.nanoTime();
        int sleepMs = 30 + random.nextInt(170);
        TimeUnit.MILLISECONDS.sleep(sleepMs);

        String status = random.nextInt(10) == 0 ? "slow" : "ok";
        Attributes attributes = Attributes.of(STATUS, status, ROUTE, "/api/orders/{id}");
        orderCounter.add(1, attributes);
        orderLatency.record(elapsedMs(started), attributes);

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("id", id);
        body.put("status", status);
        body.put("processingMs", sleepMs);
        body.put("time", Instant.now().toString());
        return ResponseEntity.ok(body);
    }

    @GetMapping("/api/load")
    public Map<String, Object> load(@RequestParam(defaultValue = "10") int count) throws InterruptedException {
        int safeCount = Math.max(1, Math.min(count, 200));
        for (int i = 0; i < safeCount; i++) {
            long started = System.nanoTime();
            TimeUnit.MILLISECONDS.sleep(5 + random.nextInt(20));
            Attributes attributes = Attributes.of(STATUS, "ok", ROUTE, "/api/load");
            orderCounter.add(1, attributes);
            orderLatency.record(elapsedMs(started), attributes);
        }

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("generated", safeCount);
        body.put("time", Instant.now().toString());
        return body;
    }

    @GetMapping("/api/error")
    public Map<String, Object> error() {
        errorCounter.add(1, Attributes.of(ROUTE, "/api/error", STATUS, "error"));
        throw new IllegalStateException("intentional demo error");
    }

    private double elapsedMs(long startedNanos) {
        return (System.nanoTime() - startedNanos) / 1_000_000.0;
    }
}
