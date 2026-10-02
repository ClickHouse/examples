package inbox

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestPayloadBoundary(t *testing.T) {
	for _, raw := range []string{`{"kind":"page_view","path":"/docs"}`, `{"kind":"demo_failure","path":"/demo"}`} {
		if _, err := ParsePayload([]byte(raw)); err != nil {
			t.Fatal(err)
		}
	}
	for _, raw := range []string{`null`, `[]`, `{"kind":"other","path":"/"}`, `{"kind":"page_view","path":"relative"}`,
		`{"kind":"page_view","path":"/","integration_id":"attacker"}`, `{"kind":"page_view","path":"/"} {}`, `{"kind":"page_view","path":"/\n"}`} {
		if _, err := ParsePayload([]byte(raw)); err == nil {
			t.Errorf("accepted %s", raw)
		}
	}
}
func TestTokenIdentity(t *testing.T) {
	token := strings.Repeat("a", 32)
	tokens, err := ParseTokens(`{"00000000-0000-4000-8000-000000000001":"` + token + `"}`)
	if err != nil {
		t.Fatal(err)
	}
	handler := tokens.authenticate(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !identity(r.Context()).Valid {
			t.Fatal("identity missing")
		}
		w.WriteHeader(204)
	}))
	for _, auth := range []string{"", "Bearer wrong", "Basic " + token} {
		req := httptest.NewRequest("GET", "/", nil)
		req.Header.Set("Authorization", auth)
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, req)
		if response.Code != 401 {
			t.Fatalf("invalid auth returned %d", response.Code)
		}
	}
	req := httptest.NewRequest("GET", "/", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, req)
	if response.Code != 204 {
		t.Fatalf("valid auth returned %d", response.Code)
	}
	if _, err = ParseTokens(`{"not-a-uuid":"` + token + `"}`); err == nil {
		t.Fatal("invalid UUID accepted")
	}
	if _, err = ParseTokens(`{"00000000-0000-4000-8000-000000000001":"` + token + `","00000000-0000-4000-8000-000000000002":"` + token + `"}`); err == nil {
		t.Fatal("duplicate token accepted")
	}
}
