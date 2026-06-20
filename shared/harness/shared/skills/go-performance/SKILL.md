---
name: go-performance
description: "Activate when optimizing Go service performance — covers parallel processing, caching, memory optimization, batch processing, and profiling."
license: MIT
---

# Go Performance Optimization Patterns

## Parallel Processing

```go
// Use errgroup for concurrent independent operations
eg, childCtx := errgroup.WithContext(ctx)

var data1 *Data1
eg.Go(func() error {
    var err error
    data1, err = fetchData1(childCtx)
    return err
})

var data2 *Data2
eg.Go(func() error {
    var err error
    data2, err = fetchData2(childCtx)
    return err
})

if err := eg.Wait(); err != nil {
    return nil, err
}
// Use data1 and data2
```

### Bounded Concurrency

```go
// Limit parallel goroutines for resource-intensive work
eg, childCtx := errgroup.WithContext(ctx)
eg.SetLimit(10)  // Max 10 concurrent goroutines

for _, item := range items {
    eg.Go(func() error {
        return processItem(childCtx, item)
    })
}

if err := eg.Wait(); err != nil {
    return err
}
```

## Caching

```go
type CachedService struct {
    service Service
    cache   Cache
}

func (s *CachedService) Get(ctx context.Context, id string) (*Data, error) {
    cacheKey := fmt.Sprintf("data:%s", id)

    var data Data
    if err := s.cache.Get(ctx, cacheKey, &data); err == nil {
        return &data, nil
    }

    result, err := s.service.Get(ctx, id)
    if err != nil {
        return nil, err
    }

    s.cache.Set(ctx, cacheKey, result, 5*time.Minute)
    return result, nil
}
```

## Memory Optimization

```go
// Pre-allocate slices with known capacity
results := make([]*Result, 0, len(items))

// Reuse allocations with sync.Pool
var bufferPool = sync.Pool{
    New: func() any {
        return new(bytes.Buffer)
    },
}

func processData(data []byte) {
    buf := bufferPool.Get().(*bytes.Buffer)
    defer func() {
        buf.Reset()
        bufferPool.Put(buf)
    }()
    buf.Write(data)
}
```

## Batch Processing

```go
func (s *Service) ProcessBatch(ctx context.Context, items []Item) error {
    const batchSize = 100

    for i := 0; i < len(items); i += batchSize {
        end := min(i+batchSize, len(items))
        batch := items[i:end]

        if err := s.processSingleBatch(ctx, batch); err != nil {
            return fmt.Errorf("batch starting at %d: %w", i, err)
        }
    }
    return nil
}
```

## Profiling

### CPU & Memory

```go
import _ "net/http/pprof"

// In main.go — expose pprof endpoint (dev only)
go func() {
    log.Println(http.ListenAndServe("localhost:6060", nil))
}()
```

```bash
# CPU profile
go tool pprof http://localhost:6060/debug/pprof/profile?seconds=30

# Memory allocations
go tool pprof http://localhost:6060/debug/pprof/heap

# Goroutine leaks
go tool pprof http://localhost:6060/debug/pprof/goroutine
```

### Distributed Tracing

```go
span, ctx := tracer.Start(ctx, "operation-name")
defer span.End()

span.SetAttributes(
    attribute.String("tenant.id", tenantID),
    attribute.Int("batch.size", len(items)),
)
```

## Optimization Checklist

### Database
- Indexes on frequently queried columns
- Avoid N+1 queries — batch or join instead
- Use batch mutations for bulk writes
- Implement cursor-based or offset pagination
- Use stale reads when real-time consistency isn't required

### Memory
- Pre-allocate slices with known capacity
- Use `sync.Pool` for frequently allocated temporary objects
- Avoid unnecessary copying — pass pointers for large structs
- Stream large data instead of loading all in memory
- Clear references to allow GC on long-lived goroutines

### Concurrency
- Use `errgroup` for parallel I/O-bound operations
- Set concurrency limits with `errgroup.SetLimit()` for resource-intensive work
- Use channels for producer-consumer patterns
- Always cancel contexts — prevent goroutine leaks
- Propagate `context.Context` through all call chains

### Caching
- Cache expensive computations and external service calls
- Set appropriate TTLs based on data freshness requirements
- Implement cache warming for critical paths
- Monitor cache hit rates
- Consider distributed cache for horizontally scaled services

### General
- Profile before optimizing — measure, don't guess
- Benchmark critical paths with `testing.B`
- Avoid premature optimization — correctness first
- Watch for allocations in hot paths (`go test -benchmem`)
