package health

import (
	"context"
	"sync"
	"time"
)

type Check func(context.Context) error

type Checker struct {
	mu     sync.RWMutex
	checks map[string]Check
}

type Status struct {
	OK         bool              `json:"ok"`
	Components map[string]string `json:"components"`
	CheckedAt  time.Time         `json:"checked_at"`
}

func New() *Checker { return &Checker{checks: make(map[string]Check)} }

func (c *Checker) Register(name string, check Check) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.checks[name] = check
}

func (c *Checker) Run(ctx context.Context) Status {
	c.mu.RLock()
	checks := make(map[string]Check, len(c.checks))
	for name, check := range c.checks {
		checks[name] = check
	}
	c.mu.RUnlock()
	status := Status{OK: true, Components: make(map[string]string), CheckedAt: time.Now().UTC()}
	for name, check := range checks {
		checkCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
		err := check(checkCtx)
		cancel()
		if err != nil {
			status.OK = false
			status.Components[name] = err.Error()
		} else {
			status.Components[name] = "ok"
		}
	}
	return status
}
