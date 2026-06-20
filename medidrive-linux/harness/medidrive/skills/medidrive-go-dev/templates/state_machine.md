// internal/app/<AREA>/domain/session_state.go
```go
package domain

import "time"

type SessionStatus string

const (
    SessionOpen    SessionStatus = "open"
    SessionClosed  SessionStatus = "closed"
    SessionExpired SessionStatus = "expired"
)

type Session struct {
    Status    SessionStatus
    ExpiresAt time.Time
}

func (s *Session) IsActive(now time.Time) bool {
    if s.Status == SessionClosed {
        return false
    }
    if now.After(s.ExpiresAt) {
        return false
    }
    return s.Status == SessionOpen
}

```
