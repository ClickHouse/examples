import type { CodegenConfig } from "@graphql-codegen/cli";
const config: CodegenConfig = {
  schema: "schema.graphql",
  documents: ["src/client/operations.graphql"],
  generates: {
    "src/client/gql/": {
      preset: "client",
      presetConfig: { fragmentMasking: false },
      config: { useTypeImports: true },
    },
  },
};
export default config;
