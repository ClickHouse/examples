package app

import (
	"context"
	"example.com/playlist-api/ent"
	"example.com/playlist-api/ent/item"
	"example.com/playlist-api/ent/playlist"
	"example.com/playlist-api/ent/track"
	"example.com/playlist-api/graph/model"
	"github.com/google/uuid"
)

func eager(query *ent.PlaylistQuery) *ent.PlaylistQuery {
	return query.WithItems(func(q *ent.ItemQuery) { q.Order(ent.Asc(item.FieldPosition)).WithTrack() })
}
func dto(row *ent.Playlist) (*model.Playlist, error) {
	result := &model.Playlist{ID: row.ID.String(), Name: row.Name, Revision: row.Revision, Items: []*model.PlaylistItem{}}
	children, err := row.Edges.ItemsOrErr()
	if err != nil {
		return nil, err
	}
	for _, child := range children {
		t, err := child.Edges.TrackOrErr()
		if err != nil {
			return nil, err
		}
		result.Items = append(result.Items, &model.PlaylistItem{Position: child.Position, Track: trackDTO(t)})
	}
	return result, nil
}
func trackDTO(t *ent.Track) *model.Track {
	return &model.Track{ID: t.ID.String(), Title: t.Title, Artist: t.Artist, DurationSeconds: t.DurationSeconds}
}
func Read(ctx context.Context, raw string) (*model.Playlist, error) {
	id, err := ID(raw)
	if err != nil {
		return nil, err
	}
	owner, err := Owner(ctx)
	if err != nil {
		return nil, err
	}
	client, err := Client(ctx)
	if err != nil {
		return nil, err
	}
	row, err := eager(client.Playlist.Query().Where(playlist.IDEQ(id), playlist.OwnerIDEQ(owner))).Only(ctx)
	if ent.IsNotFound(err) {
		return nil, &PublicError{"NOT_FOUND", "Playlist not found."}
	}
	if err != nil {
		return nil, err
	}
	return dto(row)
}
func List(ctx context.Context, limit int, cursor *string) (*model.PlaylistPage, error) {
	if limit < 1 || limit > 10 {
		return nil, bad("Page limit must be 1–10.")
	}
	owner, err := Owner(ctx)
	if err != nil {
		return nil, err
	}
	client, err := Client(ctx)
	if err != nil {
		return nil, err
	}
	query := client.Playlist.Query().Where(playlist.OwnerIDEQ(owner))
	if cursor != nil {
		id, err := ParseCursor(*cursor, owner)
		if err != nil {
			return nil, err
		}
		query = query.Where(playlist.IDGT(id))
	}
	rows, err := eager(query.Order(ent.Asc(playlist.FieldID)).Limit(limit + 1)).All(ctx)
	if err != nil {
		return nil, err
	}
	result := &model.PlaylistPage{Playlists: []*model.Playlist{}}
	if len(rows) > limit {
		next := Cursor(owner, rows[limit-1].ID)
		result.NextCursor = &next
		rows = rows[:limit]
	}
	for _, row := range rows {
		out, err := dto(row)
		if err != nil {
			return nil, err
		}
		result.Playlists = append(result.Playlists, out)
	}
	return result, nil
}
func Tracks(ctx context.Context, limit int) ([]*model.Track, error) {
	if limit < 1 || limit > 50 {
		return nil, bad("Track limit must be 1–50.")
	}
	client, err := Client(ctx)
	if err != nil {
		return nil, err
	}
	rows, err := client.Track.Query().Order(ent.Asc(track.FieldID)).Limit(limit).All(ctx)
	if err != nil {
		return nil, err
	}
	result := make([]*model.Track, 0, len(rows))
	for _, row := range rows {
		result = append(result, trackDTO(row))
	}
	return result, nil
}
func Create(ctx context.Context, input model.CreatePlaylistInput) (*model.Playlist, error) {
	name, err := Name(input.Name)
	if err != nil {
		return nil, err
	}
	ids, err := IDs(input.TrackIds)
	if err != nil {
		return nil, err
	}
	owner, err := Owner(ctx)
	if err != nil {
		return nil, err
	}
	client, err := Client(ctx)
	if err != nil {
		return nil, err
	}
	count, err := client.Track.Query().Where(track.IDIn(ids...)).Count(ctx)
	if err != nil {
		return nil, err
	}
	if count != len(ids) {
		return nil, bad("Every track must exist.")
	}
	row, err := client.Playlist.Create().SetOwnerID(owner).SetName(name).Save(ctx)
	if err != nil {
		return nil, err
	}
	for position, id := range ids {
		if _, err = client.Item.Create().SetPlaylistID(row.ID).SetTrackID(id).SetPosition(position + 1).Save(ctx); err != nil {
			return nil, err
		}
	}
	return Read(ctx, row.ID.String())
}
func Reorder(ctx context.Context, input model.ReorderInput) (*model.Playlist, error) {
	id, err := ID(input.ID)
	if err != nil {
		return nil, err
	}
	ids, err := IDs(input.TrackIds)
	if err != nil {
		return nil, err
	}
	if input.ExpectedRevision < 1 || input.ExpectedRevision >= 2147483647 {
		return nil, bad("Revision is out of bounds.")
	}
	owner, err := Owner(ctx)
	if err != nil {
		return nil, err
	}
	client, err := Client(ctx)
	if err != nil {
		return nil, err
	}
	row, err := client.Playlist.Query().Where(playlist.IDEQ(id), playlist.OwnerIDEQ(owner)).ForUpdate().Only(ctx)
	if ent.IsNotFound(err) {
		return nil, &PublicError{"NOT_FOUND", "Playlist not found."}
	}
	if err != nil {
		return nil, err
	}
	if row.Revision != input.ExpectedRevision {
		return nil, &PublicError{"STALE", "Playlist changed. Read its latest revision first."}
	}
	existing, err := client.Item.Query().Where(item.PlaylistIDEQ(id)).All(ctx)
	if err != nil {
		return nil, err
	}
	members := map[uuid.UUID]*ent.Item{}
	for _, child := range existing {
		members[child.TrackID] = child
	}
	if len(existing) != len(ids) {
		return nil, bad("Reorder must preserve every existing track.")
	}
	for position, trackID := range ids {
		child, ok := members[trackID]
		if !ok {
			return nil, bad("Reorder must be an exact membership permutation.")
		}
		if _, err = client.Item.UpdateOne(child).SetPosition(position + 1).Save(ctx); err != nil {
			return nil, err
		}
	}
	if _, err = client.Playlist.UpdateOne(row).AddRevision(1).Save(ctx); err != nil {
		return nil, err
	}
	return Read(ctx, id.String())
}
