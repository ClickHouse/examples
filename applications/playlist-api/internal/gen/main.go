//go:build ignore

package main

import (
	"entgo.io/ent/entc"
	"entgo.io/ent/entc/gen"
	"log"
)

func main() {
	if err := entc.Generate("./ent/schema", &gen.Config{Features: []gen.Feature{gen.FeatureLock}}); err != nil {
		log.Fatal(err)
	}
}
