package board

import (
	"context"
	"errors"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type Store struct{ DB *gorm.DB }

func (s Store) Projects(ctx context.Context, account, cursor string) ([]Project, error) {
	list := []Project{}
	query := s.DB.WithContext(ctx).Where("account_id = ?", account)
	if cursor != "" {
		query = query.Where("id > ?", cursor)
	}
	err := query.Order("id ASC").Limit(20).Find(&list).Error
	return list, err
}
func lockedProject(tx *gorm.DB, account, id, strength string) (Project, error) {
	var project Project
	result := tx.Clauses(clause.Locking{Strength: strength}).Where("account_id = ? AND id = ?", account, id).Take(&project)
	if errors.Is(result.Error, gorm.ErrRecordNotFound) {
		return project, NotFound
	}
	if result.Error != nil {
		return project, result.Error
	}
	if result.RowsAffected != 1 {
		return project, NotFound
	}
	return project, nil
}
func graph(tx *gorm.DB, project Project) (Snapshot, error) {
	snapshot := Snapshot{Project: project, Tasks: []Task{}, Edges: []Edge{}}
	if err := tx.Where("project_id = ?", project.ID).Order("id ASC").Limit(101).Find(&snapshot.Tasks).Error; err != nil {
		return snapshot, err
	}
	if err := tx.Where("project_id = ?", project.ID).Order("task_id ASC, prerequisite_id ASC").Limit(301).Find(&snapshot.Edges).Error; err != nil {
		return snapshot, err
	}
	if len(snapshot.Tasks) > 100 || len(snapshot.Edges) > 300 {
		return snapshot, errors.New("stored graph exceeds bounds")
	}
	return snapshot, nil
}
func (s Store) Snapshot(ctx context.Context, account, id string) (Snapshot, error) {
	var result Snapshot
	err := s.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		project, err := lockedProject(tx, account, id, "SHARE")
		if err != nil {
			return err
		}
		result, err = graph(tx, project)
		return err
	})
	return result, err
}
func bump(tx *gorm.DB, project Project) error {
	if project.Revision >= 1000000000 {
		return conflict("REVISION_LIMIT", "This project has reached its revision limit.")
	}
	result := tx.Model(&Project{}).Where("id = ? AND revision = ?", project.ID, project.Revision).UpdateColumn("revision", gorm.Expr("revision + 1"))
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected != 1 {
		return errors.New("project revision update missing")
	}
	return nil
}
func (s Store) mutate(ctx context.Context, account, id string, operation func(*gorm.DB, Snapshot) error) error {
	return s.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		project, err := lockedProject(tx, account, id, "UPDATE")
		if err != nil {
			return err
		}
		snapshot, err := graph(tx, project)
		if err != nil {
			return err
		}
		return operation(tx, snapshot)
	})
}
func (s Store) CreateTask(ctx context.Context, account, project, title string) (Task, error) {
	task := Task{ProjectID: project, Title: title}
	id, err := NewUUID()
	if err != nil {
		return task, err
	}
	task.ID = id
	err = s.mutate(ctx, account, project, func(tx *gorm.DB, snapshot Snapshot) error {
		if len(snapshot.Tasks) >= 100 {
			return conflict("TASK_LIMIT", "This project already has 100 tasks.")
		}
		if err := bump(tx, snapshot.Project); err != nil {
			return err
		}
		result := tx.Clauses(clause.Returning{}).Create(&task)
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected != 1 {
			return errors.New("task insert missing")
		}
		return nil
	})
	return task, err
}
func tasksByID(snapshot Snapshot) map[string]Task {
	tasks := make(map[string]Task)
	for _, task := range snapshot.Tasks {
		tasks[task.ID] = task
	}
	return tasks
}
func (s Store) AddEdge(ctx context.Context, account, project, task, prerequisite string) (Edge, error) {
	edge := Edge{ProjectID: project, TaskID: task, PrerequisiteID: prerequisite}
	err := s.mutate(ctx, account, project, func(tx *gorm.DB, snapshot Snapshot) error {
		tasks := tasksByID(snapshot)
		dependent, ok := tasks[task]
		if !ok {
			return NotFound
		}
		if _, ok := tasks[prerequisite]; !ok {
			return NotFound
		}
		for _, existing := range snapshot.Edges {
			if existing.TaskID == task && existing.PrerequisiteID == prerequisite {
				edge = existing
				return nil
			}
		}
		if dependent.Done {
			return conflict("TASK_DONE", "A completed task cannot gain a prerequisite.")
		}
		if task == prerequisite || Reaches(snapshot.Edges, prerequisite, task) {
			return conflict("CYCLE", "This prerequisite would create a cycle.")
		}
		if len(snapshot.Edges) >= 300 {
			return conflict("EDGE_LIMIT", "This project already has 300 prerequisites.")
		}
		if err := bump(tx, snapshot.Project); err != nil {
			return err
		}
		result := tx.Clauses(clause.Returning{}).Create(&edge)
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected != 1 {
			return errors.New("edge insert missing")
		}
		return nil
	})
	return edge, err
}
func (s Store) RemoveEdge(ctx context.Context, account, project, task, prerequisite string) error {
	return s.mutate(ctx, account, project, func(tx *gorm.DB, snapshot Snapshot) error {
		tasks := tasksByID(snapshot)
		if _, ok := tasks[task]; !ok {
			return NotFound
		}
		if _, ok := tasks[prerequisite]; !ok {
			return NotFound
		}
		exists := false
		for _, edge := range snapshot.Edges {
			if edge.TaskID == task && edge.PrerequisiteID == prerequisite {
				exists = true
				break
			}
		}
		if !exists {
			return nil
		}
		if err := bump(tx, snapshot.Project); err != nil {
			return err
		}
		result := tx.Where("project_id = ? AND task_id = ? AND prerequisite_id = ?", project, task, prerequisite).Delete(&Edge{})
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected != 1 {
			return errors.New("edge removal missing")
		}
		return nil
	})
}
func (s Store) Complete(ctx context.Context, account, project, id string) (Task, error) {
	var task Task
	err := s.mutate(ctx, account, project, func(tx *gorm.DB, snapshot Snapshot) error {
		tasks := tasksByID(snapshot)
		var ok bool
		task, ok = tasks[id]
		if !ok {
			return NotFound
		}
		if task.Done {
			return nil
		}
		for _, edge := range snapshot.Edges {
			if edge.TaskID == id && !tasks[edge.PrerequisiteID].Done {
				return conflict("PREREQUISITES_OPEN", "Complete this task’s prerequisites first.")
			}
		}
		if err := bump(tx, snapshot.Project); err != nil {
			return err
		}
		result := tx.Model(&task).Clauses(clause.Returning{}).Where("project_id = ? AND id = ? AND done = false", project, id).Updates(map[string]interface{}{"done": true, "done_at": gorm.Expr("clock_timestamp()")})
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected != 1 {
			return errors.New("task completion missing")
		}
		return nil
	})
	return task, err
}
