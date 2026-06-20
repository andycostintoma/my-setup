# Writing Domain Aggregates

The domain layer is the pure heart of the system. Zero infrastructure, zero dependencies.

## What Goes in Domain

- Aggregate root structs with private fields
- Value objects
- Domain events
- Domain errors
- State machine transitions
- Business invariants and validation
- Change tracking via `aggregate.Base`

## What NEVER Goes in Domain

- `context.Context` — not even as a parameter
- Database types, clients, or imports
- HTTP, gRPC, logging, or I/O
- Adapter or repo imports
- Any import outside standard library + `math/big` + `domainkit`

## How to Write an Aggregate

### 1. Define status types and field tracking

```go
package domain

import (
    "errors"
    "fmt"
    "time"
    "github.com/Vektor-AI/domainkit/aggregate"
)

type OrderStatus string
const (
    StatusDraft     OrderStatus = "DRAFT"
    StatusConfirmed OrderStatus = "CONFIRMED"
    StatusActive    OrderStatus = "ACTIVE"
)

var ErrInvalidTransition = errors.New("invalid transition")

// Field names for change tracking
type Field string
const (
    FieldStatus    Field = "status"
    FieldUpdatedAt Field = "updated_at"
)
```

### 2. Define the aggregate struct — all fields private

```go
type Order struct {
    id          OrderID
    customerID  CustomerID
    status      OrderStatus
    totalAmount *big.Rat       // Money = *big.Rat, suffixed with Amount
    createdAt   time.Time
    updatedAt   time.Time
    *aggregate.Base[Field, any] // Required for change tracking + events
}
```

### 3. Two constructors: Create (new) and Reconstitute (from DB)

```go
// CreateOrder — called when making a brand new order. Validates and raises events.
func CreateOrder(id OrderID, customerID CustomerID, totalAmount *big.Rat, now time.Time) (*Order, error) {
    if totalAmount.Sign() <= 0 {
        return nil, errors.New("total amount must be positive")
    }
    o := &Order{
        id:          id,
        customerID:  customerID,
        status:      StatusDraft,
        totalAmount: totalAmount,
        createdAt:   now,
        updatedAt:   now,
        Base:        aggregate.NewBase[Field, any](),
    }
    o.Events.Add(OrderCreated{OrderID: id, CustomerID: customerID, OccurredOn: now})
    return o, nil
}

// ReconstituteOrder — called by repository when loading from DB. No validation, no events.
func ReconstituteOrder(props OrderProps) *Order {
    return &Order{
        id:          props.ID,
        customerID:  props.CustomerID,
        status:      props.Status,
        totalAmount: props.TotalAmount,
        createdAt:   props.CreatedAt,
        updatedAt:   props.UpdatedAt,
        Base:        aggregate.NewBase[Field, any](),
    }
}
```

### 4. Accessors for each field

```go
func (o *Order) ID() OrderID            { return o.id }
func (o *Order) CustomerID() CustomerID { return o.customerID }
func (o *Order) Status() OrderStatus    { return o.status }
func (o *Order) TotalAmount() *big.Rat  { return o.totalAmount }
```

### 5. Business methods — intention-revealing, track changes, raise events

Every business method must:
- Validate the state transition
- Mutate the field
- Call `o.Changes.Track(FieldX, newValue)` for EVERY changed field
- Call `o.Events.Add(...)` for significant state changes
- Accept `now time.Time` for timestamps (no `time.Now()` inside domain)

```go
func (o *Order) Activate(now time.Time) error {
    if o.status != StatusConfirmed {
        return InvalidTransitionError{From: o.status, To: StatusActive}
    }

    o.status = StatusActive
    o.updatedAt = now

    o.Changes.Track(FieldStatus, o.status)
    o.Changes.Track(FieldUpdatedAt, o.updatedAt)

    o.Events.Add(OrderActivated{
        OrderID:     o.id,
        CustomerID:  o.customerID,
        ActivatedAt: now,
    })

    return nil
}
```

### 6. Define domain events

```go
type OrderCreated struct {
    OrderID    OrderID
    CustomerID CustomerID
    OccurredOn time.Time
}

type OrderActivated struct {
    OrderID     OrderID
    CustomerID  CustomerID
    ActivatedAt time.Time
}
```

### 7. Define domain errors with `Is()` support

```go
type InvalidTransitionError struct {
    From OrderStatus
    To   OrderStatus
}

func (e InvalidTransitionError) Error() string {
    return fmt.Sprintf("cannot transition from %s to %s", e.From, e.To)
}

func (e InvalidTransitionError) Is(target error) bool {
    return target == ErrInvalidTransition
}
```

### 8. Document invariants

```go
// Order represents a customer order.
//
// State Transitions:
//   Draft → Confirmed → Active → Shipped → Completed
//         └──────────────────────────────→ Cancelled
//
// Invariants:
//   - TotalAmount must be positive
//   - Cannot modify in terminal state
//   - CustomerID is immutable after creation
type Order struct { ... }
```

## Checklist Before You're Done

- [ ] All fields private
- [ ] `*aggregate.Base[Field, any]` embedded
- [ ] `CreateX()` and `ReconstituteX()` constructors
- [ ] Accessor for every field
- [ ] `Changes.Track()` for every mutation
- [ ] `Events.Add()` for state changes
- [ ] No `context.Context` anywhere
- [ ] No infrastructure imports
- [ ] Money uses `*big.Rat` with `Amount` suffix
- [ ] Errors use typed structs with `Is()` method
- [ ] Invariants documented in GoDoc
