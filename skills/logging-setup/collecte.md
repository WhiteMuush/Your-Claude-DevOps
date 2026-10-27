# Logs ingested by a collector

Companion to the `logging-setup` skill. Read it when logs leave the machine: long-running service, container, centralized aggregation. For an operations script run by hand, the console format from SKILL.md is enough.

## One line, one event, one JSON object

This section targets **what a collector ingests**, not the console output: the format imposed above remains the one a human reads. An operations script run by hand stops at the console format. A service whose logs go to a collector emits JSON, and keeps a human-readable rendering locally behind a variable (`LOG_FORMAT=pretty`).

The eye-readable text format becomes expensive as soon as there is a collector: every change to a message breaks the parsing upstream.

```json
{"ts":"2026-09-21T14:03:11.482Z","level":"error","msg":"payment declined","service":"checkout","env":"prod","trace_id":"3f9a2c","order_id":"A-12094","err":"card_expired"}
```

Non-negotiable constraints:

- **One line per event.** A 30-line stack trace becomes 30 events in the collector if it is not wrapped in a field.
- **ISO 8601 timestamp in UTC, with milliseconds.** Local time makes multi-region correlation impossible.
- **The message is stable, the context is in the fields.** Write `msg:"payment declined"` plus `order_id`, never `msg:"payment declined for order A-12094"`: otherwise no grouping by error type is possible.
- **A correlation identifier** propagated end to end. It is the only thing that lets you rebuild a path across services. If a tracer is in place, `trace_id` and `span_id` are **read from the active span's context**, never generated separately: a home-made identifier next to a trace does not let you move from one to the other. Without a tracer, a propagated `request_id` does the job. See `tracing-setup`.

## Aggregation

- **Logging must never block the application.** Asynchronous writes, a bounded buffer, and accepting lost lines rather than pending requests. An unavailable collector does not bring down the service.
- **The collector agent runs alongside**, it reads the runtime's files or the journal. The application does not itself send to the network collector.
- **Volume budget**: decide what gets sampled. Successful access logs are the first candidates.
- **Logs do not replace metrics.** Counting events with log queries is expensive and slow to answer. A Prometheus counter answers in milliseconds (see `prometheus-grafana-setup`).

## Containers and Kubernetes

- Log driver configured explicitly with `max-size` and `max-file`, otherwise the disk fills up.
- No file-writing sidecar if stdout is enough.
- The logs of a deleted pod disappear: aggregation is not optional in production.


Without `max-size` and `max-file` on Docker's `json-file` driver, the host disk fills up until it is full: rotation does not happen on its own.

## Collection-specific anti-patterns

| Anti-pattern | Consequence | Fix |
|---|---|---|
| Dynamic message with the values inside | Impossible to group by error type | Stable message plus structured fields |
| Unwrapped multi-line log | A stack trace becomes N events | Stack in a field, one line |
| Synchronous writes to the collector | The service goes down when the collector goes down | Bounded buffer, asynchronous, accepted loss |
| No `max-size` on the Docker driver | Host disk full | Explicit `max-size` and `max-file` |
| No correlation identifier | Path across services cannot be rebuilt | `trace_id` propagated end to end |
| Counting events via log queries | Slow and expensive | Dedicated metric |
