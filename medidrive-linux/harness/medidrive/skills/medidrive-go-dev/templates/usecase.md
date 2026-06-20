// internal/app/<AREA>/usecases/<action>/<action>.go
```go
package <action>

import (
    "context"
    "errors"
    "fmt"
    "time"

    "internal/app/<AREA>/contracts"
    "internal/app/<AREA>/domain"
    "github.com/Vektor-AI/commitplan"
)

// Optional: define Request/Reply and a Handler interface as the usecase contract.
// type Request struct { ID string }
// type Reply struct { OK bool }
// type Handler interface { Execute(ctx context.Context, req *Request) (*Reply, error) }

type Interactor struct {
    repo      contracts.<Entity>Repo
    sender    contracts.ExternalSender
    committer commitplan.Committer  // ✅ Usecase has committer
    clock     contracts.Clock
    log       contracts.Logger
}

func New(r contracts.<Entity>Repo, s contracts.ExternalSender, comm commitplan.Committer, c contracts.Clock, l contracts.Logger) *Interactor {
    return &Interactor{repo: r, sender: s, committer: comm, clock: c, log: l}
}

// Compile-time check that Interactor satisfies the usecase contract when defined.
// var _ Handler = (*Interactor)(nil)

func (it *Interactor) Execute(ctx context.Context, id string) error {
    e, err := retrieve<ENTITY>(ctx, it.repo, id)
    if err != nil { return err }

    if err := validateTransition(e, domain.StatusActive); err != nil { return err }

    now := it.clock.Now()
    msgID, err := externalSend(ctx, it.sender, "dest", e.Data())
    if err != nil {
        it.log.Errorf("external send failed for <entity> %s: %v", e.ID(), err)
        if err2 := setPending(ctx, e, now); err2 != nil {
            it.log.Errorf("failed to set <entity> %s to pending after send failure: %v", e.ID(), err2)
        }
        return fmt.Errorf("%w: %v", ErrExternalSendFailed, err)
    }
    if sErr := e.Complete(now); sErr != nil {
        it.log.Errorf("failed to apply status done for <entity> %s: %v", e.ID(), sErr)
        return sErr
    }

    // CRITICAL: Build plan by GETTING mutations FROM repo
    // Usecase does NOT create mutations - it calls repo.UpdateMut to GET them
    // The repo reads the aggregate's tracked changes and returns the mutation
    p := commitplan.NewPlan()
    if mut := it.repo.UpdateMut(e); mut != nil {
        // p.Add<Store>(mut)
    }
    _ = msgID

    // ✅ CRITICAL: Usecase APPLIES plan via committer (NOT handler!)
    if err := it.committer.Apply(ctx, p); err != nil {
        return fmt.Errorf("apply plan: %w", err)
    }

    // Return nil (success) - no wasteful allocations
    return nil
}

// retrieve<ENTITY> states it needs a repo and an id explicitly.
func retrieve<ENTITY>(ctx context.Context, r contracts.<Entity>Repo, id string) (*domain.<ENTITY>, error) {
    e, err := r.Retrieve(ctx, id)
    if err != nil {
        if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) { return nil, err }
        return nil, fmt.Errorf("%w: %v", ErrRetrieveFailed, err)
    }
    return e, nil
}

func validateTransition(e *domain.<ENTITY>, to domain.<ENTITY>Status) error {
    if !e.CanTransition(to) { return ErrInvalidTransition }
    return nil
}

func externalSend(ctx context.Context, s contracts.ExternalSender, dest, payload string) (string, error) {
    return s.Send(ctx, dest, payload)
}

func setPending(ctx context.Context, e *domain.<ENTITY>, now time.Time) error { e.ToPending(now); return nil }
```

// Variant: usecase composes multiple aggregate mutations into one plan and applies it
```go
package <action>

import (
    "context"
    "internal/app/<AREA>/contracts"
    "internal/app/<AREA>/domain"
    "github.com/Vektor-AI/commitplan"
)

type Multi struct {
    repo      contracts.<Entity>Repo
    committer commitplan.Committer  // ✅ Usecase has committer
    clock     contracts.Clock
}

func NewMulti(r contracts.<Entity>Repo, comm commitplan.Committer, c contracts.Clock) *Multi {
    return &Multi{repo: r, committer: comm, clock: c}
}

func (it *Multi) Execute(ctx context.Context, id string) error {
    e, err := it.repo.Retrieve(ctx, id)
    if err != nil { return err }
    now := it.clock.Now()
    if err := e.SetStatus(domain.StatusActive, now); err != nil { return err }
    p := commitplan.NewPlan()
    if mut := it.repo.UpdateMut(e); mut != nil { /* p.Add<Store>(mut) */ }

    // ✅ Usecase applies plan internally
    if err := it.committer.Apply(ctx, p); err != nil {
        return err
    }

    return nil  // Success
}
```

---

## Constructor Patterns (Options vs Functional Options)

When a constructor needs more than 2 parameters, avoid long parameter lists. Prefer one of the following patterns:

1) Options struct (all fields required)

```go
// internal/app/<AREA>/usecases/<action>/interactor.go
package <action>

import (
    "internal/app/<AREA>/contracts"
)

type Options struct {
    Repo   contracts.<Entity>Repo
    Sender contracts.ExternalSender
    Clock  contracts.Clock
    Log    contracts.Logger
}

// New constructs Interactor with explicit required dependencies.
func New(opts Options) *Interactor {
    return &Interactor{
        repo:   opts.Repo,
        sender: opts.Sender,
        clock:  opts.Clock,
        log:    opts.Log,
    }
}
```

2) Functional options (some fields optional)

```go
// Only Repo is required; others are optional via With*.
type Option func(*Interactor)

func WithSender(s contracts.ExternalSender) Option { return func(i *Interactor) { i.sender = s } }
func WithClock(c contracts.Clock) Option           { return func(i *Interactor) { i.clock = c } }
func WithLogger(l contracts.Logger) Option         { return func(i *Interactor) { i.log = l } }

func NewWithOptions(repo contracts.<Entity>Repo, opts ...Option) *Interactor {
    it := &Interactor{repo: repo}
    for _, opt := range opts { opt(it) }
    return it
}
```

Notes
- Keep constructors explicit and readable; avoid more than 2 positional parameters.
- Use Options struct when everything is required; use functional options when you have a small set of optional collaborators.
