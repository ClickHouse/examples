package app

import (
	"context"
	"github.com/google/uuid"
	"github.com/vektah/gqlparser/v2/ast"
	"github.com/vektah/gqlparser/v2/parser"
	"testing"
)

func TestMutationExpansion(t *testing.T) {
	for _, query := range []string{`mutation{ a:createPlaylist(input:{name:"x",trackIds:[]}){id} b:createPlaylist(input:{name:"y",trackIds:[]}){id}}`, `mutation{...F} fragment F on Mutation{a:createPlaylist(input:{name:"x",trackIds:[]}){id} ...G} fragment G on Mutation{b:createPlaylist(input:{name:"x",trackIds:[]}){id}}`, `mutation{...F ...F} fragment F on Mutation{createPlaylist(input:{name:"x",trackIds:[]}){id}}`} {
		doc, err := parser.ParseQuery(&ast.Source{Input: query})
		if err != nil {
			t.Fatal(err)
		}
		if CheckOperation(doc, doc.Operations[0]) == nil {
			t.Fatal("multiple expanded writes accepted")
		}
	}
	doc, _ := parser.ParseQuery(&ast.Source{Input: `mutation{...F} fragment F on Mutation{one:createPlaylist(input:{name:"x",trackIds:[]}){id}}`})
	if err := CheckOperation(doc, doc.Operations[0]); err != nil {
		t.Fatal(err)
	}
}
func TestBoundsAndExactPermutationInputs(t *testing.T) {
	id := uuid.NewString()
	if _, err := IDs([]string{id, id}); err == nil {
		t.Fatal("duplicate accepted")
	}
	if _, err := IDs(make([]string, 51)); err == nil {
		t.Fatal("oversized accepted")
	}
	if _, err := Name("\u0085name"); err == nil {
		t.Fatal("control stripped")
	}
	if _, err := Name(string([]byte{255})); err == nil {
		t.Fatal("invalid Unicode accepted")
	}
}
func TestScopedCanonicalCursor(t *testing.T) {
	a, b, last := uuid.New(), uuid.New(), uuid.New()
	text := Cursor(a, last)
	if got, err := ParseCursor(text, a); err != nil || got != last {
		t.Fatal("cursor roundtrip")
	}
	if _, err := ParseCursor(text, b); err == nil {
		t.Fatal("account crossing")
	}
	if _, err := ParseCursor(text+"=", a); err == nil {
		t.Fatal("noncanonical accepted")
	}
}
func TestNoGlobalClientFallback(t *testing.T) {
	if _, err := Client(context.Background()); err == nil {
		t.Fatal("missing transaction client accepted")
	}
}
func TestComplexitySaturates(t *testing.T) {
	if Cost(1<<62, 50) <= CostLimit {
		t.Fatal("overflow accepted")
	}
	if Cost(4, 50) != 201 {
		t.Fatal("fanout not multiplied")
	}
	if Cost(1, 51) <= CostLimit {
		t.Fatal("invalid fanout accepted")
	}
}

func TestNameReplacementRuneAndPairedUnicode(t *testing.T) {
	if _, err := Name("Lone surrogate decoded as \uFFFD"); err == nil {
		t.Fatal("replacement rune accepted")
	}
	if value, err := Name("Paired \U0001F680"); err != nil || value != "Paired \U0001F680" {
		t.Fatal("valid non-BMP name rejected")
	}
}
