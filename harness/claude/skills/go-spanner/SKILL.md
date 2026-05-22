---
name: go-spanner
description: "Activate when working with Google Cloud Spanner — covers repository pattern, query builder, transactions, schema design, and optimization."
license: MIT
---

# Google Cloud Spanner Patterns

## Repository Pattern

Repositories implement domain interfaces and encapsulate all Spanner access. The domain layer defines the interface; the adapter layer implements it.

```go
// adapters/spanner/order_repository.go
type OrderRepository struct {
    client  *spanner.Client
    objects *Objects  // Generated facade/accessor layer for type-safe DB access
}

func NewOrderRepository(client *spanner.Client, objects *Objects) *OrderRepository {
    return &OrderRepository{client: client, objects: objects}
}
```

## Objects / Facade Layer

Prefer using a generated or shared objects layer over raw Spanner reads. This layer provides:

- **Type-safe row accessors** — `objects.Order.Get(ctx, txn, key)` instead of manual `row.Column()`
- **Builder pattern** for queries — filter, sort, paginate without raw SQL
- **Consistent NULL handling** — conversion helpers between DB nulls and Go pointers
- **Read transaction variants** — `GetRtx` for read-only, `GetTx` for read-write

```go
// Single-read: use Get() — calls db.Single() internally, no transaction overhead
func (r *OrderRepository) Get(ctx context.Context, id string) (*domain.Order, error) {
    rows, err := r.objects.Order.Get(ctx, []OrderQueryParam{
        {Col: OrderID, Op: OpEq, Val: id},
    }, orderFields)
    if err != nil {
        return nil, fmt.Errorf("reading order %s: %w", id, err)
    }
    // ...
}

// Multi-read: use ReadOnlyTransaction + GetRtx when multiple tables must be
// consistent at the same snapshot (e.g. fetching a root + child rows together)
func (r *OrderRepository) GetWithLines(ctx context.Context, id string) (*domain.Order, error) {
    rtx := r.client.ReadOnlyTransaction()
    defer rtx.Close()

    row, err := r.objects.Order.FindRtx(ctx, rtx, id, orderFields)
    if err != nil {
        return nil, fmt.Errorf("reading order %s: %w", id, err)
    }
    lines, err := r.objects.OrderLine.GetRtx(ctx, rtx, lineParams, lineFields)
    // ...
}
```

## Domain ↔ DB Conversion

Repositories handle all conversion between domain entities and database rows:

```go
// adapters/spanner/converters.go

// DB → Domain (read path)
func toDomainOrder(row *objects.OrderRow) *domain.Order {
    return domain.UnmarshalOrderFromPersistence(
        row.ID,
        domain.Status(row.Status),
        nullStringToPtr(row.Notes),  // NULL handling
        row.CreatedAt,
    )
}

// Domain → DB (write path)
func toOrderMutation(order *domain.Order) *spanner.Mutation {
    return spanner.InsertOrUpdate("orders", orderColumns, []interface{}{
        order.ID(),
        order.Status().String(),
        ptrToNullString(order.Notes()),
        order.CreatedAt(),
        order.UpdatedAt(),
    })
}
```

### NULL Handling Helpers

Use shared utility functions for nullable field conversion:

```go
// Spanner NULL → Go pointer (read path)
func nullStringToPtr(ns spanner.NullString) *string { ... }
func nullTimeToPtr(nt spanner.NullTime) *time.Time { ... }
func nullInt64ToInt(ni spanner.NullInt64) int64 { ... }

// Go pointer → Spanner NULL (write path)
func ptrToNullString(s *string) spanner.NullString { ... }
func ptrToNullTime(t *time.Time) spanner.NullTime { ... }
```

## Query Builder Pattern

```go
b := r.objects.Order.InitBuilder(companyID)
b.ApplyFilter(Field("status"), "=", "active")
b.OrderBy(Field("created_at"))
b.LimitInt64(100, 20)  // limit, offset

rows, err := r.objects.Order.GetByBuilderRtx(ctx, rtx, b)
```

### With Indexes

