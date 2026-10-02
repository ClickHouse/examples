package httpapi

import (
	"bytes"
	"github.com/ClickHouse/examples/applications/task-dependencies/internal/board"
	"net/http/httptest"
	"strings"
	"testing"
)

func request(t *testing.T, path, body, origin, token string) int {
	t.Helper()
	credentials, err := Credentials(strings.Repeat("n", 32), strings.Repeat("s", 32))
	if err != nil {
		t.Fatal(err)
	}
	r := Router(board.Store{}, credentials)
	req := httptest.NewRequest("POST", path, bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if origin != "" {
		req.Header.Set("Origin", origin)
	}
	out := httptest.NewRecorder()
	r.ServeHTTP(out, req)
	return out.Code
}
func TestCredentialMapping(t *testing.T) {
	if _, err := Credentials("short", "short"); err == nil {
		t.Fatal("weak tokens accepted")
	}
	if status := request(t, "/api/projects/invalid/tasks", `{}`, "", ""); status != 401 {
		t.Fatal(status)
	}
}
func TestForeignOrigin(t *testing.T) {
	if status := request(t, "/api/projects/20000000-0000-4000-8000-000000000001/tasks", `{"title":"Plan"}`, "https://foreign.invalid", strings.Repeat("n", 32)); status != 403 {
		t.Fatal(status)
	}
}
func TestStrictJSONAndUUID(t *testing.T) {
	base := "/api/projects/20000000-0000-4000-8000-000000000001/tasks"
	for _, body := range []string{`{"title":"first","title":"second"}`, `{"unknown":"x"}`, `{"title":42}`, `{"title":"x"} {}`, `[`} {
		if status := request(t, base, body, "", strings.Repeat("n", 32)); status != 400 {
			t.Fatal(status, body)
		}
	}
	if status := request(t, "/api/projects/--000000-0000-4000-8000-000000000001/tasks", `{"title":"x"}`, "", strings.Repeat("n", 32)); status != 400 {
		t.Fatal(status)
	}
}
