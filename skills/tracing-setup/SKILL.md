---
name: tracing-setup
description: Use when setting up distributed tracing with OpenTelemetry, W3C traceparent context propagation, span naming and granularity, attributes, error handling, head and tail sampling, correlation with logs and metrics. Triggers on "trace", "tracing", "distributed traces", "OpenTelemetry", "OTel", "span", "traceparent", "trace_id", "sampling", "trace sampling", "Jaeger", "Tempo", "latency between services", "observability".
---

# Distributed tracing

## What this skill does not teach

Deploying an OpenTelemetry collector, configuring a Jaeger or Tempo backend, reading a waterfall in a UI: these are well-documented tooling tasks. Here we decide **what to trace, how to name it and what to keep**.

The basic rule: **tracing answers "where did the time go", not "how many" or "what exactly".** Those two questions belong to `metrics-setup` and `logging-setup`.

## Propagation first, everything else after

**A broken trace is worthless.** An orphan span is worse than no trace at all: it gives the illusion of coverage. It is the only point to validate before investing in naming or attributes.

The context travels in the **W3C `traceparent`** header (standard format, to be preferred over proprietary formats). It must cross:

| Boundary | Point of attention |
|---|---|
| Outgoing HTTP call | The instrumented client injects the header. A hand-built client does not |
| Queued message | The context goes in the **message headers**, not in its business body |
| Asynchronous or batch job | The producer's context must be serialized with the task, otherwise the trace stops at the enqueue |
| Gateway, proxy, load balancer | Check that the header is forwarded and not filtered |
| Team or vendor boundary | Agree on the format upfront, not afterwards |

Validation test: take a real `trace_id` and check that it appears **in every service it crosses**. As long as this test fails, do not refine the rest.

## Span naming and granularity

A span name is **low cardinality**, like a metric name. Whatever varies goes into the attributes.

```
GET /orders/{id}          correct
GET /orders/48213         wrong, one span name per order
db.query orders           correct
SELECT * FROM orders ...  wrong, and a potential data leak
```

What to split into spans:

- **A process boundary**: incoming request, outgoing call, message publication or consumption. Non-negotiable.
- **An input/output operation**: database query, cache call, reading a large file.
- **A significant block of computation**, only if it is suspected of costing time.

What not to split: every function. A 400-span trace is unreadable, expensive, and says nothing more than a trace with 20 well-placed spans. Granularity gets finer where an investigation actually lacked information.

Follow the **OpenTelemetry semantic conventions** for standard attributes (`http.request.method`, `server.address`, `db.system`). A home-made attribute where a convention exists costs compatibility with all the tooling.

## Attributes, events, errors

- **Attributes describe the span**, events timestamp a fact inside it. An exception is an event, not an attribute.
- **A failed span carries an explicit error status.** Without it, it is counted as successful in every derived statistic.
- **The error is marked where it is handled**, not at every level that relays it. Otherwise a single failure shows up as ten.
- The same prohibitions as for logs apply to attributes: **no secret, no token, no personal data, no entire request body**. Traces are exported to a third-party backend, often less protected than logs.
- An SQL query as an attribute exposes the values. Log the operation and the table, not the full query.

## Sampling

Tracing everything costs too much, tracing nothing is useless. The decision is made explicitly.

| Strategy | Principle | When |
|---|---|---|
| **Head-based** | The decision is made at the start, at the root, and propagated | Simple default, predictable volume |
| **Tail-based** | The collector keeps the complete trace once finished, based on what happened in it | When you want 100% of errors and slow traces |
| **Parent-based** | A service follows the decision received from its parent | To be enabled everywhere, whatever the strategy |

Two rules:

- **The decision must be consistent across the whole trace.** If each service decides for itself, you get traces with holes, unusable. Hence `parent-based` everywhere.
- **Keep everything abnormal**: errors and high latencies sampled at 100%, nominal traffic sampled low. This is the main argument for tail-based, which costs memory on the collector.

A rate of 1 to 10% on nominal traffic is almost always enough for diagnostics.

## Correlation between the three signals

This is what turns three separate tools into an investigation chain.

1. **Inject `trace_id` and `span_id` into every log line** emitted within a span's context. The path becomes: alert on a metric, then slow trace, then the exact logs of that trace.
2. **Exemplars**: attaching a `trace_id` to a metric point lets you jump from a latency spike to a real trace of that spike.
3. The same correlation identifier therefore crosses all three signals. Without it, each tool has to be searched by hand.

See `logging-setup` for the `trace_id` field on the logs side, and `metrics-setup` for the division of roles.

## Anti-patterns

| Anti-pattern | Consequence | Fix |
|---|---|---|
| Propagation broken at a boundary | Orphan traces, illusion of coverage | Validate a `trace_id` end to end |
| Context in the message body | Business coupling, forgotten by other producers | Message headers |
| Identifier in the span name | Unmanageable cardinality on the backend | Templated name, identifier as an attribute |
| One span per function | Unreadable traces, high cost | Process boundaries and inputs/outputs |
| Error marked at every level | One failure counts as ten | Mark it where it is handled |
| Error status not set | The failed span looks like a success | Explicit status plus exception event |
| SQL query or entire body as an attribute | Data leak to a third-party backend | Operation and table only |
| Sampling decided per service | Traces with holes | `parent-based` everywhere |
| Uniform sampling | Rare incidents are never captured | 100% of errors and slow traces |
| No `trace_id` in the logs | No link between the signals | Inject the context into the logger |

## Review checklist

1. A real `trace_id` is found in every service crossed, including behind a queue and an asynchronous job.
2. Span names are low cardinality, whatever varies is an attribute.
3. Standard attributes follow the OpenTelemetry semantic conventions.
4. No secret or personal data goes into an attribute or an event.
5. Failed spans carry an error status, marked only once.
6. `parent-based` is active everywhere and the sampling strategy is written down somewhere.
7. Errors and slow traces are kept in full.
8. `trace_id` and `span_id` appear in the application logs.
