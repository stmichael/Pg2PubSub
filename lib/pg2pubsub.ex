defmodule Pg2PubSub do
  use GenServer
  require Logger

  def start_link() do
    Logger.debug "Publisher starting..."
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    Logger.debug "Publisher started (#{inspect self})"
    {:ok, []}
  end

  def subscribe(slug, pid) do
    GenServer.call(pid, {:subscribe, slug, self})
  end

  def unsubscribe(slug, pid) do
    GenServer.call(pid, {:unsubscribe, slug, self})
  end

  def publish(slug, events, pid) do
    GenServer.cast(pid, {:publish, slug, events})
  end

  def handle_call({:subscribe, topic, pid}, from = {from_pid, _ref}, s) do
    Logger.debug "#{inspect from_pid} subscribing to #{topic}..."
    :pg2.create(topic)
    case :pg2.get_members(topic) do
      {:error, error} ->
        Logger.error "Publisher failed to get members of topic #{topic}: #{error}"
        {:stop, error, s}
      pids ->
        unless pid in pids do
          :pg2.join(topic, pid)
          Logger.debug "#{inspect from_pid} subscribed to #{topic}"
          {:reply, :ok, [pid|pids]}
      else
        Logger.debug "#{inspect from_pid} already subscribed to #{topic}"
        GenServer.reply(from, {:already_registered, pids})
        {:reply, :ok, s}
      end
    end
  end

  def handle_call({:unsubscribe, topic, pid}, {from_pid, _ref}, s) do
    Logger.debug "#{inspect from_pid} unsubscribing from #{topic}..."
    case :pg2.leave(topic, pid) do
      {:error, error} ->
        Logger.warn "#{inspect from_pid} failed to unsubscribe from #{topic}: #{error}"
        members = :pg2.get_members(topic)
        {:noreply, members}
      :ok ->
        Logger.debug "#{inspect from_pid} unsubscribed from #{topic}"
        members = :pg2.get_members(topic)
        {:reply, :ok, members}
    end
  end

  def handle_cast({:publish, topic, message}, s) do
    case :pg2.get_members(topic) do
      {:error, _} ->
        {:noreply, s}
      pids ->
        for pid <- pids, do: send(pid, message)
        {:noreply, s}
    end
  end
end
