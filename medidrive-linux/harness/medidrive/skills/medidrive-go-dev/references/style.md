# Code Style & Formatting

## Formatting Rules

### Multi-line for >2 parameters

```go
// ❌ Bad
if err := d.SetStatus(req.NewStatus, now, dom.WithReason(req.Reason), dom.WithUserID(req.UserID)); err != nil {

// ✅ Good
if err := d.SetStatus(
    req.NewStatus,
    now,
    dom.WithReason(req.Reason),
    dom.WithUserID(req.UserID),
); err != nil {
```

### Trailing commas — always in multi-line

```go
opts := Options{
    Repo:  repo,
    Clock: clock,
    Log:   logger,  // ✅ trailing comma
}
```

### Early returns over nesting

```go
// ✅ Good: flat and readable
if req.OrderID == "" {
    return ErrMissingOrderID
}
order, err := uc.repo.Retrieve(ctx, req.OrderID)
if err != nil {
    return err
}
if err := order.Activate(now); err != nil {
    return err
}
return uc.save(order)
```

### No one-liners for logic

```go
// ❌ Bad
if repo == nil { repo = n_repo.New(&n_repo.Dependencies{M: f.o.Options.M, Log: f.o.Options.Log}) }

// ✅ Good
if repo == nil {
    repo = n_repo.New(&n_repo.Dependencies{
        M:   f.o.Options.M,
        Log: f.o.Options.Log,
    })
}
```

## Naming

| What | Convention | Example |
|---|---|---|
| Packages | Short, singular | `order`, `repo`, `domain` |
| Exported types | PascalCase | `OrderRepo`, `Interactor` |
| Unexported | lowerCamelCase | `orderRepo`, `interactor` |
| New entity | `CreateX()` | `CreateOrder(...)` |
| From DB | `ReconstituteX()` | `ReconstituteOrder(props)` |
| Money fields | Suffix `Amount` | `totalAmount`, `taxAmount` |
| Field tracking | `FieldX` const | `FieldStatus`, `FieldUpdatedAt` |

## Package Documentation

Every package must have GoDoc:

```go
// Package activate_order implements the activate order use case.
//
// Flow:
//   1. Load order aggregate via repository
//   2. Validate order can be activated
//   3. Call domain Activate method
//   4. Get mutation from repository
//   5. Build and apply CommitPlan
package activate_order
```

## Nil Safety

```go
// Always check optional pointers
if req.Phone != nil && *req.Phone != "" {
    updateFields[user.Phone] = *req.Phone
}

// Validate optional fields when provided
if req.Phone != nil && *req.Phone != "" {
    if !isValidPhoneNumber(*req.Phone) {
        return errs.InvalidPhoneNumber
    }
}

// Consistent nil check patterns
if len(req.Items) > 0 { ... }    // slices
if req.Metadata != nil { ... }   // maps
```

## What to Avoid

- Dead code, commented-out blocks, unused imports
- Circular imports between packages
- Hardcoded secrets — use `os.Getenv()` or secrets manager
- `time.Now()` in domain — accept `now time.Time` as parameter
- Clever code that's hard to read

## Quality Gates (before committing)

```bash
gofmt -s -w .
goimports -w .
go vet ./...
golangci-lint run
go test ./...
go build ./...
go mod tidy && go mod verify
```
