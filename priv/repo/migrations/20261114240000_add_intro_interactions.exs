defmodule Claper.Repo.Migrations.AddIntroInteractions do
  @moduledoc """
  Interactions on the intro page (docs/INTRO.md, decisions 11-16): an
  interaction's content can belong to an intro block (`intro_block_id`), as
  it can to a breakout piece; intro blocks gain the interaction kinds; and
  participants' answers are kept in `intro_answers`.
  """
  use Ecto.Migration

  @tables [:polls, :forms, :quizzes, :word_clouds, :embeds]
  @kinds ~w(heading text image stat agenda link divider poll quiz form word_cloud embed)
  @old_kinds ~w(heading text image stat agenda link divider)

  def up do
    for table <- @tables do
      alter table(table) do
        add :intro_block_id, references(:intro_blocks, on_delete: :delete_all)
      end

      create unique_index(table, [:intro_block_id], where: "intro_block_id IS NOT NULL")
    end

    drop constraint(:intro_blocks, :intro_blocks_kind)
    create constraint(:intro_blocks, :intro_blocks_kind, check: kinds_check(@kinds))

    create table(:intro_answers) do
      add :intro_block_id, references(:intro_blocks, on_delete: :delete_all), null: false
      add :attendee_identifier, :string, null: false
      add :response, :map, null: false, default: %{}
      timestamps()
    end

    create unique_index(:intro_answers, [:intro_block_id, :attendee_identifier])
  end

  def down do
    drop table(:intro_answers)
    execute("DELETE FROM intro_blocks WHERE kind NOT IN (#{quoted(@old_kinds)})")
    drop constraint(:intro_blocks, :intro_blocks_kind)
    create constraint(:intro_blocks, :intro_blocks_kind, check: kinds_check(@old_kinds))

    for table <- @tables do
      alter table(table) do
        remove :intro_block_id
      end
    end
  end

  defp kinds_check(kinds), do: "kind IN (#{quoted(kinds)})"
  defp quoted(kinds), do: Enum.map_join(kinds, ", ", &"'#{&1}'")
end
