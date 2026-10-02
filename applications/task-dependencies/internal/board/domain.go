package board

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"
)

type Problem struct {
	Status        int
	Code, Message string
}

func (p *Problem) Error() string          { return p.Message }
func conflict(code, message string) error { return &Problem{409, code, message} }

var NotFound = &Problem{404, "NOT_FOUND", "Project or task not found."}
var BadInput = &Problem{422, "INVALID_INPUT", "Use a title of 1–100 characters without control or replacement characters."}

func UUID(value string) (string, error) {
	if len(value) != 36 || value[8] != '-' || value[13] != '-' || value[18] != '-' || value[23] != '-' {
		return "", errors.New("invalid UUID")
	}
	raw := strings.ReplaceAll(value, "-", "")
	if len(raw) != 32 {
		return "", errors.New("invalid UUID separators")
	}
	decoded, err := hex.DecodeString(raw)
	if err != nil || len(decoded) != 16 {
		return "", errors.New("invalid UUID hex")
	}
	return strings.ToLower(value), nil
}
func NewUUID() (string, error) {
	var bytes [16]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return "", err
	}
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	s := hex.EncodeToString(bytes[:])
	return s[:8] + "-" + s[8:12] + "-" + s[12:16] + "-" + s[16:20] + "-" + s[20:], nil
}
func Title(value string) (string, error) {
	if !utf8.ValidString(value) || len(value) > 400 {
		return "", BadInput
	}
	for _, r := range value {
		if unicode.IsControl(r) || unicode.Is(unicode.Cs, r) || r == utf8.RuneError {
			return "", BadInput
		}
	}
	value = strings.TrimSpace(value)
	if n := utf8.RuneCountInString(value); n < 1 || n > 100 {
		return "", BadInput
	}
	return value, nil
}

type Project struct {
	ID        string    `json:"id"`
	AccountID string    `json:"-"`
	Name      string    `json:"name"`
	Revision  int64     `json:"revision"`
	CreatedAt time.Time `json:"created_at"`
}

func (Project) TableName() string { return "task_dependencies.projects" }

type Task struct {
	ID        string     `json:"id"`
	ProjectID string     `json:"project_id"`
	Title     string     `json:"title"`
	Done      bool       `json:"done"`
	CreatedAt time.Time  `json:"created_at"`
	DoneAt    *time.Time `json:"done_at"`
}

func (Task) TableName() string { return "task_dependencies.tasks" }

type Edge struct {
	ProjectID      string    `json:"project_id"`
	TaskID         string    `json:"task_id"`
	PrerequisiteID string    `json:"prerequisite_id"`
	CreatedAt      time.Time `json:"created_at"`
}

func (Edge) TableName() string { return "task_dependencies.edges" }

type Snapshot struct {
	Project Project `json:"project"`
	Tasks   []Task  `json:"tasks"`
	Edges   []Edge  `json:"edges"`
}

// Edges point from a task to its prerequisite. A new task -> prerequisite edge
// cycles exactly when the prerequisite already reaches the task.
func Reaches(edges []Edge, start, target string) bool {
	next := make(map[string][]string)
	for _, edge := range edges {
		next[edge.TaskID] = append(next[edge.TaskID], edge.PrerequisiteID)
	}
	visited := make(map[string]bool)
	pending := []string{start}
	for len(pending) > 0 {
		id := pending[len(pending)-1]
		pending = pending[:len(pending)-1]
		if id == target {
			return true
		}
		if visited[id] {
			continue
		}
		visited[id] = true
		pending = append(pending, next[id]...)
	}
	return false
}
