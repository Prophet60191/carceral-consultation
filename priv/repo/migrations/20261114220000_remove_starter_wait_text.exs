defmodule Claper.Repo.Migrations.RemoveStarterWaitText do
  @moduledoc """
  The starter intro page no longer says "We will begin shortly." (Jose,
  2026-11-14). Removed where it is still exactly that starter text; anything
  changed is left alone. Block positions are renumbered 0, 1, 2…
  """
  use Ecto.Migration

  def up do
    execute("""
    DELETE FROM intro_blocks
    WHERE kind = 'text' AND data->>'body' = 'We will begin shortly.'
    """)

    execute("""
    UPDATE intro_blocks b SET position = r.rn - 1
    FROM (
      SELECT id, row_number() OVER (PARTITION BY intro_page_id ORDER BY position, id) AS rn
      FROM intro_blocks
    ) r
    WHERE r.id = b.id
    """)
  end

  def down, do: :ok
end
