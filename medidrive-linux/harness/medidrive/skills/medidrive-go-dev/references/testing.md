# Writing Tests

## Domain Tests — Pure, No Dependencies

Domain tests need zero mocks, zero DB, zero infrastructure:

```go
func TestOrder_Activate(t *testing.T) {
    tests := []struct {
        name          string
        initialStatus domain.OrderStatus
        wantErr       error
    }{
        {
            name:          "success from confirmed",
            initialStatus: domain.StatusConfirmed,
            wantErr:       nil,
        },
        {
            name:          "fails from draft",
            initialStatus: domain.StatusDraft,
            wantErr:       domain.ErrInvalidTransition,
        },
        {
            name:          "fails from already active",
            initialStatus: domain.StatusActive,
            wantErr:       domain.ErrInvalidTransition,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            order := domain.ReconstituteOrder(domain.OrderProps{
                ID:     "order-1",
                Status: tt.initialStatus,
            })
            err := order.Activate(time.Now())
            if tt.wantErr != nil {
                assert.True(t, errors.Is(err, tt.wantErr))
            } else {
                assert.NoError(t, err)
                assert.Equal(t, domain.StatusActive, order.Status())
            }
        })
    }
}
```

## Usecase Tests — Mock Dependencies

```go
package activate_order

import (
    "context"
    "testing"
    "time"

    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/mock"
)

// Define mocks for each contract
type MockRepo struct{ mock.Mock }
func (m *MockRepo) Retrieve(ctx context.Context, id string) (*domain.Order, error) {
    args := m.Called(ctx, id)
    if v := args.Get(0); v != nil { return v.(*domain.Order), args.Error(1) }
    return nil, args.Error(1)
}
func (m *MockRepo) UpdateMut(e *domain.Order) any { return m.Called(e).Get(0) }

type MockClock struct{ mock.Mock }
func (m *MockClock) Now() time.Time { return m.Called().Get(0).(time.Time) }

type MockLogger struct{ mock.Mock }
func (m *MockLogger) Infof(f string, args ...any)  {}
func (m *MockLogger) Warnf(f string, args ...any)  {}
func (m *MockLogger) Errorf(f string, args ...any) {}

// Setup helper
func setup(t *testing.T) (*Interactor, *MockRepo, *MockClock) {
    repo := new(MockRepo)
    clock := new(MockClock)
    committer := new(MockCommitter)
    logger := new(MockLogger)

    it := New(Options{
        Repo:      repo,
        Committer: committer,
        Clock:     clock,
        Log:       logger,
    })

    t.Cleanup(func() { repo.AssertExpectations(t) })
    return it, repo, clock
}

func TestExecute_Success(t *testing.T) {
    it, repo, clock := setup(t)

    now := time.Date(2026, 1, 15, 10, 0, 0, 0, time.UTC)
    order := domain.ReconstituteOrder(domain.OrderProps{
        ID:     "order-1",
        Status: domain.StatusConfirmed,
    })

    repo.On("Retrieve", mock.Anything, "order-1").Return(order, nil)
    clock.On("Now").Return(now)
    repo.On("UpdateMut", mock.MatchedBy(func(o *domain.Order) bool {
        return o.Status() == domain.StatusActive
    })).Return(struct{}{})

    err := it.Execute(context.Background(), &Request{OrderID: "order-1"})
    assert.NoError(t, err)
}

func TestExecute_NotFound(t *testing.T) {
    it, repo, _ := setup(t)

    repo.On("Retrieve", mock.Anything, "missing").Return(nil, errors.New("not found"))

    err := it.Execute(context.Background(), &Request{OrderID: "missing"})
    assert.Error(t, err)
}
```

## Rules

- **Table-driven tests** for multiple scenarios
- **Domain tests** must be pure — no mocks, no DB
- **Usecase tests** mock contracts, verify interactions
- **Money in tests** — always `*big.Rat`, never floats
- **Cover edge cases**: empty inputs, nil pointers, invalid transitions, already-in-state
- **Test file** lives next to the code: `interactor_test.go`
- **Use `t.Cleanup`** for assertion expectations
