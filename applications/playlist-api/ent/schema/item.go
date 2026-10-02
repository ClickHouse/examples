package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/edge"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"
	"github.com/google/uuid"
)

type Item struct{ ent.Schema }

func (Item) Fields() []ent.Field {
	return []ent.Field{field.UUID("id", uuid.UUID{}).Default(uuid.New), field.UUID("playlist_id", uuid.UUID{}).Immutable(), field.UUID("track_id", uuid.UUID{}).Immutable(), field.Int("position").Min(1).Max(50)}
}
func (Item) Edges() []ent.Edge {
	return []ent.Edge{edge.From("playlist", Playlist.Type).Ref("items").Field("playlist_id").Unique().Required().Immutable(), edge.From("track", Track.Type).Ref("items").Field("track_id").Unique().Required().Immutable()}
}
func (Item) Indexes() []ent.Index {
	return []ent.Index{index.Fields("playlist_id", "track_id").Unique(), index.Fields("playlist_id", "position").Unique().StorageKey("items_playlist_position")}
}
