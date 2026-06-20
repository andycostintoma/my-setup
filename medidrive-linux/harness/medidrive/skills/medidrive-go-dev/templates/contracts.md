// internal/app/<AREA>/contracts/contracts.go
```go
package contracts

import (
    "context"
    "time"

    "internal/app/<AREA>/domain"
)

// <Entity>Repo returns aggregates and builds mutation builders (no apply in repo).
type <Entity>Repo interface {
    Retrieve(ctx context.Context, id string) (*domain.<ENTITY>, error)
    // Return a repo‑specific mutation type (e.g., *spanner.Mutation for Spanner).
    UpdateMut(e *domain.<ENTITY>) any
}

type ExternalSender interface {
    Send(ctx context.Context, dest, payload string) (string, error)
}

type Clock interface { Now() time.Time }

// Logger is a minimal logger interface for usecases.
type Logger interface {
    Infof(format string, args ...any)
    Warnf(format string, args ...any)
    Errorf(format string, args ...any)
}

// Compile-time checks should live in implementing packages, e.g.:
// var _ contracts.<Entity>Repo = (*repo.<Entity>Repo)(nil)
```

// Optional: if your repo builds multiple mutations across several tables in the same DB,
// extend the interface with a plural builder.
```go
type <Entity>Repo interface {
    Retrieve(ctx context.Context, id string) (*domain.<ENTITY>, error)
    UpdateMut(e *domain.<ENTITY>) any            // simple case
    // UpdateMuts(e *domain.<ENTITY>) []any      // multi-table variant (optional)
}
```

// internal/app/<AREA>/usecases/<action>/types.go (usecase contracts)
```go
package <action>

// Request and Reply define the usecase boundary.
type Request struct { ID string }
type Reply struct { OK bool }

// Handler is the usecase contract; Interactor implements it.
type Handler interface {
    Execute(ctx context.Context, req *Request) (*Reply, error)
}

// In the implementation file:
// var _ Handler = (*Interactor)(nil)
```
