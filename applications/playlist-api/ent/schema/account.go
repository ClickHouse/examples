package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/edge"
	"entgo.io/ent/schema/field"
	"github.com/google/uuid"
)

type Account struct{ ent.Schema }

func (Account) Fields() []ent.Field { return []ent.Field{field.UUID("id", uuid.UUID{})} }
func (Account) Edges() []ent.Edge   { return []ent.Edge{edge.To("playlists", Playlist.Type)} }
