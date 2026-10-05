import { gql, type TypedDocumentNode } from "@apollo/client";
export type Task = { id: string; rowId: string; title: string; done: boolean };
export type Project = {
  id: string;
  rowId: string;
  name: string;
  description: string;
};
export type Connection<T> = {
  nodes: T[];
  totalCount: number;
  pageInfo: { hasNextPage: boolean; endCursor: string | null };
};
export type ProjectDetail = Project & {
  tasksByProjectIdAndWorkspaceId: Connection<Task>;
};
export const BoardDocument = gql`
  query Board($after: Cursor) {
    allProjects(
      first: 20
      after: $after
      orderBy: [CREATED_AT_DESC, PRIMARY_KEY_DESC]
    ) {
      totalCount
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
        id
        rowId
        name
        description
      }
    }
  }
` as TypedDocumentNode<
  { allProjects: Connection<Project> },
  { after?: string | null }
>;
export const ProjectDocument = gql`
  query ProjectNotebook($rowId: UUID!, $after: Cursor) {
    projectByRowId(rowId: $rowId) {
      id
      rowId
      name
      description
      tasksByProjectIdAndWorkspaceId(
        first: 50
        after: $after
        orderBy: [CREATED_AT_DESC, PRIMARY_KEY_DESC]
      ) {
        totalCount
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          id
          rowId
          title
          done
        }
      }
    }
  }
` as TypedDocumentNode<
  { projectByRowId: ProjectDetail | null },
  { rowId: string; after?: string | null }
>;
export const CreateProjectDocument = gql`
  mutation CreateProject($name: String!, $description: String!) {
    createProject(
      input: { project: { name: $name, description: $description } }
    ) {
      project {
        id
        rowId
        name
        description
      }
    }
  }
` as TypedDocumentNode<
  { createProject: { project: Project } },
  { name: string; description: string }
>;
export const CreateTaskDocument = gql`
  mutation CreateTask($projectId: UUID!, $title: String!) {
    createTask(input: { task: { projectId: $projectId, title: $title } }) {
      task {
        id
        rowId
        title
        done
      }
    }
  }
` as TypedDocumentNode<
  { createTask: { task: Task } },
  { projectId: string; title: string }
>;
export const UpdateTaskDocument = gql`
  mutation UpdateTask($rowId: UUID!, $done: Boolean!) {
    updateTaskByRowId(input: { rowId: $rowId, taskPatch: { done: $done } }) {
      task {
        id
        rowId
        title
        done
      }
    }
  }
` as TypedDocumentNode<
  { updateTaskByRowId: { task: Task } },
  { rowId: string; done: boolean }
>;
