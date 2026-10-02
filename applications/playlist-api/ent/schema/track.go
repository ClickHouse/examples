package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/edge"
	"entgo.io/ent/schema/field"
	"github.com/google/uuid"
)

type Track struct{ ent.Schema }

func (Track) Fields() []ent.Field {
	return []ent.Field{field.UUID("id", uuid.UUID{}), field.String("title").MaxLen(80).NotEmpty(), field.String("artist").MaxLen(80).NotEmpty(), field.Int("duration_seconds").Min(1).Max(3600)}
}
func (Track) Edges() []ent.Edge { return []ent.Edge{edge.To("items", Item.Type)} }
