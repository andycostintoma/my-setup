// internal/app/<AREA>/usecases/<action>/<action>_test.go
```go
package <action>

import (
    "context"
    "errors"
    "testing"
    "time"

    "internal/app/<AREA>/contracts"
    "internal/app/<AREA>/domain"
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/mock"
)

// Mocks
type MockRepo struct{ mock.Mock }
func (m *MockRepo) Retrieve(ctx context.Context, id string) (*domain.<ENTITY>, error) {
    args := m.Called(ctx, id)
    if v := args.Get(0); v != nil { return v.(*domain.<ENTITY>), args.Error(1) }
    return nil, args.Error(1)
}
func (m *MockRepo) UpdateMut(e *domain.<ENTITY>) any { return m.Called(e).Get(0) }

type MockSender struct{ mock.Mock }
func (m *MockSender) Send(ctx context.Context, dest, payload string) (string, error) {
    args := m.Called(ctx, dest, payload); return args.String(0), args.Error(1)
}

type MockClock struct{ mock.Mock }
func (m *MockClock) Now() time.Time { return m.Called().Get(0).(time.Time) }

type MockLogger struct{ mock.Mock }
func (m *MockLogger) Infof(f string, args ...any)  { m.Called(f, args) }
func (m *MockLogger) Warnf(f string, args ...any)  { m.Called(f, args) }
func (m *MockLogger) Errorf(f string, args ...any) { m.Called(f, args) }

func setup(t *testing.T) (*Interactor, *MockRepo, *MockSender, *MockClock, *MockLogger) {
    r := new(MockRepo); s := new(MockSender); c := new(MockClock); l := new(MockLogger)
    it := New(r, s, c, l)
    t.Cleanup(func() { r.AssertExpectations(t); s.AssertExpectations(t); c.AssertExpectations(t); l.AssertExpectations(t) })
    return it, r, s, c, l
}

func TestExecute_Success(t *testing.T) {
    it, r, s, c, _ := setup(t)
    id := "id-1"; now := time.Now().UTC(); msg := "msg-1"
    agg := domain.Reconstitute<ENTITY>(id, "data", domain.StatusPending)

    r.On("Retrieve", mock.Anything, id).Return(agg, nil)
    c.On("Now").Return(now)
    s.On("Send", mock.Anything, "dest", agg.Data()).Return(msg, nil)
    r.On("UpdateMut", mock.MatchedBy(func(e *domain.<ENTITY>) bool { return e.GetStatus() == domain.StatusDone })).Return(struct{}{})

    plan, err := it.Execute(context.Background(), id)
    assert.NoError(t, err)
    assert.NotNil(t, plan)
}

func TestExecute_SendFails(t *testing.T) {
    it, r, s, c, l := setup(t)
    id := "id-2"; now := time.Now().UTC(); sendErr := errors.New("network")
    agg := domain.Reconstitute<ENTITY>(id, "data", domain.StatusPending)

    r.On("Retrieve", mock.Anything, id).Return(agg, nil)
    c.On("Now").Return(now)
    s.On("Send", mock.Anything, "dest", agg.Data()).Return("", sendErr)
    l.On("Errorf", "external send failed for <entity> %s: %v", mock.Anything).Return()

    plan, err := it.Execute(context.Background(), id)
    assert.Error(t, err)
    assert.Nil(t, plan)
    assert.ErrorIs(t, err, ErrExternalSendFailed)
}
```
