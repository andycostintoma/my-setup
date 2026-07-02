---
name: go-ddd-cleanarch-dev
description: >
  Clean Architecture + DDD coding guide for Go backend services. Use this skill whenever
  the user asks to write, create, implement, build, scaffold, or review Go code that
  involves usecases, interactors, domain aggregates, entities, value objects, repositories,
  services, handlers, contracts, gRPC handlers, HTTP handlers, commit plans, mutations,
  domain events, CQRS commands/queries, or any Clean Architecture / DDD component.
  Also trigger for requests like "write a usecase", "create a domain", "add a repo",
  "implement an interactor", "new aggregate", "new endpoint", "add a feature",
  "scaffold", "boilerplate", or "add a new field" in a layered Go backend service.
---

# Go DDD Clean Architecture Development Skill

You are a senior Go engineer writing production code that follows Clean Architecture + DDD.
These rules are strict defaults for layered Go backend services. When the target project
already has a local pattern, follow it unless it violates the layer boundaries below.

Do not force this skill onto flat CLIs, small scripts, generated code, or simple handlers
that do not have domain/application layers. Use modern Go and the existing codebase first.

## Before You Write Any Code

1. Identify what you are building: domain, contract, usecase, query, repository, adapter, transport, or test.
2. Read the neighboring packages that already implement the same kind of component.
3. Follow the existing names, constructor shape, error style, and test style when they are compatible with this architecture.
4. Keep the change small. Do not add frameworks, registries, factories, or abstractions for one caller.
5. If a rule conflicts with shipped project behavior, stop and ask instead of silently inventing a third pattern.

## What To Read First

| You are writing... | Read first |
|---|---|
| Domain aggregate / entity | Neighboring `domain/` package and its tests |
| Value object | Existing value objects and validation errors |
| Usecase / interactor | Neighboring `usecases/<operation>/` or command handler |
| Query | Existing `queries/` or read-model handlers |
| Repository | Existing repo adapter and contract interface |
| Contracts / interfaces | Existing `contracts/`, `ports/`, or domain interfaces |
| gRPC / HTTP transport | Existing handler, mapper, and error mapping files |
| Tests | Existing domain/usecase tests using the same fakes/adapters |
| Money / currency | Existing exact decimal/rational type used by the project |
| Any Go code | `go.mod`, package layout, lint/style conventions |

## Golden Rules

These rules apply to all handwritten code in a layered Go backend.

### Rule 1: Mandatory Write Flow

All data modification follows this sequence unless the repository has a clearly established equivalent:

```text
1. Handler receives request and maps from proto/HTTP/CLI DTO to usecase Request.
2. Handler calls usecase.Execute(ctx, req) or handler.Handle(ctx, cmd).
3. Usecase validates application-level input.
4. Usecase loads aggregate via repo.Retrieve/Get/Find(ctx, id).
5. Usecase calls domain methods, e.g. agg.Activate(now).
6. Domain enforces business rules and records state changes.
7. Usecase builds a commit plan, unit of work, or transaction boundary.
8. Repository returns mutations or saves through that unit of work.
9. Usecase commits once, atomically.
10. Handler maps response back to proto/HTTP/CLI DTO.
```

No shortcuts:

- Handler must not mutate persistence directly.
- Repository must not make business decisions.
- Domain must not know about transport, database, queues, logs, or commits.
- Usecase must not scatter multiple commits unless the business process explicitly requires it.

### Rule 2: Layer Dependencies Point Inward

```text
[Transport / Handlers] -> [Application / Usecases] -> [Domain]
                                 |
                                 v
                         [Contracts / Ports]
                                 ^
                                 |
                    [Adapters / Repositories]
```

- Domain imports no infrastructure: no database clients, proto packages, HTTP frameworks, loggers, queues, repos, adapters, or `context`.
- Usecases import domain and contracts/ports, not concrete infrastructure packages.
- Repositories/adapters implement contracts and translate between storage/external models and domain models.
- Transport handles auth, parsing, request mapping, response mapping, and error mapping.
- Generated code stays at boundaries. Never let generated proto/ORM types leak into domain.

### Rule 3: Domain Is Pure

- No `context.Context` in domain methods.
- No `time.Now()` inside domain behavior. Pass time in: `func (o *Order) Activate(now time.Time) error`.
- All fields private unless the project has a strong reason otherwise.
- Expose accessors, not mutable internals.
- Constructors validate new data.
- Reconstitution functions rebuild already-persisted data without replaying creation rules.
- Domain methods own business transitions.
- Domain errors are returned as-is, not wrapped.

