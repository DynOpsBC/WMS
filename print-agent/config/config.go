package config

import (
	"encoding/json"
	"fmt"
	"os"
)

// Config is loaded from ~/.bcwms-print-agent/config.json (or path passed via --config flag).
type Config struct {
	RelayURL        string `json:"relayUrl"`
	TenantID        string `json:"tenantId"`
	PrinterID       string `json:"printerId"`
	Secret          string `json:"secret"`
	PrinterHandle   string `json:"printerHandle"`
	Format          string `json:"format"`
	PollIntervalSec int    `json:"pollIntervalSec"`
	AgentID         string `json:"agentId"`
}

func Load(path string) (*Config, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", path, err)
	}
	cfg := &Config{}
	if err := json.Unmarshal(raw, cfg); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	if cfg.RelayURL == "" || cfg.PrinterID == "" || cfg.Secret == "" {
		return nil, fmt.Errorf("config %s: relayUrl, printerId and secret are required", path)
	}
	if cfg.PollIntervalSec <= 0 {
		cfg.PollIntervalSec = 5
	}
	if cfg.TenantID == "" {
		cfg.TenantID = "default"
	}
	if cfg.Format == "" {
		cfg.Format = "ZPL"
	}
	if cfg.AgentID == "" {
		hostname, _ := os.Hostname()
		cfg.AgentID = "agent-" + hostname
	}
	return cfg, nil
}
