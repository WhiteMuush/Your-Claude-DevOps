---
name: metrics-setup
description: Use when designing application and infrastructure metrics, with a mandatory naming convention, choice of type (counter, gauge, histogram), control of label cardinality, RED and USE methods, buckets and quantiles. Complements prometheus-grafana-setup, which covers the tooling. Triggers on "metrics", "measurements", "instrument", "cardinality", "labels", "counter", "gauge", "histogram", "quantile", "p95", "RED", "USE", "SLI", "SLO", "observability".
---

# Designing metrics

## What this skill does not teach

Installing Prometheus, writing a `scrape_config`, plugging in Grafana, writing an Alertmanager rule: that is the `prometheus-grafana-setup` skill. Here we decide **what to measure and under which name**, before touching the tooling.

The corollary also holds: a badly named or overly cardinal metric cannot be fixed, it gets replaced, and the history is lost.

## Naming: mandatory convention

**The same convention on every project**, like the console format of `logging-setup`. A metric name can be read without documentation.

```
<namespace>_<subject>_<unit>[_total]
```

```
http_requests_total                     request counter
http_request_duration_seconds           latency histogram
queue_messages_pending                  queue depth gauge
process_resident_memory_bytes           memory gauge
```

Formatting rules:

| Rule | Detail |
|---|---|
| **Base units only** | `seconds`, `bytes`, `ratio`. Never `ms`, `mb`, `percent` |
| **The unit is in the name** | A name without a unit forces you to open the code to know what you are reading |
| **`_total` suffix** on every counter | Makes the type readable at a glance and in queries |
| **No type suffix** elsewhere | No `_gauge`, no `_histogram` |
| **Namespace = the service or component** | `checkout_`, `ingest_`, not the team or the environment |
| **Snake case, in English, plural for things that are counted** | `requests`, `errors`, `messages` |

What identifies an instance (environment, region, host, version) is a **label**, never part of the name. One name per environment makes any aggregation impossible.

## Choosing the type

| Type | When | Pitfall |
|---|---|---|
| **Counter** | A quantity that only grows: requests, errors, bytes sent | Always read as a rate, never as a raw value. The absolute value means nothing after a restart |
| **Gauge** | An instantaneous value that goes up and down: open connections, queue depth, memory | A gauge sampled every 30 seconds misses spikes. If the spike matters, count the event |
| **Histogram** | A distribution: latency, response size | Expensive, see the buckets section |

**Count errors as a label of the main counter**, not as a separate counter: `http_requests_total{status="500"}`. Otherwise the error rate becomes a division between two series that do not always line up.

Quick decision rule: if the question is "how many times", it is a counter. If it is "how many right now", a gauge. If it is "how fast for most cases", a histogram.

## Cardinality: the only mistake that really costs

**A time series is created for each combination of label values.** Cardinality is a product, not a sum: 5 methods × 40 routes × 8 statuses = 1600 series for a single metric. Adding a label with 1000 values multiplies it by 1000.

Effectively forbidden as label values:

- User, order, session or request identifier
- IP address, email address
- **Raw URL**: template the path (`/orders/{id}`), otherwise every identifier creates a series
- Error message or exception trace
- Timestamp in any form

This information already exists elsewhere: it belongs in logs and traces, not in metrics. That is the division of roles between the three signals.

Test before adding a label: **"how many distinct values will this label take in a year, in the worst case?"** If the answer is not a small, bounded and known number, the answer is no.

A cardinality explosion does not show up in development. It shows up in production, when the metrics server saturates.

## What to measure

Two complementary methods, to be applied in full rather than halfway.

**RED, for anything that handles requests** (API, queue consumer, job):

- **Rate**: the throughput, requests per second
- **Errors**: the failure rate, as a proportion of throughput
- **Duration**: the latency distribution

**USE, for any resource** (CPU, memory, disk, connection pool, threads):

- **Utilization**: the occupancy rate
- **Saturation**: what is waiting, the queue. The most predictive signal and the one most often forgotten
- **Errors**: the failures of the resource itself

Saturation is what lets you act **before** the incident. 100% utilization is not a problem if nothing is waiting.

Do not instrument what nobody will look at: every metric costs storage and attention. A metric that appears neither in a dashboard, nor in an alert, nor in a recent investigation should be deleted.

## Histograms, buckets and quantiles

- **Buckets are chosen based on the latency target**, not left at the default. You need a bucket exactly at the objective's value, otherwise the SLO compliance rate cannot be computed.
- **Cost**: one series per bucket and per label combination. Ten buckets multiply cardinality by ten. Five to eight well-placed buckets are better than twenty.
- **The average describes nothing.** An 80 ms average can hide 5% of requests at 4 seconds. Reason in p95 and p99.
- **A quantile cannot be summed or averaged.** Averaging the p95 of three instances does not give the global p95. Aggregate the buckets first, compute the quantile afterwards.
- **p99 on low volume is noise.** At 50 requests per minute, it describes a single request.

## Metric, log or trace

| Need | Signal |
|---|---|
| How many, how fast, what proportion | **Metric** |
| What happened for this specific case | **Log** (`logging-setup`) |
| Where the time went between services | **Trace** (`tracing-setup`) |

Counting events by querying logs is expensive and slow to answer. Conversely, adding a high-cardinality label to find a specific case destroys the metric. Each question has its signal.

## Anti-patterns

| Anti-pattern | Consequence | Fix |
|---|---|---|
| Identifier or raw URL as a label | Cardinality explosion, saturated server | Templated path, identifiers in the logs |
| Unit missing from the name or non-standard | Ambiguous reading, silent conversions | `_seconds`, `_bytes`, `_ratio` |
| Environment written into the name | Aggregation impossible | `env` label |
| Error counter separate from the main counter | Wrong or unstable error rate | `status` label on the counter |
| Buckets left at the default | SLO cannot be measured | A bucket at the objective's value |
| Averaging quantiles across instances | Wrong number, presented as correct | Aggregate the buckets then compute |
| Sampled gauge used to detect a spike | The spike slips between two scrapes | Count the event |
| Saturation not measured | The problem is discovered once saturated | Measure the queue |
| Metrics created but never looked at | Storage cost and noise | Delete what serves neither a dashboard nor an alert |

## Review checklist

1. Every name follows `<namespace>_<subject>_<unit>[_total]`, in base units.
2. No label can take an unbounded number of values.
3. Errors are a label of the main counter, not a separate metric.
4. RED is complete on every entry point, USE is complete on every critical resource, saturation included.
5. Histogram buckets surround the latency target.
6. No quantile is averaged or summed.
7. Every metric added serves an identified dashboard, alert or investigation.
