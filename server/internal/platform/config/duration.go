package config

import (
	"fmt"
	"time"

	"gopkg.in/yaml.v3"
)

func (d *Duration) UnmarshalYAML(value *yaml.Node) error {
	parsed, err := time.ParseDuration(value.Value)
	if err != nil {
		return fmt.Errorf("invalid duration %q: %w", value.Value, err)
	}
	*d = Duration(parsed)
	return nil
}

type Duration time.Duration

func (d Duration) Value() time.Duration { return time.Duration(d) }
