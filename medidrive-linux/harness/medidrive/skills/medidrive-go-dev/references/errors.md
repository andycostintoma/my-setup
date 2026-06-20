# Writing Errors

## Three Error Layers

### 1. Domain Errors — business rule violations

Live in `domain/errors.go`. Use sentinel errors + typed structs with `Is()`:

```go
package domain

import (
    "errors"
    "fmt"
)

// Sentinel errors for errors.Is() matching
var (
    ErrInvalidTransition = errors.New("invalid state transition")
    ErrOrderNotRefundable = errors.New("order is not refundable")
    ErrInsufficientFunds  = errors.New("insufficient funds")
)

// Typed error with details
type InvalidTransitionError struct {
    From OrderStatus
    To   OrderStatus
}

func (e InvalidTransitionError) Error() string {
    return fmt.Sprintf("cannot transition from %s to %s", e.From, e.To)
}

// Implement Is() so errors.Is(err, ErrInvalidTransition) works
func (e InvalidTransitionError) Is(target error) bool {
    return target == ErrInvalidTransition
}
```

### 2. Application Errors — usecase-level failures

Live in `usecases/errors.go` or in each usecase's `errors.go`:

```go
package usecases

var (
    ErrNotFound         = errors.New("resource not found")
    ErrValidationFailed = errors.New("validation failed")
)

type NotFoundError struct {
    Resource string
    ID       string
}

func (e NotFoundError) Error() string {
    return fmt.Sprintf("%s %s not found", e.Resource, e.ID)
}

func (e NotFoundError) Is(target error) bool {
    return target == ErrNotFound
}

type ValidationError struct {
    Field   string
    Message string
}

func (e ValidationError) Error() string {
    return fmt.Sprintf("validation failed: %s - %s", e.Field, e.Message)
}
```

### 3. Infrastructure Errors — wrap with context

Never define custom types. Just wrap with `fmt.Errorf`:

```go
// In repo
return fmt.Errorf("read order %s: %w", id, err)

// In adapter
return fmt.Errorf("send notification: %w", err)
```

## How Each Layer Handles Errors

```go
// Usecase: domain errors → return as-is
if err := order.Activate(now); err != nil {
    return err  // ✅ Never wrap domain errors
}

// Usecase: infra errors → wrap with context
order, err := it.repo.Retrieve(ctx, id)
if err != nil {
    if errors.Is(err, context.Canceled) {
        return err  // Context errors: return as-is
    }
    return fmt.Errorf("retrieve order %s: %w", id, err)  // ✅ Wrap
}

// Handler: map to gRPC codes
switch {
case errors.Is(err, domain.ErrInvalidTransition):
    return status.Errorf(codes.FailedPrecondition, err.Error())
case errors.Is(err, usecases.ErrNotFound):
    return status.Errorf(codes.NotFound, err.Error())
}
```

## Rules

- Don't leave unused error definitions — remove or document why kept
- Always check nil before dereferencing optional pointers
- Validate optional fields when provided
- Prefer typed errors with `Is()` for matching
