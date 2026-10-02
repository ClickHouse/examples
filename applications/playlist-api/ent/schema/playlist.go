package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/edge"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"
	"github.com/google/uuid"
)

type Playlist struct{ ent.Schema }

func (Playlist) Fields() []ent.Field {
	return []ent.Field{field.UUID("id", uuid.UUID{}).Default(uuid.New), field.UUID("owner_id", uuid.UUID{}).Immutable(), field.String("name").MaxLen(80).NotEmpty(), field.Int("revision").Default(1).Min(1)}
}
func (Playlist) Edges() []ent.Edge {
	return []ent.Edge{edge.To("items", Item.Type), edge.From("owner", Account.Type).Ref("playlists").Field("owner_id").Unique().Required().Immutable()}
}
func (Playlist) Indexes() []ent.Index { return []ent.Index{index.Fields("owner_id", "id")} }