```go
func CreateOrder(id string, now time.Time) (*Order, error) {
    if id == "" {
        return nil, ErrMissingOrderID
    }

    return &Order{
        id:        id,
        status:    StatusPending,
        createdAt: now,
        updatedAt: now,
    }, nil
}

func ReconstituteOrder(
    id string,
    status Status,
    createdAt time.Time,
    updatedAt time.Time,
) *Order {
    return &Order{
        id:        id,
        status:    status,
        createdAt: createdAt,
        updatedAt: updatedAt,
    }
}
```

### Rule 4: Business Logic Lives On Domain Objects

Correct:

```go
func (o *Order) Activate(now time.Time) error {
    if o.status != StatusPending {
        return ErrInvalidTransition
    }

    o.status = StatusActive
    o.updatedAt = now
    return nil
}
```

Wrong:

```go
func (it *Interactor) Execute(ctx context.Context, req *Request) error {
    order, err := it.orders.Retrieve(ctx, req.OrderID)
    if err != nil {
        return err
    }

    if order.Status() != domain.StatusPending {
        return domain.ErrInvalidTransition
    }

    order.SetStatus(domain.StatusActive)
    return it.orders.Save(ctx, order)
}
```

The usecase orchestrates. The domain decides.

### Rule 5: Repositories Do Persistence, Not Policy

Repositories load, map, and persist. They do not validate business rules or decide state transitions.

When the project uses mutation/commit-plan patterns, repositories return mutations and never apply them:

```go
func (r *OrderRepo) UpdateMut(order *domain.Order) *spanner.Mutation {
    updates := map[string]any{
        "status":     order.Status(),
        "updated_at": order.UpdatedAt(),
    }

    return r.model.UpdateMut(order.ID(), updates)
}
```

Wrong:

```go
func (r *OrderRepo) Update(order *domain.Order) error {
    mut := r.model.UpdateMut(order.ID(), updates)
    _, err := r.client.Apply(ctx, []*spanner.Mutation{mut})
    return err
}
```

If the project uses a unit-of-work instead of mutation returns, keep the same principle: the application layer owns the transaction boundary.

### Rule 6: Change Tracking Must Be Complete When Present

If the project has `Changes`, dirty fields, event sourcing, patch structs, or mutation builders, every field mutation must be tracked.

Correct:

```go
func (o *Order) SetTotalAmount(totalAmount *big.Rat) {
    o.totalAmount = totalAmount
    o.Changes.Track(FieldTotalAmount, totalAmount)
}
```

Wrong:

```go
func (o *Order) SetTotalAmount(totalAmount *big.Rat) {
    o.totalAmount = totalAmount
}
```

Tests must verify dirty state when the project exposes it:

```go
err := order.Activate(now)
require.NoError(t, err)
assert.True(t, order.Changes.Dirty())
assert.True(t, order.Changes.Has(domain.FieldStatus))
```

Auto-reject if:

- A field changes without dirty/change tracking in a project that uses tracking.
- A repository update ignores dirty fields and writes stale/full state by accident.
- Tests cover the method result but not the tracked change.

### Rule 7: Domain Events For Meaningful State Changes When Present

If the project has domain events or an outbox, every meaningful state transition raises an event.

Correct:

```go
func (o *Order) Activate(now time.Time) error {
    if o.status != StatusPending {
        return ErrInvalidTransition
    }

    o.status = StatusActive
    o.updatedAt = now
    o.Changes.Track(FieldStatus, StatusActive)
    o.Events.Add(OrderActivated{OrderID: o.id, OccurredAt: now})
    return nil
}
```

Wrong:

```go
func (o *Order) Activate(now time.Time) error {
    o.status = StatusActive
    return nil
}
```

In the usecase, commit events atomically with persistence using the project's existing mechanism:

```go
if err := plan.AddAggregateSideEffects(
    order,
    req.TenantID,
    req.OrderID,
    it.eventRepo,
    it.activityRepo,
); err != nil {
    return err
}
```

Auto-reject if:

- State changes without an event in a project that uses events.
- Aggregate events are never pulled/drained into the commit path.
- Event mutations are committed separately from state changes.
- Proto/generated transport types are stored in domain events instead of domain-native event types.

### Rule 8: Money Must Be Exact

- Never use `float32` or `float64` for currency.
- Use the exact money type already standard in the repo: `*big.Rat`, decimal package, integer minor units, or a Money value object.
- Variable names for currency should end in `Amount`, e.g. `totalAmount`, `taxAmount`, `fareAmount`.
- Tests must not assert money with float comparisons.
- Conversion to display strings belongs at transport/presentation boundaries.

### Rule 9: Tests Exercise Usecases, Not Networks

Domain tests call domain methods directly.

Usecase tests call usecases directly:

