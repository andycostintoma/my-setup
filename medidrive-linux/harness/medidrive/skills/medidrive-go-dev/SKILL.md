---
name: medidrive-go-dev
description: >
  Clean Architecture + DDD coding guide for the MediDrive NEMT Go backend specifically — the
  github.com/Vektor-AI/{commitplan,domainkit,cron} framework contract, Spanner mutations, CompanyID
  tenancy, and the coverage gates. Use this skill only when working inside a MediDrive/Vektor-AI Go
  repo (usecases, aggregates, repositories, contracts, gRPC handlers, commit plans, cron jobs).
  For Go/DDD work in any other repo use go-ddd-cleanarch-dev instead; for optimization use
  go-performance; for syntax modernization use use-modern-go.
---

# MediDrive Go Development Skill

You are a senior Go engineer (A+ grade) writing production code following Clean Architecture + DDD.
These patterns are **engineering law** — every line of code you write MUST comply. When in doubt, stop and ask.

The generic Clean Architecture / DDD rules live in the `go-ddd-cleanarch-dev` skill. This skill adds
what is specific to this codebase: the Vektor-AI framework APIs, Spanner, `CompanyID` tenancy, and the
coverage gates.

## Before You Write Any Code

1. **Identify what you're building** — which layer(s) does it touch?
2. **Read the relevant reference + template files** from the tables below.
3. **Follow the templates exactly** — they encode battle-tested patterns.
4. **Never take shortcuts** — the mandatory flow exists for good reasons.

### Which reference to read

| You're writing... | Read reference | Read template |
|---|---|---|
| Domain aggregate / entity | `references/domain.md` | `templates/domain.md` |
| Usecase / interactor | `references/usecase.md` | `templates/usecase.md` |
| Repository | `references/repository.md` | `templates/repo.md` |
| Contracts / interfaces | `references/contracts.md` | `templates/contracts.md` |
| gRPC handler / transport | `references/transport.md` | — |
| Tests | `references/testing.md` | `templates/usecase_test.md` |
| Error types | `references/errors.md` | — |
| Money / currency logic | `references/money.md` | — |
| Any Go code | `references/style.md` | — |

---

## The Golden Rules

These rules apply to ALL code you write. Memorize them.

### Rule 1: The Mandatory Flow

All data modification follows this exact sequence — NO shortcuts:

```
1. Handler receives request → maps from proto/HTTP to usecase Request
2. Handler calls usecase.Execute(ctx, req)
3. Usecase loads aggregate via repo.Retrieve(ctx, id)
4. Usecase calls domain methods (agg.Activate(now)) → domain tracks changes
5. Usecase gets mutations via repo.UpdateMut(agg) → repo reads changes
6. Usecase builds CommitPlan, adds mutations
7. Usecase applies plan via committer.Apply(ctx, plan)
8. Handler maps response back to proto/HTTP
```

### Rule 2: Layer Dependencies (inward only)

```
[Transport/Handlers] → [Usecases] → [Domain (pure center)]
```

- **Domain** imports NOTHING external — no `context`, no repos, no adapters
- **Usecases** import only `contracts` (interfaces) and `domain`
- **Repos/Adapters** implement contracts, import `domain`
- **Transport** handles proto/HTTP, calls usecases

### Rule 3: Domain Is Pure

- No `context.Context` — ever
- All fields private, exposed via accessors
- Track every mutation: `o.Changes.Track(FieldX, value)`
- Raise events for state changes: `o.Events.Add(XHappened{...})`
- Time comes as a parameter: `func (o *Order) Activate(now time.Time) error`

### Rule 4: Repos Return Mutations, Never Apply

```go
// ✅ Repo RETURNS mutation
func (r *OrderRepo) UpdateMut(order *domain.Order) *spanner.Mutation {
    return r.model.UpdateMut(order.ID(), updates)
}

// ❌ NEVER: Repo applies mutation
func (r *OrderRepo) Update(order *domain.Order) error {
    _, err := r.client.Apply(ctx, []*spanner.Mutation{mut})
    return err
}
```

### Rule 5: Money = `*big.Rat`, Always

- All currency: `*big.Rat` — never `float32`/`float64`
- Variable names: always suffix with `Amount` (e.g., `totalAmount`, `taxAmount`)
- Tests too — no float assertions for money

### Rule 6: Domain Events (State Changes Must Raise Events)

Every state change in the domain MUST raise an event — no exceptions:

```go
// ✅ Correct — state change + event
func (o *Order) Activate(now time.Time) error {
    if o.status != StatusPending {
        return ErrInvalidTransition
    }
    o.status = StatusActive
    o.Changes.Track(FieldStatus, StatusActive)
    o.Events.Add(OrderActivated{OrderID: o.id, OccurredOn: now})
    return nil
}

// ❌ WRONG — state change without event
func (o *Order) Activate(now time.Time) error {
    o.status = StatusActive
    return nil
}
```

In usecase, events are committed atomically via `AddAggregateSideEffects`:
```go
if err := plan.AddAggregateSideEffects(
    agg, req.CompanyID, req.ID,
    it.noteRepo, it.activityRepo,
); err != nil {
    return err
}
```

Auto-reject if:
- State change without `o.Events.Add(...)`
- Missing `PullOutboxEvents()` on aggregate
- Events not added to commit plan
- Missing `ConvertOutboxEventsToMutations()`
- Direct proto types used inside domain (use event builders)

