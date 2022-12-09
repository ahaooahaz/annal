package todo

import (
	"context"
	"strconv"

	proto "github.com/AHAOAHA/Annal/binaries/internal/pb/gen"
	"github.com/AHAOAHA/Annal/binaries/internal/storage"
	"github.com/jmoiron/sqlx"
	"github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
)

var doneCmd = &cobra.Command{
	Use:     "done",
	Aliases: []string{"d"},
	Short:   "done task",
	Long:    `done task`,
	Run:     doneTodoTasks,
}

func doneTodoTasks(cmd *cobra.Command, args []string) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	for _, idS := range args {
		id, err := strconv.ParseInt(idS, 10, 64)
		if err != nil {
			logrus.Errorf("%s", err.Error())
			continue
		}
		err = doneTodoTask(ctx, id)
		if err != nil {
			logrus.Errorf("%s", err.Error())
			continue
		}
	}
}

func doneTodoTask(ctx context.Context, ID int64) (err error) {
	var tx *sqlx.Tx
	tx, err = storage.GetInstance().Beginx()
	if err != nil {
		logrus.Errorf("%v", err.Error())
		return
	}

	var task *proto.TodoTask
	task, err = storage.SelectTodoTaskForUpdate(ctx, tx, ID)
	if err != nil {
		logrus.Errorf("%v", err.Error())
		tx.Rollback()
		return
	}

	task.Status = proto.TodoTaskStatus_DONE
	err = storage.UpdateTodoTask(ctx, tx, task)
	if err != nil {
		logrus.Errorf("%v", err.Error())
		tx.Rollback()
		return
	}

	if err = tx.Commit(); err != nil {
		logrus.Errorf("%v", err.Error())
		tx.Rollback()
		return
	}

	return
}