# Writing Usecases (Interactors)

Usecases orchestrate the flow: load aggregate → call domain → get mutations → build plan → apply.

## Structure

Each usecase gets its own package:

```
usecases/
  activate_order/
    interactor.go       # Main logic
    interactor_test.go  # Tests
    request.go          # Request/Reply types (optional, can be in interactor.go)
    errors.go           # Usecase-specific errors (optional)
```

## How to Write a Usecase

### 1. Define the struct with injected dependencies (contracts only)

```go
package activate_order

import (
    "context"
    "fmt"

    "internal/app/order/contracts"
    "internal/app/order/domain"
    "github.com/Vektor-AI/commitplan"
)

type Options struct {
    Repo      contracts.OrderRepo
    Committer commitplan.Committer
    Clock     contracts.Clock
    Log       contracts.Logger
}

type Interactor struct {
    repo      contracts.OrderRepo
    committer commitplan.Committer
    clock     contracts.Clock
    log       contracts.Logger
}

func New(opts Options) *Interactor {
    return &Interactor{
        repo:      opts.Repo,
        committer: opts.Committer,
        clock:     opts.Clock,
        log:       opts.Log,
    }
}
```

### 2. Define Request (and optionally Reply)

```go
type Request struct {
    OrderID   string
    UserID    string
    CompanyID string
}

// Reply only if returning data. Most commands return error only.
// type Reply struct { ActivatedAt time.Time }
```

### 3. Write Execute — follow the exact flow

```go
func (it *Interactor) Execute(ctx context.Context, req *Request) error {
    // Step 1: Validate inputs BEFORE anything else
    if req.OrderID == "" {
        return ErrMissingOrderID
    }

    // Step 2: Load aggregate via repo
    order, err := it.repo.Retrieve(ctx, req.OrderID)
    if err != nil {
        return fmt.Errorf("retrieve order %s: %w", req.OrderID, err)
    }

    // Step 3: Call domain method
    now := it.clock.Now()
    if err := order.Activate(now); err != nil {
        return err  // Domain errors: return as-is, NEVER wrap
    }

    // Step 4: Get mutations FROM repo (repo reads tracked changes)
    plan := commitplan.NewPlan()
    if mut := it.repo.UpdateMut(order); mut != nil {
        plan.Add(mut)
    }

    // Step 5: Apply plan via committer
    if err := it.committer.Apply(ctx, plan); err != nil {
        it.log.Errorf("failed to apply plan for order %s: %v", req.OrderID, err)
        return fmt.Errorf("apply plan: %w", err)
    }

    it.log.Infof("order %s activated successfully", req.OrderID)
    return nil
}
```

## Key Rules

### What usecases MUST do:
- Validate inputs before domain calls
- Load aggregates through repo contracts (never direct DB)
- Call domain methods for business logic
- Get mutations by calling `repo.UpdateMut(agg)` — never create mutations
- Build a CommitPlan and apply via committer
- Return domain errors as-is (unwrapped)
- Wrap infrastructure errors with `fmt.Errorf("context: %w", err)`

### What usecases MUST NOT do:
- Import concrete repo implementations (only contracts)
- Import another usecase
- Import generated DB models or proto types
- Create mutations directly (e.g., `spanner.Update(...)`)
- Access the database directly
- Contain business logic (that belongs in domain)
- Let handlers apply the plan — usecase applies it

### Constructor rules:
- ≤2 params → direct parameters
- >2 params → Options struct
- Inject all deps via contracts (interfaces)

### Error handling:
```go
// Domain error → return as-is
if err := order.Activate(now); err != nil {
    return err
}

// Infrastructure error → wrap with context
if err := it.repo.Retrieve(ctx, id); err != nil {
    return fmt.Errorf("retrieve order %s: %w", id, err)
}

// Context cancellation → return as-is
if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
    return err
}
```

## Variant: Create Operation

```go
func (it *Interactor) Execute(ctx context.Context, req *Request) (*Reply, error) {
    order, err := domain.CreateOrder(
        domain.NewOrderID(),
        domain.CustomerID(req.CustomerID),
        req.TotalAmount,
        it.clock.Now(),
    )
    if err != nil {
        return nil, err
    }

    plan := commitplan.NewPlan()
    if mut := it.repo.CreateMut(order); mut != nil {
        plan.Add(mut)
    }

    if err := it.committer.Apply(ctx, plan); err != nil {
        return nil, fmt.Errorf("apply plan: %w", err)
    }

    return &Reply{CreatedID: order.ID().String()}, nil
}
```

## Variant: Multi-Aggregate

```go
func (it *Interactor) Execute(ctx context.Context, req *Request) error {
    order, err := it.orderRepo.Retrieve(ctx, req.OrderID)
    if err != nil { return err }

    invoice, err := it.invoiceRepo.Retrieve(ctx, req.InvoiceID)
    if err != nil { return err }

    now := it.clock.Now()
    if err := order.Complete(now); err != nil { return err }
    if err := invoice.MarkPaid(req.TxID, now); err != nil { return err }

    plan := commitplan.NewPlan()
    if mut := it.orderRepo.UpdateMut(order); mut != nil { plan.Add(mut) }
    if mut := it.invoiceRepo.UpdateMut(invoice); mut != nil { plan.Add(mut) }

    return it.committer.Apply(ctx, plan)
}
```

## Checklist

- [ ] Own package under `usecases/<operation>/`
- [ ] Dependencies injected via contracts (interfaces)
- [ ] Options struct if >2 constructor params
- [ ] Input validation before domain calls
- [ ] Domain errors returned as-is
- [ ] Infrastructure errors wrapped
- [ ] Mutations obtained FROM repo (not created directly)
- [ ] Plan built and applied via committer
- [ ] Logging at decision points and failures
- [ ] No imports of concrete repos, other usecases, or DB models