```go
err := app.Order.Activate.Execute(ctx, &activate.Request{
    OrderID: orderID,
})
require.NoError(t, err)
```

Do not test business behavior through gRPC/HTTP unless the behavior under test is transport mapping:

```go
_, err := grpcClient.ActivateOrder(ctx, &pb.ActivateOrderRequest{
    OrderId: orderID,
})
```

Auto-reject if:

- Integration tests go through gRPC just to test usecase/domain behavior.
- Domain aggregates are mocked.
- Domain state transitions lack direct tests.
- Usecase tests skip commit-plan/unit-of-work assertions.
- Event-producing methods do not assert emitted events or outbox mutations.

## Canonical Directory Layout

Prefer the existing repository layout. When creating new code in a repo without a clear local shape, use this structure:

```text
internal/
  app/<area>/
    domain/           # aggregates, value objects, events, errors, state machines
    contracts/        # ports/interfaces, usually tiny and consumer-owned
    usecases/         # one package per write operation
      <operation>/
        interactor.go
        interactor_test.go
        request.go    # request/reply types when useful
        errors.go     # usecase-specific errors when useful
    queries/          # CQRS read-side, no mutations
      <query_name>/
        query.go
        query_test.go
    repo/             # persistence adapters, storage-to-domain mapping
    adapters/         # external service adapters
    services/         # thin facades/wiring only when existing project uses them
  transport/
    grpc/
      <area>/
        handler.go
        mappers.go
        errors.go
    http/
      <area>/
        handler.go
        mappers.go
        errors.go
pkg/                  # shared reusable packages only when genuinely reusable
cmd/                  # application entrypoints and DI wiring
```

Do not add all directories for a tiny feature. Add only the files the feature needs.

## Component Rules

### Domain Aggregate / Entity

Must have:

- Private fields.
- Constructor for new valid objects.
- Reconstitution path for persisted objects when needed.
- Accessors for read-only state.
- Methods for business transitions.
- Domain errors for invalid transitions.
- Change tracking and events if the project uses them.

Avoid:

- Setters that bypass invariants.
- `context.Context`.
- Database tags unless the project explicitly uses domain-as-persistence-model, and even then avoid adding more coupling.
- Proto/HTTP/ORM imports.
- Logging.

### Usecase / Interactor

Must have:

- Dependencies injected through constructor/options.
- Interfaces for outbound dependencies.
- Input validation before domain calls.
- One transaction/commit boundary for a logical write.
- Infrastructure errors wrapped with useful context.
- Domain errors returned as-is.

Typical shape:

```go
type Interactor struct {
    orders    contracts.OrderRepo
    committer contracts.Committer
    clock     Clock
}

type Options struct {
    Orders    contracts.OrderRepo
    Committer contracts.Committer
    Clock     Clock
}

func New(opts Options) *Interactor {
    return &Interactor{
        orders:    opts.Orders,
        committer: opts.Committer,
        clock:     opts.Clock,
    }
}
```

### Contracts / Interfaces

Interfaces should be small and owned by the layer that consumes them.

Correct:

```go
type OrderRepo interface {
    Retrieve(ctx context.Context, id string) (*domain.Order, error)
    UpdateMut(order *domain.Order) Mutation
}
```

Avoid:

```go
type Repository interface {
    Create(ctx context.Context, v any) error
    Update(ctx context.Context, v any) error
    Delete(ctx context.Context, id string) error
    List(ctx context.Context, filter any) ([]any, error)
}
```

Compile-time checks are encouraged when the project uses them:

```go
var _ contracts.OrderRepo = (*OrderRepo)(nil)
```

### Repository / Adapter

Must have:

- Storage-to-domain mapping in one place.
- Domain-to-storage mapping in one place.
- No business rules.
- No direct commits when a commit-plan/unit-of-work exists.
- Context only on I/O methods, not domain methods.

### Transport Handler

Must have:

- Request validation that belongs to transport shape, such as malformed IDs or missing required proto fields.
- Mapping from transport request to usecase request.
- Call into one usecase/query.
- Mapping from usecase response to transport response.
- Error mapping through existing helper.

Must not have:

- Domain state transitions.
- Repository calls.
- Commit plans.
- Business branching beyond transport concerns.

## Error Handling

Three error types, each handled differently:

| Type | Where | How to handle |
|---|---|---|
| Domain | Domain methods | Return as-is, never wrap |
| Application | Usecase validation | Typed/sentinel errors |
| Infrastructure | Repos/adapters/external services | Wrap with `fmt.Errorf("context: %w", err)` |

Correct:

```go
if err := order.Activate(now); err != nil {
    return err
}

order, err := it.orders.Retrieve(ctx, req.OrderID)
if err != nil {
    return fmt.Errorf("retrieve order %s: %w", req.OrderID, err)
}
```

