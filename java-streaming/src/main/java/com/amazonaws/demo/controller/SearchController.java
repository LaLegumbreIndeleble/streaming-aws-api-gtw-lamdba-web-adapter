package com.amazonaws.demo.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

@RestController
public class SearchController {

    private static final ScheduledExecutorService SCHEDULER =
            Executors.newScheduledThreadPool(20);
    private static final ObjectMapper MAPPER = new ObjectMapper();

    record FlightData(String dep, String arr, String dur, int stops, String price) {}
    record Provider(String name, String code, int delayMs, List<FlightData> flights) {}
    record GlobalFlight(String flightId, int globalIdx) {}

    private static final List<Provider> PROVIDERS = List.of(
        new Provider("JetBlue", "B6", 5_000, List.of(
            new FlightData("08:15 AM", "11:28 AM", "5h 13m", 0, "C$489"),
            new FlightData("01:00 PM", "04:19 PM", "5h 19m", 0, "C$521"),
            new FlightData("07:30 PM", "10:52 PM", "5h 22m", 0, "C$458")
        )),
        new Provider("Delta", "DL", 10_000, List.of(
            new FlightData("06:00 AM", "09:32 AM", "5h 32m", 0, "C$534"),
            new FlightData("11:15 AM", "03:47 PM", "6h 32m", 1, "C$412"),
            new FlightData("05:00 PM", "09:35 PM", "6h 35m", 1, "C$387")
        )),
        new Provider("United", "UA", 15_000, List.of(
            new FlightData("07:40 AM", "01:12 PM", "7h 32m", 1, "C$445"),
            new FlightData("03:20 PM", "10:05 PM", "8h 45m", 2, "C$361")
        )),
        new Provider("American", "AA", 22_000, List.of(
            new FlightData("09:00 AM", "12:22 PM", "5h 22m", 0, "C$621"),
            new FlightData("04:15 PM", "07:40 PM", "5h 25m", 0, "C$574")
        )),
        new Provider("Air China", "CA", 30_000, List.of(
            new FlightData("10:30 PM", "03:58 AM", "5h 28m", 0, "C$398"),
            new FlightData("08:00 AM", "02:45 PM", "8h 45m", 1, "C$341")
        ))
    );

    private static final List<GlobalFlight> ALL_FLIGHTS;
    static {
        var flights = new ArrayList<GlobalFlight>();
        PROVIDERS.forEach(p -> {
            for (int i = 0; i < p.flights().size(); i++) {
                flights.add(new GlobalFlight(p.name() + "-" + i, flights.size()));
            }
        });
        ALL_FLIGHTS = List.copyOf(flights);
    }

    /** Deterministic score 50–100, matching the Node.js seededScore function exactly. */
    private static int seededScore(int seed, int index) {
        long h = (Integer.toUnsignedLong(seed) * 2654435761L
                + Integer.toUnsignedLong(index) * 2246822519L) & 0xFFFFFFFFL;
        h = (h ^ (h >>> 16)) & 0xFFFFFFFFL;
        h = (h * 0x45d9f3bL) & 0xFFFFFFFFL;
        h = (h ^ (h >>> 16)) & 0xFFFFFFFFL;
        return (int) (50 + (h % 51));
    }

    private static int globalIdx(String flightId) {
        return ALL_FLIGHTS.stream()
                .filter(af -> af.flightId().equals(flightId))
                .findFirst().orElseThrow().globalIdx();
    }

    private void emit(SseEmitter emitter, Object data, AtomicBoolean closed) {
        if (closed.get()) return;
        try {
            emitter.send(SseEmitter.event().data(MAPPER.writeValueAsString(data)));
        } catch (Exception e) {
            closed.set(true);
            emitter.completeWithError(e);
        }
    }

    @GetMapping(value = "/search/stream", produces = "text/event-stream")
    public SseEmitter searchStream(
            @RequestParam(defaultValue = "false") boolean ai,
            @RequestParam(defaultValue = "0") int seed) {

        SseEmitter emitter = new SseEmitter(65_000L);
        AtomicBoolean closed = new AtomicBoolean(false);

        int total = ALL_FLIGHTS.size();
        // One emit per flight: ai=true holds until scored, ai=false emits immediately
        AtomicInteger pending = new AtomicInteger(total);

        emitter.onCompletion(() -> closed.set(true));
        emitter.onTimeout(() -> { closed.set(true); emitter.complete(); });
        emitter.onError(e -> closed.set(true));

        Runnable finish = () -> {
            if (!closed.getAndSet(true)) {
                try {
                    emitter.send(SseEmitter.event().data("[DONE]"));
                    emitter.complete();
                } catch (Exception ignored) {}
            }
        };

        emit(emitter, Map.of("type", "meta", "totalFlights", total), closed);

        for (Provider p : PROVIDERS) {
            SCHEDULER.schedule(() -> {
                for (int fi = 0; fi < p.flights().size(); fi++) {
                    if (closed.get()) return;

                    FlightData f = p.flights().get(fi);
                    String flightId = p.name() + "-" + fi;
                    int gIdx = globalIdx(flightId);

                    var ev = new LinkedHashMap<String, Object>();
                    ev.put("type", "flight");
                    ev.put("flightId", flightId);
                    ev.put("airline", p.name());
                    ev.put("code", p.code());
                    ev.put("from", "JFK");
                    ev.put("to", "LAX");
                    ev.put("departure", f.dep());
                    ev.put("arrival", f.arr());
                    ev.put("duration", f.dur());
                    ev.put("stops", f.stops());
                    ev.put("price", f.price());
                    ev.put("providerResponseTime", p.delayMs());

                    if (ai) {
                        // Hold the flight record until the AI score is ready, then emit once
                        long scoreDelay = 1500 + (long) (Math.random() * 1500);
                        SCHEDULER.schedule(() -> {
                            ev.put("score", seededScore(seed, gIdx));
                            emit(emitter, ev, closed);
                            if (pending.decrementAndGet() == 0) finish.run();
                        }, scoreDelay, TimeUnit.MILLISECONDS);
                    } else {
                        emit(emitter, ev, closed);
                        if (pending.decrementAndGet() == 0) finish.run();
                    }
                }
            }, p.delayMs(), TimeUnit.MILLISECONDS);
        }

        return emitter;
    }
}
