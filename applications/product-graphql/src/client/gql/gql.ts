/* eslint-disable */
import * as types from './graphql';
import type { TypedDocumentNode as DocumentNode } from '@graphql-typed-document-node/core';

/**
 * Map of all GraphQL operations in the project.
 *
 * This map has several performance disadvantages:
 * 1. It is not tree-shakeable, so it will include all operations in the project.
 * 2. It is not minifiable, so the string of a GraphQL query will be multiple times inside the bundle.
 * 3. It does not support dead code elimination, so it will add unused operations.
 *
 * Therefore it is highly recommended to use the babel or swc plugin for production.
 * Learn more about it here: https://the-guild.dev/graphql/codegen/plugins/presets/preset-client#reducing-bundle-size
 */
type Documents = {
    "query Catalog($first: Int!, $offset: Int!, $search: String, $category: String) {\n  products(first: $first, offset: $offset, search: $search, category: $category) {\n    id\n    name\n    category\n    description\n    variants {\n      id\n      name\n      sku\n      priceCents\n    }\n  }\n}\n\nquery CollectionList {\n  collections {\n    id\n    title\n    revision\n  }\n}\n\nquery CollectionDetail($id: ID!) {\n  collection(id: $id) {\n    id\n    title\n    revision\n    products {\n      id\n      name\n      category\n      description\n      variants {\n        id\n        name\n        sku\n        priceCents\n      }\n    }\n  }\n}\n\nmutation NewCollection($title: String!, $productIds: [ID!]!) {\n  createCollection(title: $title, productIds: $productIds) {\n    id\n    title\n    revision\n    products {\n      id\n      name\n      category\n      description\n      variants {\n        id\n        name\n        sku\n        priceCents\n      }\n    }\n  }\n}\n\nmutation SaveCollection($id: ID!, $baseRevision: Int!, $productIds: [ID!]!) {\n  replaceCollection(id: $id, baseRevision: $baseRevision, productIds: $productIds) {\n    status\n    collection {\n      id\n      title\n      revision\n      products {\n        id\n        name\n        category\n        description\n        variants {\n          id\n          name\n          sku\n          priceCents\n        }\n      }\n    }\n  }\n}": typeof types.CatalogDocument,
};
const documents: Documents = {
    "query Catalog($first: Int!, $offset: Int!, $search: String, $category: String) {\n  products(first: $first, offset: $offset, search: $search, category: $category) {\n    id\n    name\n    category\n    description\n    variants {\n      id\n      name\n      sku\n      priceCents\n    }\n  }\n}\n\nquery CollectionList {\n  collections {\n    id\n    title\n    revision\n  }\n}\n\nquery CollectionDetail($id: ID!) {\n  collection(id: $id) {\n    id\n    title\n    revision\n    products {\n      id\n      name\n      category\n      description\n      variants {\n        id\n        name\n        sku\n        priceCents\n      }\n    }\n  }\n}\n\nmutation NewCollection($title: String!, $productIds: [ID!]!) {\n  createCollection(title: $title, productIds: $productIds) {\n    id\n    title\n    revision\n    products {\n      id\n      name\n      category\n      description\n      variants {\n        id\n        name\n        sku\n        priceCents\n      }\n    }\n  }\n}\n\nmutation SaveCollection($id: ID!, $baseRevision: Int!, $productIds: [ID!]!) {\n  replaceCollection(id: $id, baseRevision: $baseRevision, productIds: $productIds) {\n    status\n    collection {\n      id\n      title\n      revision\n      products {\n        id\n        name\n        category\n        description\n        variants {\n          id\n          name\n          sku\n          priceCents\n        }\n      }\n    }\n  }\n}": types.CatalogDocument,
};

/**
 * The graphql function is used to parse GraphQL queries into a document that can be used by GraphQL clients.
 *
 *
 * @example
 * ```ts
 * const query = graphql(`query GetUser($id: ID!) { user(id: $id) { name } }`);
 * ```
 *
 * The query argument is unknown!
 * Please regenerate the types.
 */
export function graphql(source: string): unknown;

/**
 * The graphql function is used to parse GraphQL queries into a document that can be used by GraphQL clients.
 */
export function graphql(source: "query Catalog($first: Int!, $offset: Int!, $search: String, $category: String) {\n  products(first: $first, offset: $offset, search: $search, category: $category) {\n    id\n    name\n    category\n    description\n    variants {\n      id\n      name\n      sku\n      priceCents\n    }\n  }\n}\n\nquery CollectionList {\n  collections {\n    id\n    title\n    revision\n  }\n}\n\nquery CollectionDetail($id: ID!) {\n  collection(id: $id) {\n    id\n    title\n    revision\n    products {\n      id\n      name\n      category\n      description\n      variants {\n        id\n        name\n        sku\n        priceCents\n      }\n    }\n  }\n}\n\nmutation NewCollection($title: String!, $productIds: [ID!]!) {\n  createCollection(title: $title, productIds: $productIds) {\n    id\n    title\n    revision\n    products {\n      id\n      name\n      category\n      description\n      variants {\n        id\n        name\n        sku\n        priceCents\n      }\n    }\n  }\n}\n\nmutation SaveCollection($id: ID!, $baseRevision: Int!, $productIds: [ID!]!) {\n  replaceCollection(id: $id, baseRevision: $baseRevision, productIds: $productIds) {\n    status\n    collection {\n      id\n      title\n      revision\n      products {\n        id\n        name\n        category\n        description\n        variants {\n          id\n          name\n          sku\n          priceCents\n        }\n      }\n    }\n  }\n}"): (typeof documents)["query Catalog($first: Int!, $offset: Int!, $search: String, $category: String) {\n  products(first: $first, offset: $offset, search: $search, category: $category) {\n    id\n    name\n    category\n    description\n    variants {\n      id\n      name\n      sku\n      priceCents\n    }\n  }\n}\n\nquery CollectionList {\n  collections {\n    id\n    title\n    revision\n  }\n}\n\nquery CollectionDetail($id: ID!) {\n  collection(id: $id) {\n    id\n    title\n    revision\n    products {\n      id\n      name\n      category\n      description\n      variants {\n        id\n        name\n        sku\n        priceCents\n      }\n    }\n  }\n}\n\nmutation NewCollection($title: String!, $productIds: [ID!]!) {\n  createCollection(title: $title, productIds: $productIds) {\n    id\n    title\n    revision\n    products {\n      id\n      name\n      category\n      description\n      variants {\n        id\n        name\n        sku\n        priceCents\n      }\n    }\n  }\n}\n\nmutation SaveCollection($id: ID!, $baseRevision: Int!, $productIds: [ID!]!) {\n  replaceCollection(id: $id, baseRevision: $baseRevision, productIds: $productIds) {\n    status\n    collection {\n      id\n      title\n      revision\n      products {\n        id\n        name\n        category\n        description\n        variants {\n          id\n          name\n          sku\n          priceCents\n        }\n      }\n    }\n  }\n}"];

export function graphql(source: string) {
  return (documents as any)[source] ?? {};
}

export type DocumentType<TDocumentNode extends DocumentNode<any, any>> = TDocumentNode extends DocumentNode<  infer TType,  any>  ? TType  : never;