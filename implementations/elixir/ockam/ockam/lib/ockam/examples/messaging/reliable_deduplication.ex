defmodule Ockam.Examples.Messaging.ReliableDeduplication do
  @moduledoc """
  Example of combining reliable delivery with index-ordering deduplication.

  Such combination allows to get low message loss with high uniqness of messages
  as long as pipes and channels are available and have no errors
  """

  alias Ockam.Examples.Messaging.Filter
  alias Ockam.Examples.Messaging.Shuffle

  alias Ockam.Examples.Ping
  alias Ockam.Examples.Pong

  alias Ockam.Messaging.Delivery.ResendPipe
  alias Ockam.Messaging.Ordering.Strict.IndexPipe

  alias Ockam.Messaging.PipeChannel

  alias Ockam.PubSubSubscriber

  alias Ockam.Transport.TCP.RecoverableClient

  ## Local examole
  ## Create filter and shuffle forwarders
  ## Run reliable delivery channel over filter and shuffle
  ## Wrap reliable channel into index ordering channel to deduplicate messages
  ## Send ping-pong through this combined channel
  def local() do
    ## Intermediate
    {:ok, filter} = Filter.create()
    {:ok, shuffle} = Shuffle.create()

    ## Pong
    {:ok, resend_spawner} =
      PipeChannel.Spawner.create(
        responder_options: [pipe_mods: ResendPipe, sender_options: [confirm_timeout: 200]]
      )

    {:ok, ord_spawner} = PipeChannel.Spawner.create(responder_options: [pipe_mods: IndexPipe])
    {:ok, pong} = Pong.create(delay: 500)

    ## Create resend channel through filter and shuffle
    {:ok, resend_channel} =
      PipeChannel.Initiator.create(
        pipe_mods: ResendPipe,
        spawner_route: [filter, shuffle, resend_spawner],
        sender_options: [confirm_timeout: 200]
      )

    {:ok, ord_channel} =
      PipeChannel.Initiator.create(
        pipe_mods: IndexPipe,
        spawner_route: [resend_channel, ord_spawner]
      )

    {:ok, ping} = Ping.create(delay: 500)

    ## Start ping-pong
    Ockam.Router.route(%{
      onward_route: [ord_channel, pong],
      return_route: [ping],
      payload: "0"
    })
  end

  def hub_responder() do
    Ockam.Transport.TCP.start()

    {:ok, "pong"} = Pong.create(address: "pong", delay: 500)

    {:ok, client} = RecoverableClient.create(destination: {"localhost", 4000})

    {:ok, _subscription} =
      PubSubSubscriber.create(
        pub_sub_route: [client, "pub_sub_service"],
        name: "responder",
        topic: "responder"
      )

    {:ok, "resend_receiver"} = ResendPipe.receiver().create(address: "resend_receiver")

    {:ok, "resend_spawner"} =
      PipeChannel.Spawner.create(
        address: "resend_spawner",
        responder_options: [
          pipe_mods: ResendPipe,
          sender_options: [
            confirm_timeout: 200,
            receiver_route: [client, "pub_sub_t_initiator", "resend_receiver"]
          ]
        ]
      )

    {:ok, "ord_spawner"} =
      PipeChannel.Spawner.create(
        address: "ord_spawner",
        responder_options: [pipe_mods: IndexPipe]
      )
  end

  def hub_initiator() do
    {:ok, "ping"} = Ping.create(address: "ping", delay: 500)

    {:ok, client} = RecoverableClient.create(destination: {"localhost", 4000})

    {:ok, _subscription} =
      PubSubSubscriber.create(
        pub_sub_route: [client, "pub_sub_service"],
        name: "initiator",
        topic: "initiator"
      )

    {:ok, "resend_receiver"} = ResendPipe.receiver().create(address: "resend_receiver")

    {:ok, resend_channel} =
      PipeChannel.Initiator.create(
        pipe_mods: ResendPipe,
        spawner_route: [client, "pub_sub_t_responder", "resend_spawner"],
        sender_options: [
          confirm_timeout: 200,
          receiver_route: [client, "pub_sub_t_responder", "resend_receiver"]
        ]
      )

    {:ok, ord_channel} =
      PipeChannel.Initiator.create(
        pipe_mods: IndexPipe,
        spawner_route: [resend_channel, "ord_spawner"]
      )

    ## Start ping-pong
    Ockam.Router.route(%{
      onward_route: [ord_channel, "pong"],
      return_route: ["ping"],
      payload: "0"
    })
  end
end
