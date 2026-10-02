package httpapi

import (
	"bytes"
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"github.com/ClickHouse/examples/applications/task-dependencies/internal/board"
	"github.com/gin-gonic/gin"
	"io"
	"net/http"
	"strings"
	"time"
)

const North = "10000000-0000-4000-8000-000000000001"
const South = "10000000-0000-4000-8000-000000000002"

type Credential struct {
	Digest  [32]byte
	Account string
}

func Credentials(north, south string) ([]Credential, error) {
	if len(north) < 32 || len(south) < 32 || len(north) > 256 || len(south) > 256 || north == south {
		return nil, errors.New("two distinct bearer tokens of 32–256 bytes required")
	}
	return []Credential{{sha256.Sum256([]byte(north)), North}, {sha256.Sum256([]byte(south)), South}}, nil
}
func report(c *gin.Context, err error) {
	var problem *board.Problem
	if errors.As(err, &problem) {
		c.JSON(problem.Status, gin.H{"error": problem.Code, "message": problem.Message})
		return
	}
	c.JSON(503, gin.H{"error": "DATABASE_UNAVAILABLE", "message": "The operation could not be confirmed. Read the current state before retrying a task creation."})
}
func bad(c *gin.Context, message string) {
	c.AbortWithStatusJSON(400, gin.H{"error": "BAD_REQUEST", "message": message})
}
func id(c *gin.Context, key string) (string, bool) {
	value, err := board.UUID(c.Param(key))
	if err != nil {
		bad(c, "Use a valid UUID path.")
		return "", false
	}
	return value, true
}
func decode(c *gin.Context, target any) bool {
	if c.GetHeader("Content-Type") != "application/json" {
		bad(c, "Use Content-Type: application/json.")
		return false
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 8192)
	body, err := io.ReadAll(c.Request.Body)
	if err != nil {
		bad(c, "JSON body must fit 8 KiB.")
		return false
	}
	// Reject duplicate top-level properties before decoding the typed shape.
	scan := json.NewDecoder(bytes.NewReader(body))
	token, err := scan.Token()
	if err != nil || token != json.Delim('{') {
		bad(c, "Use one JSON object.")
		return false
	}
	seen := map[string]bool{}
	for scan.More() {
		key, err := scan.Token()
		if err != nil {
			bad(c, "Malformed JSON.")
			return false
		}
		name, ok := key.(string)
		if !ok || seen[name] {
			bad(c, "Duplicate JSON property.")
			return false
		}
		seen[name] = true
		var raw json.RawMessage
		if scan.Decode(&raw) != nil {
			bad(c, "Malformed JSON.")
			return false
		}
	}
	if _, err = scan.Token(); err != nil {
		bad(c, "Malformed JSON.")
		return false
	}
	var extra any
	if scan.Decode(&extra) != io.EOF {
		bad(c, "Use exactly one JSON object.")
		return false
	}
	decoder := json.NewDecoder(bytes.NewReader(body))
	decoder.DisallowUnknownFields()
	if decoder.Decode(target) != nil {
		bad(c, "Use the documented JSON fields and types.")
		return false
	}
	return true
}
func Router(store board.Store, credentials []Credential) *gin.Engine {
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.SetTrustedProxies(nil)
	r.Use(gin.CustomRecoveryWithWriter(io.Discard, func(c *gin.Context, _ any) {
		c.AbortWithStatusJSON(503, gin.H{"error": "REQUEST_FAILED", "message": "The request could not be completed."})
	}))
	r.Use(func(c *gin.Context) {
		c.Header("Cache-Control", "no-store")
		c.Header("X-Content-Type-Options", "nosniff")
		ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
		defer cancel()
		c.Request = c.Request.WithContext(ctx)
		c.Next()
	})
	r.GET("/healthz", func(c *gin.Context) {
		pool, err := store.DB.DB()
		if err != nil || pool.PingContext(c.Request.Context()) != nil {
			c.Status(503)
			return
		}
		c.JSON(200, gin.H{"status": "ready"})
	})
	api := r.Group("/api", func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		if !strings.HasPrefix(header, "Bearer ") || len(header) > 263 {
			c.AbortWithStatusJSON(401, gin.H{"error": "UNAUTHORIZED", "message": "Use an account bearer token."})
			return
		}
		digest := sha256.Sum256([]byte(strings.TrimPrefix(header, "Bearer ")))
		account := ""
		for _, credential := range credentials {
			if subtle.ConstantTimeCompare(digest[:], credential.Digest[:]) == 1 {
				account = credential.Account
			}
		}
		if account == "" {
			c.AbortWithStatusJSON(401, gin.H{"error": "UNAUTHORIZED", "message": "Use an account bearer token."})
			return
		}
		// Bearer headers are not ambient browser cookies. Reject foreign unsafe
		// browser origins as an additional boundary; no cross-origin API is enabled.
		if c.Request.Method != "GET" && c.Request.Method != "HEAD" {
			origin := c.GetHeader("Origin")
			if origin != "" && origin != "http://127.0.0.1:8090" {
				c.AbortWithStatusJSON(403, gin.H{"error": "ORIGIN_REJECTED", "message": "Use the local API origin."})
				return
			}
		}
		c.Set("account", account)
		c.Next()
	})
	api.GET("/projects", func(c *gin.Context) {
		cursor := c.Query("after")
		for key, values := range c.Request.URL.Query() {
			if key != "after" || len(values) != 1 {
				bad(c, "Only one after cursor is supported.")
				return
			}
		}
		if cursor != "" {
			var err error
			cursor, err = board.UUID(cursor)
			if err != nil {
				bad(c, "Use a valid UUID cursor.")
				return
			}
		}
		result, err := store.Projects(c.Request.Context(), c.GetString("account"), cursor)
		if err != nil {
			report(c, err)
			return
		}
		c.JSON(200, result)
	})
	api.GET("/projects/:project", func(c *gin.Context) {
		project, ok := id(c, "project")
		if !ok {
			return
		}
		result, err := store.Snapshot(c.Request.Context(), c.GetString("account"), project)
		if err != nil {
			report(c, err)
			return
		}
		c.JSON(200, result)
	})
	api.POST("/projects/:project/tasks", func(c *gin.Context) {
		project, ok := id(c, "project")
		if !ok {
			return
		}
		var input struct {
			Title *string `json:"title"`
		}
		if !decode(c, &input) {
			return
		}
		if input.Title == nil {
			report(c, board.BadInput)
			return
		}
		title, err := board.Title(*input.Title)
		if err != nil {
			report(c, err)
			return
		}
		task, err := store.CreateTask(c.Request.Context(), c.GetString("account"), project, title)
		if err != nil {
			report(c, err)
			return
		}
		c.JSON(201, task)
	})
	api.POST("/projects/:project/tasks/:task/prerequisites", func(c *gin.Context) {
		project, ok := id(c, "project")
		if !ok {
			return
		}
		task, ok := id(c, "task")
		if !ok {
			return
		}
		var input struct {
			PrerequisiteID *string `json:"prerequisite_id"`
		}
		if !decode(c, &input) {
			return
		}
		if input.PrerequisiteID == nil {
			bad(c, "Use a prerequisite UUID.")
			return
		}
		prerequisite, err := board.UUID(*input.PrerequisiteID)
		if err != nil {
			bad(c, "Use a prerequisite UUID.")
			return
		}
		edge, err := store.AddEdge(c.Request.Context(), c.GetString("account"), project, task, prerequisite)
		if err != nil {
			report(c, err)
			return
		}
		c.JSON(200, edge)
	})
	api.DELETE("/projects/:project/tasks/:task/prerequisites/:prerequisite", func(c *gin.Context) {
		project, ok := id(c, "project")
		if !ok {
			return
		}
		task, ok := id(c, "task")
		if !ok {
			return
		}
		prerequisite, ok := id(c, "prerequisite")
		if !ok {
			return
		}
		if err := store.RemoveEdge(c.Request.Context(), c.GetString("account"), project, task, prerequisite); err != nil {
			report(c, err)
			return
		}
		c.Status(204)
	})
	api.POST("/projects/:project/tasks/:task/complete", func(c *gin.Context) {
		project, ok := id(c, "project")
		if !ok {
			return
		}
		task, ok := id(c, "task")
		if !ok {
			return
		}
		var input struct{}
		if !decode(c, &input) {
			return
		}
		result, err := store.Complete(c.Request.Context(), c.GetString("account"), project, task)
		if err != nil {
			report(c, err)
			return
		}
		c.JSON(200, result)
	})
	return r
}
