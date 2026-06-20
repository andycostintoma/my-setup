// internal/app/<AREA>/repo/<entity>_repo.go
```go
package repo

import (
    "context"
    "fmt"

    "internal/app/<AREA>/contracts"
    "internal/app/<AREA>/domain"
)

// DBRow is a persistence projection returned by the DB client.
type DBRow struct {
    ID     string
    Data   string
    Status string
}

// DBClient abstracts the underlying storage operations.
type DBClient interface {
    Get<ENTITY>(ctx context.Context, id string) (DBRow, error)
    ApplyMutations(ctx context.Context, muts []any) error
}

// <Entity>Repo implements contracts.<Entity>Repo by mapping DB ↔ domain.
type <Entity>Repo struct {
    db DBClient
    // log, tracer, metrics, etc.
}

func New<Entity>Repo(db DBClient) *<Entity>Repo { return &<Entity>Repo{db: db} }

var _ contracts.<Entity>Repo = (*<Entity>Repo)(nil)

// Retrieve loads the entity and returns a domain aggregate (repo performs unmarshalling).
func (r *<Entity>Repo) Retrieve(ctx context.Context, id string) (*domain.<ENTITY>, error) {
    row, err := r.db.Get<ENTITY>(ctx, id)
    if err != nil {
        return nil, fmt.Errorf("get <entity> %q: %w", id, err)
    }
    agg := mapRowToAggregate(row)
    return agg, nil
}

// UpdateMut builds and RETURNS a persistence mutation for changed fields.
// CRITICAL: This method READS the aggregate's tracked changes and CREATES a mutation.
// It does NOT apply the mutation - that's the committer's job.
// The usecase calls this method to GET the mutation, then adds it to a CommitPlan.
// The service applies the plan via committer.
// Return a repo‑specific mutation type (DB‑agnostic here, e.g., *spanner.Mutation for Spanner).
func (r *<Entity>Repo) UpdateMut(e *domain.<ENTITY>) any {
    // Example: Read tracked changes and create mutation
    // if e.Changes.Dirty(domain.FieldStatus) { updates[...] = ... }
    // return r.model.UpdateMut(id, updates)
    return toMutationFromChanges(e)
}

// mapRowToAggregate maps a DB row to a domain aggregate using constructors.
func mapRowToAggregate(row DBRow) *domain.<ENTITY> {
    // Use Reconstitute to rebuild domain state from persisted data.
    return domain.Reconstitute<ENTITY>(row.ID, row.Data, domain.<ENTITY>Status(row.Status))
}

// toMutations converts the aggregate state into persistence mutations.
// Example: translate tracked changes into DB layer mutations.
// Adjust these types to your DB client (Spanner mutations, SQL statements, etc.).
func toMutationFromChanges(e *domain.<ENTITY>) any {
    // Example: if e.Changes.Dirty(domain.FieldStatus) { return model.UpdateMut(...) }
    return nil
}

func eventToOutboxMut(ev any) any { return nil }

// --- Multi-table variant (same DB) ---
// If your repository commonly updates several tables at once (e.g., primary + outbox),
// expose a plural builder that returns all mutations to be applied together.
// Adjust your contract accordingly (e.g., add UpdateMuts to the interface).
//
// func (r *<Entity>Repo) UpdateMuts(e *domain.<ENTITY>) []any {
//     var muts []any
//     updates := m_<entity>.UpdateFields{}
//     if e.Changes.Dirty(domain.FieldStatus) { updates[m_<entity>.Status] = string(e.GetStatus()) }
//     if len(updates) > 0 { muts = append(muts, r.models.<Entity>.UpdateMut(companyID, e.ID(), updates)) }
//     // for _, ev := range e.Events.Drain() { muts = append(muts, r.outbox.CreateMut(fromEvent(ev))) }
//     return muts
// }
```
