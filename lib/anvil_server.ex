defmodule AnvilServer do

  def start_link(initial_state) do
    GenServer.start_link(__MODULE__, initial_state)
  end

  # SERVER

  def init(state) do
    schedule_work()
    { :ok, state }
  end

  def handle_info(:work, state) do
    schedule_work()
    { :noreply, state }
  end

  defp schedule_work() do
    Process.send_after(self(), :work, 60 * 60 * 1000) # Check back in an hour
  end
end
