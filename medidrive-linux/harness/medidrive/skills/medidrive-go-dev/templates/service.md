//internal/app/<AREA>/usecases/<action>/<action>.go
```go
package <action>

import (
    "context"
    "errors"
    "fmt"

    "internal/app/<AREA>/contracts"
    "internal/app/<AREA>/domain"
    "github.com/Vektor-AI/commitplan"
)

// Request is the input for this usecase.
type Request struct {
    ID string
    // ... other fields
}

// Reply is the output (OPTIONAL - only if returning data like created IDs).
// Most commands return error only.
type Reply struct {
    CreatedID string  // Example: for create operations
}

type Interactor struct {
    repo      contracts.<Entity>Repo
    committer commitplan.Committer  // ✅ Usecase has committer
    clock     contracts.Clock
    log       contracts.Logger
}

type Options struct {
    Repo      contracts.<Entity>Repo
    Committer commitplan.Committer
    Clock     contracts.Clock
    Log       contracts.Logger
}

func New(opts Options) *Interactor {
    return &Interactor{
        repo:      opts.Repo,
        committer: opts.Committer,
        clock:     opts.Clock,
        log:       opts.Log,
    }
}

// Execute orchestrates the use case.
//
// Flow:
//   1. Load aggregate via repository
//   2. Execute domain logic
//   3. Get mutations FROM repo (repo.UpdateMut returns mutation)
//   4. Build commit plan
//   5. Apply plan via committer
//   6. Return error only (nil = success)
//
// CRITICAL: Usecase applies the plan, NOT the handler/service.
func (it *Interactor) Execute(ctx context.Context, req *Request) error {
    // Step 1: Load aggregate
    e, err := it.repo.Retrieve(ctx, req.ID)
    if err != nil {
        if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
            return err
        }
        it.log.Errorf("failed to retrieve entity %s: %v", req.ID, err)
        return fmt.Errorf("retrieve failed: %w", err)
    }

    // Step 2: Execute domain logic
    now := it.clock.Now()
    if err := e.Activate(now); err != nil {
        it.log.Errorf("failed to activate entity %s: %v", req.ID, err)
        return err
    }

    // Step 3: Build commit plan - GET mutations FROM repo
    plan := commitplan.NewPlan()

    if mut := it.repo.UpdateMut(e); mut != nil {
        plan.Add(mut)
    }

    // Step 4: Apply plan via committer
    if err := it.committer.Apply(ctx, plan); err != nil {
        it.log.Errorf("failed to apply plan for entity %s: %v", req.ID, err)
        return fmt.Errorf("apply plan: %w", err)
    }

    it.log.Infof("entity %s activated successfully", req.ID)

    // Step 5: Return nil (success) - no wasteful allocations
    return nil
}
```

---

## Variant: Create Operation (Returns Created ID)

```go
func (it *Interactor) Execute(ctx context.Context, req *Request) (*Reply, error) {
    // Create new aggregate
    entity := domain.CreateEntity(req.ID, req.Data, it.clock.Now())

    // Build plan
    plan := commitplan.NewPlan()

    if mut := it.repo.CreateMut(entity); mut != nil {
        plan.Add(mut)
    }

    // Apply plan
    if err := it.committer.Apply(ctx, plan); err != nil {
        it.log.Errorf("failed to create entity: %v", err)
        return nil, fmt.Errorf("apply plan: %w", err)
    }

    // Return created ID
    return &Reply{CreatedID: entity.ID()}, nil
}
```

---

## Variant: Multi-Aggregate Composition

```go
func (it *Interactor) Execute(ctx context.Context, req *Request) error {
    // Load multiple aggregates
    order, err := it.orderRepo.Retrieve(ctx, req.OrderID)
    if err != nil {
        return err
    }

    invoice, err := it.invoiceRepo.Retrieve(ctx, req.InvoiceID)
    if err != nil {
        return err
    }

    // Execute domain logic on each
    now := it.clock.Now()
    if err := order.Complete(now); err != nil {
        return err
    }

    if err := invoice.MarkPaid(req.TransactionID, now); err != nil {
        return err
    }

    // Build plan with all mutations
    plan := commitplan.NewPlan()

    if mut := it.orderRepo.UpdateMut(order); mut != nil {
        plan.Add(mut)
    }

    if mut := it.invoiceRepo.UpdateMut(invoice); mut != nil {
        plan.Add(mut)
    }

    // Apply once atomically
    if err := it.committer.Apply(ctx, plan); err != nil {
        return fmt.Errorf("apply plan: %w", err)
    }

    return nil
}
```

---

## Key Points

1. **Usecase has committer** - Applies plan internally
2. **Returns error only** - For most operations (nil = success)
3. **Returns Reply** - Only when need to return data (created IDs, calculated values)
4. **Gets mutations FROM repo** - Never creates mutations directly
5. **Builds and applies plan** - Transaction control in usecase

---

## See Also

- layers/application/usecases.md - Usecase structure and patterns
- layers/application/commitplan.md - CommitPlan usage
- layers/infrastructure/repositories.md - Repository mutation pattern
- templates/usecase.md - Full usecase template