### Rule 7: Change Tracking (Every Field Mutation Must Be Tracked)

Every field mutation in domain MUST call `Changes.Track()`:

```go
// ✅ Correct
func (o *Order) SetAmount(amount *big.Rat) {
    o.amount = amount
    o.Changes.Track(FieldAmount, amount)  // required
}

// ❌ WRONG — mutation without tracking
func (o *Order) SetAmount(amount *big.Rat) {
    o.amount = amount
}
```

Tests MUST verify `Changes.Dirty()`:
```go
// ✅ Test must check dirty state
err := agg.Activate(now)
require.NoError(t, err)
assert.True(t, agg.Changes.Dirty())   // required
assert.True(t, agg.Changes.Has(domain.FieldStatus))
```

Auto-reject if:
- Field mutation without `Changes.Track()`
- Missing `aggregate.Base[Field, Event]` embedding
- Tests missing `Changes.Dirty()` verification

### Rule 8: E2E Tests Must Call Usecases Directly (Never gRPC)

```go
// ✅ Correct — test calls usecase directly
err := app.Order.Activate.Execute(ctx, &activate.Request{
    OrderID: orderID,
})
require.NoError(t, err)

// ❌ WRONG — test goes through gRPC transport
_, err := grpcClient.ActivateOrder(ctx, &pb.ActivateOrderRequest{
    OrderId: orderID,
})
```

Auto-reject if:
- E2E/integration test uses `grpcClient` instead of direct usecase call
- Domain coverage < 90%
- Usecase coverage < 80%
- Domain aggregates are mocked in tests (NEVER mock domain)

---

## Canonical Directory Layout

When creating new files, place them in the correct location:

```
internal/
  app/<area>/
    domain/           # Aggregates, value objects, events, errors, state machines
    contracts/        # Port interfaces (tiny, 1-3 methods each)
    usecases/         # One package per usecase
      <operation>/
        interactor.go
        interactor_test.go
        request.go    # Request/Reply types (optional)
        errors.go     # Usecase-specific errors (optional)
    queries/          # CQRS read-side (no mutations!)
      <query_name>/
        query.go
    repo/             # Repository adapters (DB ↔ domain mapping)
    adapters/         # External service adapters
    services/         # Service facades (thin wiring)
  transport/
    grpc/             # gRPC handlers, proto mappers, error mapping
      <area>/
        handler.go
        mappers.go
        errors.go
pkg/                  # Shared reusable packages
cmd/                  # Application entrypoints, DI wiring
```

---

## Code Style Rules

Follow these in every file:

- **>2 parameters → multi-line** with trailing comma on each line
- **Trailing commas** in all multi-line composite literals
- **Early returns** over deep nesting
- **No one-liners** for logic — always multi-line blocks
- **Package names**: short, singular (`order`, not `orders`)
- **Constructors**: `CreateX()` for new, `ReconstituteX()` from DB
- **Options struct** when constructor needs >2 params
- **Compile-time interface checks**: `var _ contracts.XRepo = (*XRepo)(nil)`
- **Package-level GoDoc** on every package

```go
// ✅ Good style
opts := Options{
    Repo:  repo,
    Clock: clock,
    Log:   logger,  // trailing comma
}

// ✅ Early return
if req.OrderID == "" {
    return ErrMissingOrderID
}
```

---

## Error Handling

Three error types, each handled differently:

| Type | Where | How to handle |
|---|---|---|
| **Domain** | Domain methods | Return as-is, never wrap |
| **Application** | Usecase validation | Custom typed errors |
| **Infrastructure** | Repos/adapters | Wrap with `fmt.Errorf("context: %w", err)` |

```go
// Domain error — return as-is
if err := order.Activate(now); err != nil {
    return err  // ✅ Don't wrap
}

// Infrastructure error — wrap with context
order, err := uc.repo.Retrieve(ctx, req.OrderID)
if err != nil {
    return fmt.Errorf("retrieve order %s: %w", req.OrderID, err)  // ✅ Wrap
}
```

Always validate inputs BEFORE calling domain methods.

---

## Quick Patterns

### CQRS: Command vs Query

**Command** (write) — goes through domain, builds plan:
```go
func (it *Interactor) Execute(ctx context.Context, req *Request) error {
    agg, _ := it.repo.Retrieve(ctx, req.ID)
    agg.Update(req.Value, it.clock.Now())
    plan := commitplan.NewPlan()
    plan.Add(it.repo.UpdateMut(agg))
    return it.committer.Apply(ctx, plan)
}
```

**Query** (read) — bypasses domain, queries directly:
```go
func (q *Query) Execute(ctx context.Context, req *Request) (*Reply, error) {
    dto, err := q.readModel.GetSummary(ctx, req.ID)
    if err != nil { return nil, err }
    return &Reply{Summary: dto}, nil
}
```

### Side Effects (Modern Pattern)
```go
if err := plan.AddAggregateSideEffects(
    agg, req.CompanyID, req.ID,
    it.noteRepo, it.activityRepo,
); err != nil {
    return err
}
```

### Outbox Pattern (Domain Events)
```go
// In domain: raise event
o.Events.Add(OrderPlaced{OrderID: o.ID(), OccurredOn: now})

// In usecase: events are picked up by AddAggregateSideEffects
// and committed atomically with the plan
```
