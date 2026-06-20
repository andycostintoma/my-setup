# Cron Job Template

Copy-paste template for creating new scheduled background jobs.

## Quick Start

1. Copy the facade and service templates below
2. Replace `{domain}`, `{job_name}`, and placeholders
3. Register job in `commands.go`
4. Wire up in scheduler

## File Structure

```
internal/app/{domain}/
├── jobs/
│   ├── jobs_options/
│   │   └── options.go           # Shared options
│   ├── {job_name}/
│   │   ├── facade.go            # Copy template below
│   │   └── service.go           # Copy template below
│   └── commands.go              # Register job here
```

---

## Template: Facade

**File**: `internal/app/{domain}/jobs/{job_name}/facade.go`

```go
package {job_name}

import (
    "context"
    "time"

    "internal/app/{domain}/jobs/jobs_options"
    "internal/pkg/log"
    "github.com/go-co-op/gocron"
)

const (
    processName = "{job_name}"
    Interval    = 5 * time.Minute  // TODO: Set appropriate interval
)

type Facade struct {
    o *jobs_options.Options
}

func New(o *jobs_options.Options) *Facade {
    return &Facade{o: o}
}

// JobName returns the unique identifier for this job
func (f *Facade) JobName() string {
    return processName
}

// ScheduleInterval returns how often this job runs
func (f *Facade) ScheduleInterval() time.Duration {
    return Interval
}

// Lock returns the distributed lock for this job
func (f *Facade) Lock() gocron.Locker {
    return f.o.PKG.CronLocker
}

// Handle is called by the scheduler to execute the job
func (f *Facade) Handle() error {
    // ProcessBlocking ensures only one instance runs at a time
    f.o.PKG.Cron.ProcessBlocking(processName, func(ctx context.Context) error {
        // Set timeout based on interval
        ctx, cancel := context.WithTimeout(ctx, Interval)
        defer cancel()

        // Create service with logging
        serv := &service{
            f:   f,
            log: f.o.PKG.Log.SetLevel(log.DebugLevel),
        }

        // Process for each active company
        if err := f.o.PKG.Cron.ForEachActiveCompany(ctx, serv.processCompany); err != nil {
            return err
        }

        return nil
    }, Interval*3) // Grace period: 3x interval

    return nil
}

// TestRun allows manual testing of the job
func (f *Facade) TestRun(ctx context.Context, companyID string) error {
    serv := &service{
        f:   f,
        log: f.o.PKG.Log.SetLevel(log.DebugLevel),
    }
    return serv.processCompany(ctx, companyID)
}
```

---

## Template: Service

**File**: `internal/app/{domain}/jobs/{job_name}/service.go`

```go
package {job_name}

import (
    "context"

    "internal/app/{domain}/usecases/{usecase_name}"
    "internal/pkg/log"
)

type service struct {
    f   *Facade
    log *log.Logger
}

// processCompany handles job logic for a single company
func (s *service) processCompany(ctx context.Context, companyID string) error {
    s.log.Info("Starting {job_name}", log.H{
        "company_id": companyID,
    })

    // ✅ Call usecase directly
    if err := s.f.o.App.{Domain}.{UsecaseName}.Execute(ctx, &{usecase_name}.Request{
        CompanyID: companyID,
        // TODO: Add other request fields
    }); err != nil {
        s.log.Error("Failed to execute {job_name}", log.H{
            "company_id": companyID,
            "error":      err,
        })
        return err
    }

    s.log.Info("Successfully completed {job_name}", log.H{
        "company_id": companyID,
    })

    return nil
}
```

---

## Template: Job Registration

**File**: `internal/app/{domain}/commands.go`

```go
package {domain}

import (
    "internal/app/{domain}/jobs/jobs_options"
    "internal/app/{domain}/jobs/{job_name}"
    "github.com/Vektor-AI/cron"
)

func (f *Facade) GetCommands(o *jobs_options.Options) []cron.Command {
    return []cron.Command{
        {job_name}.New(o),
        // ... other jobs
    }
}
```

---

## Template: Options (First Time Only)

**File**: `internal/app/{domain}/jobs/jobs_options/options.go`

Only create this if it doesn't exist yet:

```go
package jobs_options

import (
    "internal/app"
    "internal/pkg"
)

type Options struct {
    App *app.Facade  // Application usecases
    PKG *pkg.Facade  // Infrastructure (Cron, Log, etc.)
}
```

---

## Complete Example: Alert Sync Job

### facade.go

