package todo

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"time"

	proto "github.com/AHAOAHA/Annal/binaries/internal/pb/gen"
	"github.com/AHAOAHA/Annal/binaries/internal/storage"
	"github.com/google/uuid"
	"github.com/spf13/cobra"
)

var createCmd = &cobra.Command{
	Use:     "create",
	Aliases: []string{"c"},
	Short:   "create task",
	Long:    `create task`,
	Run:     createTodoTask,
}

func createTodoTask(cmd *cobra.Command, args []string) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var err error
	task := &proto.TodoTask{
		UUID:      uuid.New().String(),
		UpdatedAt: time.Now().Unix(),
		CreatedAt: time.Now().Unix(),
	}
	reader := bufio.NewReader(os.Stdin)
	fmt.Printf("What todo:\n")
	title, _, _ := reader.ReadLine()
	task.Title = string(title)
	fmt.Printf("What desp:\n")
	desp, _, _ := reader.ReadLine()
	task.Description = string(desp)
	fmt.Printf("When todo: (default: 1 hour later)\n")
	var planT int
	var plan time.Time

	fmt.Scanf("%d\n", planT)
	switch planT {
	case 1:
		fmt.Printf("Input time: (format: %s)\n", _TimeFormatString)
		planS, _, _ := reader.ReadLine()
		plan, err = time.Parse(_TimeFormatString, string(planS))
		if err != nil {
			fmt.Fprintf(os.Stderr, "%s\n", err.Error())
			return
		}
	default:
		plan = time.Now().Add(time.Hour)
	}
	task.Plan = plan.Unix()

	var tasks []*proto.TodoTask
	tasks, err = storage.ListTodoTasks(ctx, storage.GetInstance())
	if err != nil {
		fmt.Fprintf(os.Stderr, "%v", err.Error())
		return
	}

	useIndexs := make(map[int64]bool)
	for _, t := range tasks {
		useIndexs[t.GetIndex()] = true
	}

	var index int64
	for index = 1; index <= 100; index++ {
		_, used := useIndexs[index]
		if !used {
			break
		}
	}
	task.Index = index
	err = CreateTodoTasks(ctx, []*proto.TodoTask{task})
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s\n", err.Error())
		return
	}
}

func CreateTodoTasks(ctx context.Context, tasks []*proto.TodoTask) (err error) {
	if len(tasks) == 0 {
		return
	}

	for _, task := range tasks {
		if err = task.Validate(); err != nil {
			return
		}
	}

	err = storage.CreateTodoTasks(ctx, storage.GetInstance(), tasks)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%v", err.Error())
		return
	}
	return
}
