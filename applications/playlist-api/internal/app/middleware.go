package app

import (
	"context"
	"database/sql"
	"errors"
	"example.com/playlist-api/ent"
	"github.com/99designs/gqlgen/graphql"
	"github.com/vektah/gqlparser/v2/ast"
	"github.com/vektah/gqlparser/v2/gqlerror"
)

type Policy struct{}

func (Policy) ExtensionName() string                   { return "BoundedOperationPolicy" }
func (Policy) Validate(graphql.ExecutableSchema) error { return nil }
func (Policy) MutateOperationContext(_ context.Context, op *graphql.OperationContext) *gqlerror.Error {
	if err := CheckOperation(op.Doc, op.Operation); err != nil {
		return &gqlerror.Error{Message: err.Error(), Extensions: map[string]any{"code": "OPERATION_POLICY"}}
	}
	return nil
}

type QuerySnapshot struct{ Client *ent.Client }

func (QuerySnapshot) ExtensionName() string                   { return "QuerySnapshot" }
func (QuerySnapshot) Validate(graphql.ExecutableSchema) error { return nil }
func (q QuerySnapshot) InterceptResponse(ctx context.Context, next graphql.ResponseHandler) *graphql.Response {
	if graphql.GetOperationContext(ctx).Operation.Operation != ast.Query {
		return next(ctx)
	}
	tx, err := q.Client.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelRepeatableRead, ReadOnly: true})
	if err != nil {
		return graphql.ErrorResponse(ctx, "Database unavailable.")
	}
	defer tx.Rollback()
	ctx = ent.NewTxContext(ctx, tx)
	ctx = ent.NewContext(ctx, tx.Client())
	response := next(ctx)
	if len(response.Errors) > 0 {
		return &graphql.Response{Errors: response.Errors}
	}
	if err = tx.Commit(); err != nil {
		return graphql.ErrorResponse(ctx, "Database unavailable.")
	}
	return response
}
func PresentError(ctx context.Context, err error) *gqlerror.Error {
	out := graphql.DefaultErrorPresenter(ctx, err)
	if out.Extensions["code"] == "OPERATION_POLICY" {
		return out
	}
	if out.Extensions["code"] == "COMPLEXITY_LIMIT_EXCEEDED" {
		out.Message = "The requested query is too expensive."
		return out
	}
	var public *PublicError
	if errors.As(err, &public) {
		out.Message = public.Message
		out.Extensions = map[string]any{"code": public.Code}
	} else {
		out.Message = "The request could not be completed."
		out.Extensions = map[string]any{"code": "REQUEST_FAILED"}
	}
	return out
}

// Wrap the completed response outside Ent's middleware because its commit/open
// errors are constructed directly, bypassing the resolver error presenter.
func Sanitize(ctx context.Context, next graphql.ResponseHandler) *graphql.Response {
	response := next(ctx)
	if response == nil {
		return nil
	}
	for _, err := range response.Errors {
		code, _ := err.Extensions["code"].(string)
		switch code {
		case "INVALID", "NOT_FOUND", "STALE", "OPERATION_POLICY", "COMPLEXITY_LIMIT_EXCEEDED":
		default:
			err.Message = "The request could not be completed."
		}
	}
	return response
}