```go
package alert_sync

import (
    "context"
    "time"

    "internal/app/detention/jobs/jobs_options"
    "internal/pkg/log"
    "github.com/go-co-op/gocron"
)

const (
    processName = "alert_sync"
    Interval    = 5 * time.Minute
)

type Facade struct {
    o *jobs_options.Options
}

func New(o *jobs_options.Options) *Facade {
    return &Facade{o: o}
}

func (f *Facade) JobName() string {
    return processName
}

func (f *Facade) ScheduleInterval() time.Duration {
    return Interval
}

func (f *Facade) Lock() gocron.Locker {
    return f.o.PKG.CronLocker
}

func (f *Facade) Handle() error {
    f.o.PKG.Cron.ProcessBlocking(processName, func(ctx context.Context) error {
        ctx, cancel := context.WithTimeout(ctx, Interval)
        defer cancel()

        serv := &service{
            f:   f,
            log: f.o.PKG.Log.SetLevel(log.DebugLevel),
        }

        if err := f.o.PKG.Cron.ForEachActiveCompany(ctx, serv.processCompany); err != nil {
            return err
        }

        return nil
    }, Interval*3)

    return nil
}

func (f *Facade) TestRun(ctx context.Context, companyID string) error {
    serv := &service{
        f:   f,
        log: f.o.PKG.Log.SetLevel(log.DebugLevel),
    }
    return serv.processCompany(ctx, companyID)
}
```

### service.go

```go
package alert_sync

import (
    "context"

    "internal/app/detention/usecases/sync_alert_events"
    "internal/pkg/log"
)

type service struct {
    f   *Facade
    log *log.Logger
}

func (s *service) processCompany(ctx context.Context, companyID string) error {
    s.log.Info("Starting alert sync", log.H{
        "company_id": companyID,
    })

    // ✅ Call usecase directly
    if err := s.f.o.App.Detention.SyncAlertEvents.Execute(ctx, &sync_alert_events.Request{
        CompanyID: companyID,
    }); err != nil {
        s.log.Error("Failed to sync alert events", log.H{
            "company_id": companyID,
            "error":      err,
        })
        return err
    }

    s.log.Info("Successfully synced alert events", log.H{
        "company_id": companyID,
    })

    return nil
}
```

---

## Checklist

When creating a new cron job:

- [ ] Create `facade.go` with job interface implementation
- [ ] Create `service.go` with usecase call
- [ ] Set appropriate `Interval` (5min, 1hr, 24hr, etc.)
- [ ] Set grace period to `Interval * 3`
- [ ] Implement `TestRun()` for manual testing
- [ ] Register job in `commands.go`
- [ ] Add structured logging with `log.H{}`
- [ ] Use `ForEachActiveCompany` for multi-tenant processing
- [ ] Return errors to mark job as failed
- [ ] Test with `TestRun()` first
- [ ] Monitor logs after deployment

---

## Common Intervals

| Job Type | Recommended Interval |
|----------|---------------------|
| External API sync | 5-15 minutes |
| Cleanup/maintenance | 1-24 hours |
| Event publishing | 1-5 minutes |
| Report generation | 1-24 hours |
| Health checks | 1-10 minutes |

---

## Critical Rules

### ✅ DO:

```go
// ✅ Call usecase directly
s.f.o.App.Detention.SyncAlerts.Execute(ctx, req)

// ✅ Set timeout
ctx, cancel := context.WithTimeout(ctx, Interval)
defer cancel()

// ✅ Use structured logging
s.log.Info("Job completed", log.H{"company_id": companyID})

// ✅ Grace period = 3x interval
f.o.PKG.Cron.ProcessBlocking(processName, fn, Interval*3)
```

### ❌ DON'T:

```go
// ❌ Don't call through intermediate layers
s.f.o.Syncers.SyncAlerts(ctx, companyID)

// ❌ Don't put business logic in facade
func (f *Facade) Handle() error {
    // Business logic should be in service.go
}

// ❌ Don't skip timeout
ctx := context.Background() // Missing timeout!

// ❌ Don't hardcode grace period
f.o.PKG.Cron.ProcessBlocking(processName, fn, 15*time.Minute)
```

---

## See Also

- [Cron Jobs Documentation](../implementation/cron-jobs.md) - Complete guide
- [Usecase Template](usecase.md) - Create usecases for jobs to call
- [E2E Testing](../testing/e2e-testing.md) - How to test usecases

---

[← Back to Templates](README.md) | [← Back to Main](../README.md)