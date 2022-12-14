package todo

import (
	"context"
	"fmt"
	"time"

	"github.com/AHAOAHA/Annal/binaries/internal/storage"
	"github.com/jedib0t/go-pretty/table"
	"github.com/spf13/cobra"
)

var listCmd = &cobra.Command{
	Use:     "list",
	Aliases: []string{"l"},
	Short:   "list tasks",
	Long:    `list tasks`,
	Run: func(cmd *cobra.Command, args []string) {
		ctx, cancel := context.WithTimeout(context.Background(), time.Second*3)
		defer cancel()
		tasks, err := storage.ListTodoTasks(ctx, storage.GetInstance())
		if err != nil {
			fmt.Printf("%v\n", err.Error())
			return
		}

		printTable("test", tasks, TableOptions{
			Columns: columns,
			Style:   table.StyleColoredDark,
		})
	},
}
