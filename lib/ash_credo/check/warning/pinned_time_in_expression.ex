defmodule AshCredo.Check.Warning.PinnedTimeInExpression do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash],
    explanations: [
      check: """
      Using `^Date.utc_today()` or `^DateTime.utc_now()` inside an Ash expression
      freezes the value at compile time. The pinned value never changes after
      compilation, leading to subtle bugs that only manifest after time passes.

      Use Ash's built-in expression functions instead:

          # Bad — frozen at compile time
          filter expr(start_date <= ^Date.utc_today())

          # Good — evaluated at runtime
          filter expr(start_date <= today())

          # Bad
          filter expr(inserted_at >= ^DateTime.utc_now())

          # Good
          filter expr(inserted_at >= now())
      """
    ]

  alias AshCredo.Introspection

  @time_calls %{
    {[:Date], :utc_today} => "today()",
    {[:DateTime], :utc_now} => "now()",
    {[:NaiveDateTime], :utc_now} => "now()"
  }

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if Introspection.ash_resource?(source_file) do
      issue_meta = IssueMeta.for(source_file, params)

      Credo.Code.prewalk(
        source_file,
        fn
          {:expr, _meta, [body]} = ast, acc ->
            {ast, find_pinned_time_calls(body, issue_meta) ++ acc}

          ast, acc ->
            {ast, acc}
        end,
        []
      )
    else
      []
    end
  end

  defp find_pinned_time_calls(ast, issue_meta) do
    {_, issues} =
      Macro.prewalk(ast, [], fn
        {:^, meta, [{{:., _, [{:__aliases__, _, module}, func]}, _, _}]} = node, acc ->
          case Map.get(@time_calls, {module, func}) do
            nil ->
              {node, acc}

            replacement ->
              pinned = "^#{Enum.join(module, ".")}.#{func}()"

              issue =
                format_issue(issue_meta,
                  message:
                    "Use `#{replacement}` instead of `#{pinned}` in Ash expressions. " <>
                      "The pinned call is evaluated at compile time and never updates.",
                  trigger: pinned,
                  line_no: meta[:line]
                )

              {node, [issue | acc]}
          end

        node, acc ->
          {node, acc}
      end)

    issues
  end
end
