# Writing Repositories

Repositories are **dumb mappers** between the database and domain. No business logic.

## What Repos Do

1. **Retrieve**: Load from DB → unmarshall → return domain aggregate
2. **UpdateMut / CreateMut**: Read aggregate's tracked changes → return mutation (NEVER apply)

## How to Write a Repository

### 1. Implement the contract interface

```go
package repo

import (
    "context"
    "fmt"

    "internal/app/order/contracts"
    "internal/app/order/domain"
)

type OrderRepo struct {
    client *spanner.Client
    model  m_order.Model
}

func NewOrderRepo(client *spanner.Client, model m_order.Model) *OrderRepo {
    return &OrderRepo{client: client, model: model}
}

// Compile-time interface check — ALWAYS include this
var _ contracts.OrderRepo = (*OrderRepo)(nil)
```

### 2. Retrieve — repo-side unmarshalling

The repo reads from DB and converts to a domain aggregate using `Reconstitute`:

```go
func (r *OrderRepo) Retrieve(ctx context.Context, id string) (*domain.Order, error) {
    row, err := r.model.ReadRow(ctx, r.client.Single(), id)
    if err != nil {
        return nil, fmt.Errorf("read order %s: %w", id, err)
    }

    // Repo-side unmarshalling: DB model → domain aggregate
    order := domain.ReconstituteOrder(domain.OrderProps{
        ID:          domain.OrderID(row.ID),
        CustomerID:  domain.CustomerID(row.CustomerID),
        Status:      domain.OrderStatus(row.Status),
        TotalAmount: row.TotalAmount,  // Already *big.Rat from DB layer
        CreatedAt:   row.CreatedAt,
        UpdatedAt:   row.UpdatedAt,
    })

    return order, nil
}
```

### 3. UpdateMut — return mutation, never apply

The repo reads the aggregate's tracked changes and builds a DB mutation:

```go
func (r *OrderRepo) UpdateMut(order *domain.Order) *spanner.Mutation {
    updates := m_order.UpdateFields{}

    if order.Changes.Dirty(domain.FieldStatus) {
        updates[m_order.Status] = string(order.Status())
    }
    if order.Changes.Dirty(domain.FieldUpdatedAt) {
        updates[m_order.UpdatedAt] = order.UpdatedAt()
    }

    if len(updates) == 0 {
        return nil  // No changes = no mutation
    }

    return r.model.UpdateMut(order.ID().String(), updates)  // RETURN, never apply
}
```

### 4. CreateMut — for new aggregates

```go
func (r *OrderRepo) CreateMut(order *domain.Order) *spanner.Mutation {
    return r.model.InsertMut(m_order.Row{
        ID:          order.ID().String(),
        CustomerID:  order.CustomerID().String(),
        Status:      string(order.Status()),
        TotalAmount: order.TotalAmount(),
        CreatedAt:   order.CreatedAt(),
        UpdatedAt:   order.UpdatedAt(),
    })
}
```

## Key Rules

### Repos MUST:
- Return domain aggregates from `Retrieve()` (not DB rows)
- Perform all unmarshalling inside the repo (DB model → domain)
- Use `Reconstitute` constructor (no validation, no events)
- Return mutations from `UpdateMut()`/`CreateMut()` — never apply them
- Return `nil` when there are no changes
- Have compile-time interface check: `var _ contracts.XRepo = (*XRepo)(nil)`

### Repos MUST NOT:
- Apply mutations to the database (that's the committer's job)
- Contain any business logic or validation
- Make business decisions (if/else based on domain state)
- Import other repos or usecases
- Return DB model types to callers

## Checklist

- [ ] `var _ contracts.XRepo = (*XRepo)(nil)` compile-time check
- [ ] `Retrieve()` returns domain aggregate (not DB model)
- [ ] Uses `Reconstitute` constructor for unmarshalling
- [ ] `UpdateMut()` reads `Changes.Dirty()` and returns mutation
- [ ] `CreateMut()` maps all fields and returns mutation
- [ ] Returns `nil` when no changes detected
- [ ] No `client.Apply()` — repo never applies mutations
- [ ] No business logic whatsoever
- [ ] Errors wrapped with context
