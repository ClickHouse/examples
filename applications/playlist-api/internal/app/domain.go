package app

import (
	"context"
	"encoding/base64"
	"errors"
	"example.com/playlist-api/ent"
	"github.com/google/uuid"
	"strings"
	"unicode"
	"unicode/utf8"
)

type PublicError struct{ Code, Message string }

func (e *PublicError) Error() string { return e.Message }
func bad(message string) error       { return &PublicError{"INVALID", message} }

type ownerKey struct{}

func WithOwner(ctx context.Context, id uuid.UUID) context.Context {
	return context.WithValue(ctx, ownerKey{}, id)
}
func Owner(ctx context.Context) (uuid.UUID, error) {
	id, ok := ctx.Value(ownerKey{}).(uuid.UUID)
	if !ok {
		return uuid.Nil, errors.New("missing authenticated identity")
	}
	return id, nil
}
func Client(ctx context.Context) (*ent.Client, error) {
	client := ent.FromContext(ctx)
	if client == nil {
		return nil, errors.New("transaction client missing")
	}
	return client, nil
}
func ID(raw string) (uuid.UUID, error) {
	if len(raw) != 36 {
		return uuid.Nil, bad("A UUID is required.")
	}
	id, err := uuid.Parse(raw)
	if err != nil {
		return uuid.Nil, bad("A UUID is required.")
	}
	return id, nil
}
func Name(raw string) (string, error) {
	if !utf8.ValidString(raw) || utf8.RuneCountInString(raw) > 80 {
		return "", bad("Name must contain 1–80 characters.")
	}
	for _, r := range raw {
		if r == utf8.RuneError || unicode.IsControl(r) || unicode.Is(unicode.Cs, r) {
			return "", bad("Name contains invalid characters.")
		}
	}
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return "", bad("Name is required.")
	}
	return raw, nil
}
func IDs(raw []string) ([]uuid.UUID, error) {
	if len(raw) < 1 || len(raw) > 50 {
		return nil, bad("Supply 1–50 distinct tracks.")
	}
	result := make([]uuid.UUID, 0, len(raw))
	seen := map[uuid.UUID]bool{}
	for _, value := range raw {
		id, err := ID(value)
		if err != nil {
			return nil, err
		}
		if seen[id] {
			return nil, bad("Track IDs must be distinct.")
		}
		seen[id] = true
		result = append(result, id)
	}
	return result, nil
}
func Cursor(owner, last uuid.UUID) string {
	return base64.RawURLEncoding.EncodeToString([]byte(owner.String() + "|" + last.String()))
}
func ParseCursor(raw string, owner uuid.UUID) (uuid.UUID, error) {
	if len(raw) > 100 {
		return uuid.Nil, bad("Invalid cursor.")
	}
	data, err := base64.RawURLEncoding.DecodeString(raw)
	if err != nil {
		return uuid.Nil, bad("Invalid cursor.")
	}
	parts := strings.Split(string(data), "|")
	if len(parts) != 2 || parts[0] != owner.String() {
		return uuid.Nil, bad("Cursor belongs to another account.")
	}
	id, err := ID(parts[1])
	if err != nil || Cursor(owner, id) != raw {
		return uuid.Nil, bad("Invalid cursor.")
	}
	return id, nil
}
