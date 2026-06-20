// internal/app/<AREA>/usecases/<action>/errors.go
```go
package <action>

import "errors"

var (
    ErrRetrieveFailed     = errors.New("retrieve failed")
    Err<ENTITY>NotFound   = errors.New("<entity> not found")
    ErrInvalidTransition  = errors.New("invalid status transition")
    ErrExternalSendFailed = errors.New("external send failed")
    ErrStatusUpdateFailed = errors.New("status update failed")
    ErrPlanApplyFailed    = errors.New("plan apply failed")
)
```
