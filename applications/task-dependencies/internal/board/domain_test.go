package board

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestUUIDSeparators(t *testing.T) {
	valid := "ABCDEF01-2345-6789-ABCD-EF0123456789"
	actual, err := UUID(valid)
	if err != nil || actual != strings.ToLower(valid) {
		t.Fatal(actual, err)
	}
	// Required separators plus two additional hyphens still give length 36,
	// but previously decoded only 15 bytes after removing every hyphen.
	invalid := "--CDEF01-2345-6789-ABCD-EF0123456789"
	if len(invalid) != 36 {
		t.Fatal("fixture length")
	}
	if _, err = UUID(invalid); err == nil {
		t.Fatal("extra separator accepted")
	}
}
func TestTitleUnicodeBoundary(t *testing.T) {
	for _, encoded := range []string{`"\ud800"`, `"bad\u007f"`, `"bad\u0085"`} {
		var text string
		if err := json.Unmarshal([]byte(encoded), &text); err != nil {
			t.Fatal(err)
		}
		if _, err := Title(text); err == nil {
			t.Fatal("unsafe title accepted")
		}
	}
	var paired string
	if err := json.Unmarshal([]byte(`"Plan \ud83d\ude80"`), &paired); err != nil {
		t.Fatal(err)
	}
	if _, err := Title(paired); err != nil {
		t.Fatal(err)
	}
	if title, err := Title("  Plan launch  "); err != nil || title != "Plan launch" {
		t.Fatal(title, err)
	}
}
func TestReachabilityLongCycle(t *testing.T) {
	edges := []Edge{{TaskID: "a", PrerequisiteID: "b"}, {TaskID: "b", PrerequisiteID: "c"}, {TaskID: "c", PrerequisiteID: "d"}}
	if !Reaches(edges, "a", "d") || Reaches(edges, "d", "a") || Reaches(edges, "x", "a") {
		t.Fatal("wrong path")
	}
	edges = append(edges, Edge{TaskID: "d", PrerequisiteID: "a"})
	if !Reaches(edges, "b", "a") {
		t.Fatal("visited cycle traversal")
	}
}
