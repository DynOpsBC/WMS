//go:build darwin || linux

package printer

import (
	"bytes"
	"fmt"
	"os/exec"
	"strconv"

	"github.com/dynops/bcwms-print-agent/config"
)

type unixBackend struct {
	handle string
}

func newBackend(cfg *config.Config) Backend {
	return &unixBackend{handle: cfg.PrinterHandle}
}

func (b *unixBackend) Print(format string, payload []byte, copies int) error {
	if b.handle == "" {
		return fmt.Errorf("printerHandle not set in config")
	}
	if copies <= 0 {
		copies = 1
	}
	args := []string{"-d", b.handle, "-n", strconv.Itoa(copies)}
	if format == "ZPL" || format == "RAW" || format == "ESCPOS" {
		args = append(args, "-o", "raw")
	}
	cmd := exec.Command("lp", args...)
	cmd.Stdin = bytes.NewReader(payload)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("lp failed: %v output=%s", err, string(out))
	}
	return nil
}
