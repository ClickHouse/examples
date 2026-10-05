import {
  parse,
  getOperationAST,
  Kind,
  valueFromASTUntyped,
  type SelectionSetNode,
  type FragmentDefinitionNode,
} from "graphql";
export function validateOperation(
  source: unknown,
  variables: Record<string, unknown>,
  name?: string,
) {
  if (typeof source !== "string" || !source.trim() || source.length > 8192)
    throw new Error("Query text must be 1..8192 characters");
  const document = parse(source);
  const operation = getOperationAST(document, name);
  if (!operation || operation.operation === "subscription")
    throw new Error("Choose one query or mutation");
  const fragments = new Map(
    document.definitions
      .filter((d) => d.kind === Kind.FRAGMENT_DEFINITION)
      .map((d) => [d.name.value, d as FragmentDefinitionNode]),
  );
  let fields = 0;
  function connectionRows(
    set: SelectionSetNode | undefined,
    stack = new Set<string>(),
  ): boolean {
    if (!set) return false;
    return set.selections.some((s) => {
      if (s.kind === Kind.FIELD)
        return ["nodes", "edges"].includes(s.name.value);
      if (s.kind === Kind.INLINE_FRAGMENT)
        return connectionRows(s.selectionSet, stack);
      const key = s.name.value;
      if (stack.has(key)) throw new Error("Cyclic query fragment");
      const fragment = fragments.get(key);
      if (!fragment) throw new Error("Unknown fragment");
      return connectionRows(fragment.selectionSet, new Set([...stack, key]));
    });
  }
  function walk(set: SelectionSetNode, depth: number, stack: Set<string>) {
    if (depth > 8) throw new Error("Query nesting exceeds eight levels");
    for (const s of set.selections) {
      if (s.kind === Kind.FIELD) {
        if (++fields > 100) throw new Error("Query contains too many fields");
        if (["__schema", "__type"].includes(s.name.value))
          throw new Error("Use the checked-in schema for introspection");
        if (connectionRows(s.selectionSet)) {
          const page = s.arguments?.find(
            (a) => a.name.value === "first" || a.name.value === "last",
          );
          const n = page && valueFromASTUntyped(page.value, variables);
          if (typeof n !== "number" || !Number.isInteger(n) || n < 1 || n > 50)
            throw new Error("Connections require first or last between1 and50");
        }
        if (s.selectionSet) walk(s.selectionSet, depth + 1, stack);
      } else if (s.kind === Kind.INLINE_FRAGMENT)
        walk(s.selectionSet, depth, stack);
      else {
        const key = s.name.value;
        if (stack.has(key)) throw new Error("Cyclic query fragment");
        const f = fragments.get(key);
        if (!f) throw new Error("Unknown fragment");
        walk(f.selectionSet, depth, new Set([...stack, key]));
      }
    }
  }
  walk(operation.selectionSet, 1, new Set());
}