Rules:

- Validate application inputs before calling domain methods.
- Keep domain errors stable and comparable when callers branch on them.
- Wrap infrastructure errors with operation and key identifiers.
- Do not wrap just to add noise like `failed to` everywhere.
- Do not convert errors to transport status codes outside the transport layer.

## CQRS Patterns

### Command / Write Path

Commands go through domain and commit atomically:

```go
func (it *Interactor) Execute(ctx context.Context, req *Request) error {
    if req.ID == "" {
        return ErrMissingID
    }

    agg, err := it.repo.Retrieve(ctx, req.ID)
    if err != nil {
        return fmt.Errorf("retrieve aggregate %s: %w", req.ID, err)
    }

    if err := agg.Update(req.Value, it.clock.Now()); err != nil {
        return err
    }

    plan := commitplan.NewPlan()
    plan.Add(it.repo.UpdateMut(agg))
    return it.committer.Apply(ctx, plan)
}
```

### Query / Read Path

Queries may bypass domain when they do not mutate state:

```go
func (q *Query) Execute(ctx context.Context, req *Request) (*Reply, error) {
    if req.ID == "" {
        return nil, ErrMissingID
    }

    dto, err := q.readModel.GetSummary(ctx, req.ID)
    if err != nil {
        return nil, fmt.Errorf("get summary %s: %w", req.ID, err)
    }

    return &Reply{Summary: dto}, nil
}
```

Query rules:

- No domain mutations.
- No commit plans.
- Use read models/DTOs when the data is projection-shaped.
- Still validate request fields.
- Still wrap infrastructure errors.

## Side Effects And Outbox

When the project has an outbox or side-effect mechanism:

1. Domain raises domain-native events.
2. Usecase drains events from the aggregate.
3. Usecase converts events to outbox/activity/note mutations through existing adapters.
4. Usecase commits state mutations and event/side-effect mutations atomically.

```go
o.Events.Add(OrderPlaced{OrderID: o.ID(), OccurredAt: now})

if err := plan.AddAggregateSideEffects(
    o,
    req.TenantID,
    req.ID,
    it.noteRepo,
    it.activityRepo,
); err != nil {
    return err
}
```

Do not publish messages directly from domain. Do not publish messages before the database commit succeeds.

## Code Style Rules

Follow these unless the repository has stricter local rules:

- More than two parameters: prefer multi-line call/declaration with trailing commas.
- Use trailing commas in multi-line composite literals.
- Use early returns over deep nesting.
- Avoid one-liners for real logic; keep branches readable.
- Package names should be short and singular: `order`, not `orders`.
- Constructors should make creation intent clear: `CreateX`, `NewX`, or the existing project convention.
- Reconstitution functions should make persistence intent clear: `ReconstituteX`, `FromRecord`, or the existing convention.
- Use options structs when constructors need more than two or three dependencies.
- Add package-level GoDoc when the project requires it.
- Prefer standard library helpers and modern Go features supported by the module's Go version.
- Keep interfaces near consumers unless the project has a clear contracts package.

```go
opts := Options{
    Repo:  repo,
    Clock: clock,
    Log:   logger,
}

if req.OrderID == "" {
    return ErrMissingOrderID
}
```

## Review Checklist

Before considering Go Clean Architecture / DDD code done, check:

- Does the domain contain the business rule?
- Does the usecase orchestrate rather than decide domain policy?
- Are repositories free of business logic?
- Is the transaction/commit boundary in the application layer?
- Are generated/transport types stopped at the boundary?
- Are infrastructure errors wrapped and domain errors returned as-is?
- Are money values exact, never floats?
- Are state changes tracked when the project has tracking?
- Are domain events raised when the project has events?
- Are events/outbox side effects committed atomically with state?
- Do tests hit domain/usecase directly instead of going through the network?
- Did you add only the files needed for this feature?

## Auto-Reject Patterns

Reject or rewrite code that does any of this:

- Imports database/proto/HTTP/logger packages in domain.
- Passes `context.Context` into domain methods.
- Calls `time.Now()` inside domain state transitions.
- Mutates aggregate fields outside aggregate methods.
- Adds a setter that bypasses invariants.
- Puts business branching in handlers or repositories.
- Applies repository mutations directly when the project uses commit plans.
- Commits multiple times for one logical write without a strong reason.
- Uses `float32` or `float64` for money.
- Mocks domain aggregates.
- Tests usecase behavior through gRPC/HTTP instead of calling the usecase.
- Adds generic repositories, factories, or service layers for one implementation.
- Creates new architecture when the existing local pattern already works.
