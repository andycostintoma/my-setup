// internal/app/<AREA>/domain/<ENTITY>.go
```go
package domain

import (
    "errors"
    "fmt"
    "time"

    "github.com/Vektor-AI/domainkit/aggregate"
)

type <ENTITY>Status string

const (
    StatusPending <ENTITY>Status = "PENDING"
    StatusActive  <ENTITY>Status = "ACTIVE"
    StatusDone    <ENTITY>Status = "DONE"
)

var ErrInvalidTransition = errors.New("invalid transition")

// Strongly-typed field names for change tracking
type Field string
const (
    FieldStatus Field = "status"
    FieldData   Field = "data"
)

// Example domain events
type <ENTITY>Created struct {
    ID         string
    Data       string
    OccurredOn time.Time
}

type <ENTITY>Activated struct {
    ID         string
    OccurredOn time.Time
}

type <ENTITY>Completed struct {
    ID         string
    OccurredOn time.Time
}

type <ENTITY>Event interface {
    is<ENTITY>Event()
}

func (<ENTITY>Created) is<ENTITY>Event()   {}
func (<ENTITY>Activated) is<ENTITY>Event() {}
func (<ENTITY>Completed) is<ENTITY>Event() {}

type <ENTITY> struct {
    id     string
    data   string
    status <ENTITY>Status
    *aggregate.Base[Field, <ENTITY>Event]
}

// Create<ENTITY> constructs a new aggregate with initial invariants and events.
func Create<ENTITY>(id, data string, now time.Time) *<ENTITY> {
    e := &<ENTITY>{
        id:     id,
        data:   data,
        status: StatusPending,
        Base:   aggregate.NewBase[Field, <ENTITY>Event](),
    }
    e.Events.Add(<ENTITY>Created{ID: id, Data: data, OccurredOn: now})
    return e
}

// Reconstitute<ENTITY> reconstructs from persisted state (no business logic).
func Reconstitute<ENTITY>(id, data string, status <ENTITY>Status) *<ENTITY> {
    return &<ENTITY>{id: id, data: data, status: status, Base: aggregate.NewBase[Field, <ENTITY>Event]()}
}

// Accessors
func (e *<ENTITY>) ID() string                { return e.id }
func (e *<ENTITY>) Data() string              { return e.data }
func (e *<ENTITY>) GetStatus() <ENTITY>Status { return e.status }

// Business operations
func (e *<ENTITY>) Activate(now time.Time) error {
    if e.status != StatusPending { return fmt.Errorf("%w: cannot activate from %s", ErrInvalidTransition, e.status) }
    e.status = StatusActive
    e.Changes.Track(FieldStatus, e.status)
    e.Events.Add(<ENTITY>Activated{ID: e.id, OccurredOn: now})
    return nil
}

func (e *<ENTITY>) Complete(now time.Time) error {
    if e.status != StatusActive && e.status != StatusPending { return fmt.Errorf("%w: cannot complete from %s", ErrInvalidTransition, e.status) }
    e.status = StatusDone
    e.Changes.Track(FieldStatus, e.status)
    e.Events.Add(<ENTITY>Completed{ID: e.id, OccurredOn: now})
    return nil
}

// ToPending sets status to pending if not already; used as compensating action.
func (e *<ENTITY>) ToPending(now time.Time) {
    if e.status == StatusPending { return }
    e.status = StatusPending
    e.Changes.Track(FieldStatus, e.status)
}

// Optional: CanTransition is a pure query that checks if moving to `to` is allowed.
// Keep transition rules in domain for clarity and testability.
func (e *<ENTITY>) CanTransition(to <ENTITY>Status) bool {
    switch e.status {
    case StatusPending:
        return to == StatusActive || to == StatusDone
    case StatusActive:
        return to == StatusDone
    default:
        return false
    }
}
```
