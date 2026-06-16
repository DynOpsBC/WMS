//go:build windows

package printer

import (
	"fmt"
	"net"
	"strings"
	"time"

	"github.com/dynops/bcwms-print-agent/config"
)

// windowsBackend uses raw TCP socket 9100 by default.
// For full Win32 Spooler integration use the kardianos/service + alexbrainman/printer
// libraries (see README.md). This minimal v1 covers the most common warehouse
// scenario: a network ZPL printer reachable via raw TCP.
type windowsBackend struct {
	handle string
	host   string
	port   int
}

func newBackend(cfg *config.Config) Backend {
	return &windowsBackend{
		handle: cfg.PrinterHandle,
		host:   firstNonEmpty(cfg.PrinterHandle, "127.0.0.1"),
		port:   9100,
	}
}

func (b *windowsBackend) Print(format string, payload []byte, copies int) error {
	if b.host == "" {
		return fmt.Errorf("printerHandle (host[:port]) not set")
	}
	host, port := splitHostPort(b.host)
	if port == 0 {
		port = b.port
	}
	if copies <= 0 {
		copies = 1
	}
	for i := 0; i < copies; i++ {
		conn, err := net.DialTimeout("tcp", fmt.Sprintf("%s:%d", host, port), 5*time.Second)
		if err != nil {
			return fmt.Errorf("dial %s:%d: %w", host, port, err)
		}
		if _, err := conn.Write(payload); err != nil {
			conn.Close()
			return err
		}
		conn.Close()
	}
	return nil
}

func splitHostPort(handle string) (string, int) {
	parts := strings.SplitN(handle, ":", 2)
	if len(parts) == 2 {
		var port int
		fmt.Sscanf(parts[1], "%d", &port)
		return parts[0], port
	}
	return handle, 0
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}
