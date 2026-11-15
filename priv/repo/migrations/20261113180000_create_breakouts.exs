defmodule Claper.Repo.Migrations.CreateBreakouts do
  @moduledoc """
  Breakout groups (Carceral Consultation, 2026-11-13; design record in
  docs/BREAKOUT.md).

  A breakout holds packets, a packet holds pieces in order. A piece is either
  typed text (kept on the piece) or one of the app's interactions, whose
  content stays in that interaction's own table, linked back through
  `breakout_piece_id` (one link column per interaction table, Ecto's advice
  for polymorphic associations, so every link is a real foreign key).

  Running a breakout creates a run with its groups and members. Answers given
  in a breakout live in breakout_answers, never in the interactions' own
  answer tables, so breakouts cannot disturb the slide-attached interactions.
  """
  use Ecto.Migration

  @interaction_tables [:polls, :forms, :quizzes, :word_clouds, :embeds]

  def change do
    create table(:breakouts) do
      add :uuid, :uuid, null: false
      add :title, :string, size: 255, null: false
      # In an event: the slide it belongs to. In the library: both null.
      add :presentation_file_id, references(:presentation_files, on_delete: :delete_all)
      add :position, :integer
      add :enabled, :boolean, default: false, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :material_mode, :string, size: 16, null: false, default: "same"
      add :group_sizing, :string, size: 16, null: false, default: "max_size"
      add :max_group_size, :integer, null: false, default: 5
      add :group_count, :integer
      add :timer_minutes, :integer
      # The library breakout this one was copied from (kept for reference only).
      add :source_breakout_id, references(:breakouts, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:breakouts, [:uuid])
    create index(:breakouts, [:presentation_file_id, :position])

    create index(:breakouts, [:user_id],
             where: "presentation_file_id IS NULL",
             name: :breakouts_library_index
           )

    create constraint(:breakouts, :breakouts_material_mode,
             check: "material_mode IN ('same', 'per_case')"
           )

    create constraint(:breakouts, :breakouts_group_sizing,
             check: "group_sizing IN ('max_size', 'group_count')"
           )

    create constraint(:breakouts, :breakouts_max_group_size,
             check: "max_group_size BETWEEN 2 AND 12"
           )

    create constraint(:breakouts, :breakouts_group_count,
             check: "group_count IS NULL OR group_count BETWEEN 1 AND 50"
           )

    create constraint(:breakouts, :breakouts_timer_minutes,
             check: "timer_minutes IS NULL OR timer_minutes BETWEEN 1 AND 240"
           )

    create table(:breakout_packets) do
      add :breakout_id, references(:breakouts, on_delete: :delete_all), null: false
      add :position, :integer, null: false, default: 0
      add :label, :string, size: 255

      timestamps()
    end

    create index(:breakout_packets, [:breakout_id, :position])

    create table(:breakout_pieces) do
      add :packet_id, references(:breakout_packets, on_delete: :delete_all), null: false
      add :position, :integer, null: false, default: 0
      add :kind, :string, size: 32, null: false
      # Typed text pieces keep their text here.
      add :body, :text
      add :answer_scope, :string, size: 16, null: false, default: "individual"
      add :visible_to_group, :boolean, null: false, default: false

      timestamps()
    end

    create index(:breakout_pieces, [:packet_id, :position])

    create constraint(:breakout_pieces, :breakout_pieces_answer_scope,
             check: "answer_scope IN ('individual', 'group')"
           )

    for table <- @interaction_tables do
      alter table(table) do
        add :breakout_piece_id, references(:breakout_pieces, on_delete: :delete_all)
      end

      create unique_index(table, [:breakout_piece_id], where: "breakout_piece_id IS NOT NULL")
    end

    create table(:breakout_runs) do
      add :breakout_id, references(:breakouts, on_delete: :delete_all), null: false
      add :started_at, :utc_datetime, null: false
      # Timer: when time is up (a signal only; nothing locks).
      add :ends_at, :utc_datetime
      # Answers become final when the run is stopped.
      add :stopped_at, :utc_datetime
      # Reporting back: the group shown on the big screen and phones.
      add :showing_group_id, :integer

      timestamps()
    end

    create index(:breakout_runs, [:breakout_id])

    create unique_index(:breakout_runs, [:breakout_id],
             where: "stopped_at IS NULL",
             name: :breakout_runs_one_open_index
           )

    create table(:breakout_groups) do
      add :run_id, references(:breakout_runs, on_delete: :delete_all), null: false
      add :number, :integer, null: false
      add :packet_id, references(:breakout_packets, on_delete: :nilify_all)
      add :note_taker_identifier, :string

      timestamps()
    end

    create unique_index(:breakout_groups, [:run_id, :number])

    create table(:breakout_members) do
      add :run_id, references(:breakout_runs, on_delete: :delete_all), null: false
      add :group_id, references(:breakout_groups, on_delete: :delete_all), null: false
      add :attendee_identifier, :string, null: false
      add :late, :boolean, null: false, default: false

      timestamps()
    end

    create unique_index(:breakout_members, [:run_id, :attendee_identifier])
    create index(:breakout_members, [:group_id])

    create table(:breakout_answers) do
      add :run_id, references(:breakout_runs, on_delete: :delete_all), null: false
      add :piece_id, references(:breakout_pieces, on_delete: :delete_all), null: false
      add :group_id, references(:breakout_groups, on_delete: :delete_all), null: false
      # Individual answers: who answered. Group answers: who wrote it last
      # (the note-taker at the time); the group owns the answer.
      add :attendee_identifier, :string, null: false
      add :scope, :string, size: 16, null: false
      add :response, :map, null: false, default: %{}

      timestamps()
    end

    create constraint(:breakout_answers, :breakout_answers_scope,
             check: "scope IN ('individual', 'group')"
           )

    create unique_index(:breakout_answers, [:run_id, :piece_id, :attendee_identifier],
             where: "scope = 'individual'",
             name: :breakout_answers_individual_index
           )

    create unique_index(:breakout_answers, [:run_id, :piece_id, :group_id],
             where: "scope = 'group'",
             name: :breakout_answers_group_index
           )

    create index(:breakout_answers, [:group_id])
  end
end