```go
b := r.objects.Order.InitBuilder(companyID)
b.UseIndex("idx_company_status_created")
b.ApplyFilter(Field("status"), "=", "active")
b.LimitInt64(100, 20)
```

### Known Limitations

Some generated facade methods (`GetRtx`, `ListRtx`) may not support `ORDER BY` or `LIMIT/OFFSET`. In such cases:
- Sort in-memory after fetching
- Paginate by slicing the result set

## Transaction Management

Transactions are **repository concerns** — never exposed to domain or application layers.

### Which read primitive to use

| Situation | Primitive | Why |
|---|---|---|
| Single isolated query | `facade.X.Get()` | Uses `db.Single()` — lightweight, no session held |
| Multiple tables that must be consistent | `ReadOnlyTransaction` + `GetRtx` | Pins all reads to the same timestamp |
| Read-write (command) | `ReadWriteTransaction` | Atomic read + mutate |

```go
// Single query — no transaction needed
func (r *OrderRepository) GetStatus(ctx context.Context, id string) (string, error) {
    rows, err := r.objects.Order.Get(ctx, params, fields)
    // ...
}

// Multi-table consistent read — use ReadOnlyTransaction
func (r *OrderRepository) GetWithLines(ctx context.Context, id string) (*domain.Order, error) {
    rtx := r.client.ReadOnlyTransaction()
    defer rtx.Close()

    row, err := r.objects.Order.FindRtx(ctx, rtx, id, fields)
    lines, err := r.objects.OrderLine.GetRtx(ctx, rtx, params, lineFields)
    // ...
}

// Read-write — for commands that need atomic read+write
func (r *OrderRepository) Save(ctx context.Context, order *domain.Order) error {
    _, err := r.client.ReadWriteTransaction(ctx,
        func(ctx context.Context, txn *spanner.ReadWriteTransaction) error {
            return txn.BufferWrite([]*spanner.Mutation{toOrderMutation(order)})
        })
    return err
}

// Stale reads — when real-time consistency not required
rtx := r.client.ReadOnlyTransaction(spanner.ExactStaleness(15 * time.Second))
```

## Schema Design

- **Composite primary keys** for sharding — avoid monotonic keys that create hotspots
- **Interleaved tables** for parent-child relationships (co-locates data for efficient joins)
- **UUID or reverse-timestamp prefixes** for row keys — prevents write hotspots
- Design for horizontal scaling from the start
- Use `STORING` clause on indexes for covered queries

### Migration Management

Use a schema migration tool (e.g., Liquibase) to manage DDL changes:
- Never manually edit the DDL file
- Migrations are additive — one changelog per change
- Test migrations against an emulator before applying to production

## Query Optimization

- Always use indexes for filtered queries — add `FORCE_INDEX` hint when needed
- Avoid full table scans — Spanner bills by rows read
- Batch mutations for bulk writes (group mutations in a single transaction)
- Use stale reads (`ExactStaleness`) when real-time consistency isn't required
- Monitor query execution plans via Spanner console
- Prefer `IN UNNEST(@param)` over `IN (...)` for parameterized lists

## Connection Pooling

```go
config := spanner.ClientConfig{
    NumChannels: 4,
    SessionPoolConfig: spanner.SessionPoolConfig{
        MinOpened:     100,
        MaxOpened:     400,
        MaxIdle:       10,
        WriteSessions: 0.2,
    },
}
client, err := spanner.NewClientWithConfig(ctx, database, config)
```

## Emulator Testing

- Use the Spanner emulator for integration tests
- Create a unique database per test suite to avoid cross-test pollution
- Apply schema migrations before running tests
- Set `SPANNER_EMULATOR_HOST` environment variable — all Spanner clients in the process will route to it

## Key Rules

- Repositories implement domain interfaces — domain never imports Spanner
- Transactions stay inside repository methods — never leak to application layer
- Use the objects/facade layer for type-safe access — avoid raw `row.Column()` calls
- All NULL ↔ pointer conversions use shared helpers — no inline conversions
- `UnmarshalFromPersistence` for domain rehydration — bypasses constructor validation
