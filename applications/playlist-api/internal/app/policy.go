package app

import (
	"fmt"
	"github.com/vektah/gqlparser/v2/ast"
)

const CostLimit = 6000

func Cost(child, fanout int) int {
	if child < 0 || fanout < 1 || fanout > 50 || child > CostLimit/fanout {
		return CostLimit + 1
	}
	return 1 + child*fanout
}

// Count expanded syntactic occurrences, not merged response keys. Repeated
// fragments and aliases cannot turn two mutation fields into one allowed write.
func CheckOperation(doc *ast.QueryDocument, op *ast.OperationDefinition) error {
	if op.Operation == ast.Subscription {
		return bad("Subscriptions are disabled.")
	}
	fields, total := 0, 0
	var walk func(ast.SelectionSet, int) error
	walk = func(selections ast.SelectionSet, depth int) error {
		if len(selections) == 0 {
			return nil
		}
		if depth > 5 {
			return bad("Selection depth exceeds five.")
		}
		for _, selection := range selections {
			total++
			if total > 100 {
				return bad("Too many expanded selections.")
			}
			switch node := selection.(type) {
			case *ast.Field:
				if depth == 1 {
					fields++
				}
				if node.Name == "__schema" || node.Name == "__type" {
					return bad("Introspection is disabled.")
				}
				if err := walk(node.SelectionSet, depth+1); err != nil {
					return err
				}
			case *ast.InlineFragment:
				if err := walk(node.SelectionSet, depth); err != nil {
					return err
				}
			case *ast.FragmentSpread:
				fragment := doc.Fragments.ForName(node.Name)
				if fragment == nil {
					return bad("Unknown fragment.")
				}
				if err := walk(fragment.SelectionSet, depth); err != nil {
					return err
				}
			}
		}
		return nil
	}
	if err := walk(op.SelectionSet, 1); err != nil {
		return err
	}
	if op.Operation == ast.Mutation && fields != 1 {
		return &PublicError{"OPERATION_POLICY", "Supply exactly one top-level mutation field."}
	}
	if fields > 5 {
		return bad("At most five top-level query fields are allowed.")
	}
	return nil
}
func Bound(limit, max int) error {
	if limit < 1 || limit > max {
		return bad(fmt.Sprintf("Limit must be 1–%d.", max))
	}
	return nil
}
