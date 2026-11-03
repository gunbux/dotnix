package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// flagDef describes one --flag. Flags may come before or after positionals.
type flagDef struct {
	help    string
	isBool  bool
	choices []string
}

// argDef describes one positional. opt allows it to be missing; many takes
// the rest (at least one).
type argDef struct {
	name    string
	opt     bool
	many    bool
	choices []string
}

type command struct {
	path     string
	help     string
	args     []argDef
	flags    map[string]flagDef
	required []string
	run      func(*call)
	prefetch func(*call) // runs before the write lock
}

// call is one parsed command line.
type call struct {
	cmd     *command
	store   Store
	dbPath  string
	pos     map[string]string
	many    []string
	vals    map[string]string
	set     map[string]bool
	out     io.Writer
	errOut  io.Writer
	fetched any
}

func (c *call) flag(name string) string { return c.vals[name] }
func (c *call) has(name string) bool    { return c.set[name] }
func (c *call) printf(format string, a ...any) {
	fmt.Fprintf(c.out, format, a...)
}

var globalFlags = map[string]flagDef{
	"db":     {help: "log file (default $SPRINT_DB or ~/.local/state/sprint/sprint.db)"},
	"sprint": {help: "sprint slug (default $SPRINT, or the only open sprint)"},
}

func defaultDB() string {
	if v := os.Getenv("SPRINT_DB"); v != "" {
		return v
	}
	state := os.Getenv("XDG_STATE_HOME")
	if state == "" {
		home, _ := os.UserHomeDir()
		state = filepath.Join(home, ".local", "state")
	}
	return filepath.Join(state, "sprint", "sprint.db")
}

func looksNumeric(a string) bool {
	_, err := strconv.ParseFloat(a, 64)
	return err == nil
}

// parse splits args into flags and positionals for cmd.
func parse(cmd *command, args []string, c *call) {
	var pos []string
	for i := 0; i < len(args); i++ {
		a := args[i]
		if a == "--" {
			pos = append(pos, args[i+1:]...)
			break
		}
		if !strings.HasPrefix(a, "-") || a == "-" || looksNumeric(a) {
			pos = append(pos, a)
			continue
		}
		name, val, hasVal := strings.Cut(strings.TrimLeft(a, "-"), "=")
		def, ok := cmd.flags[name]
		if !ok {
			def, ok = globalFlags[name]
		}
		if !ok {
			fail("%s: unknown flag %s\n%s", cmd.path, a, usage(cmd))
		}
		if def.isBool {
			val = "true"
		} else if !hasVal {
			if i+1 >= len(args) {
				fail("%s: %s needs a value", cmd.path, a)
			}
			i++
			val = args[i]
		}
		if def.choices != nil && !contains(def.choices, val) {
			fail("%s: --%s must be one of %s", cmd.path, name, strings.Join(def.choices, ", "))
		}
		c.vals[name], c.set[name] = val, true
	}
	for _, r := range cmd.required {
		if !c.set[r] {
			fail("%s: --%s is required\n%s", cmd.path, r, usage(cmd))
		}
	}
	for _, d := range cmd.args {
		switch {
		case d.many:
			if len(pos) == 0 {
				fail("%s: missing %s\n%s", cmd.path, d.name, usage(cmd))
			}
			c.many, pos = pos, nil
		case len(pos) == 0:
			if !d.opt {
				fail("%s: missing %s\n%s", cmd.path, d.name, usage(cmd))
			}
		default:
			if d.choices != nil && !contains(d.choices, pos[0]) {
				fail("%s: %s must be one of %s", cmd.path, d.name, strings.Join(d.choices, ", "))
			}
			c.pos[d.name], pos = pos[0], pos[1:]
		}
	}
	if len(pos) > 0 {
		fail("%s: unexpected %q\n%s", cmd.path, pos[0], usage(cmd))
	}
}

func contains(list []string, v string) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}

