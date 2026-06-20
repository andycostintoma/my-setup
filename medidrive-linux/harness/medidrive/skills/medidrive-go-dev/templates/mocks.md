# Shared Mocks for Usecases

To avoid redefining mocks in every test file, create a shared `mocks` package per area and reuse it across tests.

Recommended location:

- `internal/app/<AREA>/mocks/` — contains testify-based mocks for contracts used by usecases within that area.

Example:

```go
// internal/app/<AREA>/mocks/mocks.go
package mocks

import (
    "context"
    "time"

    "internal/app/<AREA>/contracts"
    "internal/app/<AREA>/domain"
    "github.com/stretchr/testify/mock"
)

type <Entity>Repo struct{ mock.Mock }
func (m *<Entity>Repo) Retrieve(ctx context.Context, id string) (*domain.<ENTITY>, error) {
    args := m.Called(ctx, id)
    if v := args.Get(0); v != nil { return v.(*domain.<ENTITY>), args.Error(1) }
    return nil, args.Error(1)
}
func (m *<Entity>Repo) UpdateMut(e *domain.<ENTITY>) any { return m.Called(e).Get(0) }

type ExternalSender struct{ mock.Mock }
func (m *ExternalSender) Send(ctx context.Context, dest, payload string) (string, error) { a := m.Called(ctx, dest, payload); return a.String(0), a.Error(1) }

type Clock struct{ mock.Mock }
func (m *Clock) Now() time.Time { return m.Called().Get(0).(time.Time) }

type Logger struct{ mock.Mock }
func (m *Logger) Infof(f string, args ...any)  { m.Called(f, args) }
func (m *Logger) Warnf(f string, args ...any)  { m.Called(f, args) }
func (m *Logger) Errorf(f string, args ...any) { m.Called(f, args) }

// compile-time checks
var _ contracts.<Entity>Repo = (*<Entity>Repo)(nil)
var _ contracts.ExternalSender = (*ExternalSender)(nil)
var _ contracts.Clock = (*Clock)(nil)
var _ contracts.Logger = (*Logger)(nil)
```

Then import these mocks into your usecase tests:

```go
import mocks "internal/app/<AREA>/mocks"

repo := new(mocks.<Entity>Repo)
sender := new(mocks.ExternalSender)
clock := new(mocks.Clock)
log := new(mocks.Logger)
```

Notes:
- Keep mocks in a test-only context. Consider using `//go:build test` build tags if you prefer to avoid including mocks in regular builds.
- Do not put mocks into production adapter packages; keep adapters for real implementations. Shared mocks belong in a dedicated `mocks` directory close to the contracts.