func usage(cmd *command) string {
	var b strings.Builder
	fmt.Fprintf(&b, "usage: sprint %s", cmd.path)
	for _, a := range cmd.args {
		name := a.name
		if a.choices != nil {
			name = strings.Join(a.choices, "|")
		}
		switch {
		case a.many:
			fmt.Fprintf(&b, " <%s>...", name)
		case a.opt:
			fmt.Fprintf(&b, " [%s]", name)
		default:
			fmt.Fprintf(&b, " <%s>", name)
		}
	}
	b.WriteString("\n  " + cmd.help + "\n")
	names := make([]string, 0, len(cmd.flags))
	for n := range cmd.flags {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, n := range names {
		d := cmd.flags[n]
		v := " <value>"
		if d.isBool {
			v = ""
		} else if d.choices != nil {
			v = " " + strings.Join(d.choices, "|")
		}
		req := ""
		if contains(cmd.required, n) {
			req = " (required)"
		}
		fmt.Fprintf(&b, "  --%s%s  %s%s\n", n, v, d.help, req)
	}
	return b.String()
}

func topUsage() string {
	var b strings.Builder
	b.WriteString("sprint: append-only sprint log, shown on a local Grafana dashboard\n\n" +
		"usage: sprint [--db <file>] [--sprint <slug>] <command> ...\n\ncommands:\n")
	for _, c := range commands {
		fmt.Fprintf(&b, "  %-12s %s\n", c.path, c.help)
	}
	b.WriteString("\nRun `sprint <command> --help` for its flags.\n")
	return b.String()
}

// findCommand matches the longest command path at the start of args.
func findCommand(args []string) (*command, []string) {
	for n := 2; n >= 1; n-- {
		if len(args) < n {
			continue
		}
		path := strings.Join(args[:n], " ")
		for i := range commands {
			if commands[i].path == path {
				return &commands[i], args[n:]
			}
		}
	}
	return nil, args
}

// run is the whole CLI. It returns the exit code.
func run(args []string, stdout, stderr io.Writer) (code int) {
	c := &call{pos: map[string]string{}, vals: map[string]string{}, set: map[string]bool{},
		out: stdout, errOut: stderr}
	defer func() {
		if r := recover(); r != nil {
			if e, ok := r.(userError); ok {
				fmt.Fprintf(stderr, "sprint: %s\n", e.msg)
			} else if e, ok := r.(error); ok {
				fmt.Fprintf(stderr, "sprint: %v\n", e)
			} else {
				panic(r)
			}
			code = 1
		}
	}()
	// Global flags may come before the command.
	for len(args) > 0 && strings.HasPrefix(args[0], "--") {
		name, val, hasVal := strings.Cut(args[0][2:], "=")
		if _, ok := globalFlags[name]; !ok {
			break
		}
		if !hasVal {
			if len(args) < 2 {
				fail("--%s needs a value", name)
			}
			val, args = args[1], args[1:]
		}
		c.vals[name], c.set[name] = val, true
		args = args[1:]
	}
	if len(args) == 0 || args[0] == "help" || args[0] == "-h" || args[0] == "--help" {
		fmt.Fprint(stdout, topUsage())
		if len(args) == 0 {
			return 2
		}
		return 0
	}
	cmd, rest := findCommand(args)
	if cmd == nil {
		fail("unknown command %q\n\n%s", strings.Join(args[:min(2, len(args))], " "), topUsage())
	}
	for _, a := range rest {
		if a == "-h" || a == "--help" {
			fmt.Fprint(stdout, usage(cmd))
			return 0
		}
	}
	c.cmd = cmd
	parse(cmd, rest, c)
	c.dbPath = c.vals["db"]
	if c.dbPath == "" {
		c.dbPath = defaultDB()
	}
	s, closeDB := openWrite(c.dbPath)
	defer closeDB()
	c.store = s
	if cmd.prefetch != nil {
		cmd.prefetch(c)
	}
	s.write(func() { cmd.run(c) })
	return 0
}

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}
