defmodule Panoramix.Error do
  defexception [:message, :code]
  @type t :: %__MODULE__{}
end

defmodule Panoramix do
  @moduledoc """
  Post a query to Druid Broker or request its status.

  Use Panoramix.Query to build a query.

  ## Examples

  Build a query like this:

  ```elixir
  use Panoramix

  q = from "my_datasource",
        query_type: "timeseries",
        intervals: ["2019-03-01T00:00:00+00:00/2019-03-04T00:00:00+00:00"],
        granularity: :day,
        filter: dimensions.foo == "bar",
         aggregations: [event_count: count(),
                        unique_id_count: hyperUnique(:user_unique)]
  ```

  And then send it:

  ```elixir
  Panoramix.post_query(q, :default)
  ```

  Where `:default` is a configuration profile pointing to your Druid server.

  The default value for the profile argument is `:default`, so if you
  only need a single configuration you can omit it:

  ```elixir
  Panoramix.post_query(q)
  ```

  Response example:
  ```elixir
  {:ok,
   [
     %{
       "result" => %{
         "event_count" => 7544,
         "unique_id_count" => 43.18210933535
       },
       "timestamp" => "2019-03-01T00:00:00.000Z"
     },
     %{
       "result" => %{
         "event_count" => 1051,
         "unique_id_count" => 104.02052398847
       },
       "timestamp" => "2019-03-02T00:00:00.000Z"
     },
     %{
       "result" => %{
         "event_count" => 4591,
         "unique_id_count" => 79.19885795313
       },
       "timestamp" => "2019-03-03T00:00:00.000Z"
     }
   ]}
  ```

  To make a nested query, pass a map of the form `%{type: :query, query: inner_query}`
  as data source. For example:

  ```elixir
  use Panoramix

  inner_query = from "my_datasource",
                  query_type: "topN",
                  intervals: ["2019-03-01T00:00:00+00:00/2019-03-04T00:00:00+00:00"],
                  granularity: :day,
                  aggregations: [event_count: count()],
                  dimension: "foo",
                  metric: "event_count",
                  threshold: 100
  q = from %{type: :query, query: inner_query},
        query_type: "timeseries",
        intervals: ["2019-03-01T00:00:00+00:00/2019-03-04T00:00:00+00:00"],
        granularity: :day,
        aggregations: [foo_count: count(),
                       event_count_sum: longSum(:event_count)],
        post_aggregations: [mean_events_per_foo: aggregations.event_count_sum / aggregations.foo_count]
  ```

  To make a join query, pass a map of the form `%{type: :join, left: left, right: right,
  joinType: :INNER | :LEFT, rightPrefix: "prefix_", condition: "condition"}`. Both the left
  and the right side can be a nested query as above, `%{type: :query, query: inner_query}`,
  which will be expanded. Other join sources will be passed to Druid unchanged. For example:

  ```elixir
  use Panoramix

  from %{type: :join,
         left: "sales",
         right: %{type: :lookup, lookup: "store_to_country"},
         rightPrefix: "r.",
         condition: "store == \"r.k\"",
         joinType: :INNER},
    query_type: "groupBy",
    intervals: ["0000/3000"],
    granularity: "all",
    dimensions: [%{type: "default", outputName: "country", dimension: "r.v"}],
    aggregations: [country_revenue: longSum(:revenue)]
  ```

  You can also build a JSON query yourself by passing it as a map to
  `post_query`:

  ```elixir
  Panoramix.post_query(%{queryType: "timeBoundary", dataSource: "my_datasource"})
  ```

  To request status from Broker run
  ```elixir
  Panoramix.status(:default)
  ```

  """
  @moduledoc since: "1.0.0"

  @spec post_query(Panoramix.Query.t() | map(), atom()) ::
          {:ok, term()}
          | {:error, HTTPoison.Error.t() | Jason.DecodeError.t() | Panoramix.Error.t()}
  def post_query(query, profile \\ :default) do
    url_path = "/druid/v2"

    body =
      case query do
        %Panoramix.Query{} ->
          Panoramix.Query.to_json(query)

        _ ->
          Jason.encode!(query)
      end

    headers = [{"Content-Type", "application/json"}]

    request_and_decode(profile, :post, url_path, body, headers)
  end

  @spec post_query!(Panoramix.Query.t() | map(), atom()) :: term()
  def post_query!(query, profile \\ :default) do
    case post_query(query, profile) do
      {:ok, response} -> response
      {:error, error} -> raise error
    end
  end

  @spec status(atom) ::
          {:ok, term()}
          | {:error, HTTPoison.Error.t() | Jason.DecodeError.t() | Panoramix.Error.t()}
  def status(profile \\ :default) do
    url_path = "/status"
    body = ""
    headers = []

    request_and_decode(profile, :get, url_path, body, headers)
  end

  @spec status!(atom) :: term()
  def status!(profile \\ :default) do
    case status(profile) do
      {:ok, response} -> response
      {:error, error} -> raise error
    end
  end

  defp request_and_decode(profile, method, url_path, body, headers) do
    broker_profiles = Application.get_env(:panoramix, :broker_profiles)

    broker_profile =
      broker_profiles[profile] ||
        raise ArgumentError, "no broker profile with name #{profile}"

    url = broker_profile[:base_url] <> url_path
    options = http_options(url, broker_profile)

    with {:ok, http_response} <- HTTPoison.request(method, url, body, headers, options),
         {:ok, body} <- maybe_handle_druid_error(http_response) do
      Jason.decode(body)
    end
  end

  defp http_options(url, broker_profile) do
    ssl_options(url, broker_profile) ++ auth_options(broker_profile) ++ timeout_options()
  end

  defp ssl_options(url, broker_profile) do
    if url =~ ~r(^https://) do
      cacert_options = cacert_options(broker_profile)
      [ssl: [verify: :verify_peer, depth: 10] ++ cacert_options]
    else
      []
    end
  end

  defp cacert_options(broker_profile) do
    cond do
      cacertfile = broker_profile[:cacertfile] ->
        # The CA certificate is in a file.
        [cacertfile: cacertfile]

      cacert = broker_profile[:cacert] ->
        # The CA certificate is provided as a PEM-encoded string.
        # Need to convert it to DER.
        pem_entries = :public_key.pem_decode(cacert)
        cacerts = for {:Certificate, cert, :not_encrypted} <- pem_entries, do: cert
        [cacerts: cacerts]

      true ->
        # No CA certificate specified.
        []
    end
  end

  defp auth_options(broker_profile) do
    if broker_profile[:http_username] do
      auth = {broker_profile[:http_username], broker_profile[:http_password]}
      [hackney: [basic_auth: auth]]
    else
      []
    end
  end

  defp timeout_options() do
    # Default to 120 seconds
    request_timeout = Application.get_env(:panoramix, :request_timeout, 120_000)
    [recv_timeout: request_timeout]
  end

  defp maybe_handle_druid_error(%HTTPoison.Response{status_code: 200, body: body}) do
    {:ok, body}
  end

  defp maybe_handle_druid_error(%HTTPoison.Response{status_code: status_code, body: body}) do
    message =
      "Druid error (code #{status_code}): " <>
        case Jason.decode(body) do
          {:ok, %{"error" => _} = decoded} ->
            # Usually we'll get a JSON object from Druid with "error",
            # "errorMessage", "errorClass" and "host". Some of them
            # might be null.
            Enum.join(
              for field <- ["error", "errorMessage", "errorClass", "host"],
                  decoded[field] do
                "#{field}: #{decoded[field]}"
              end,
              " "
            )

          _ ->
            "undecodable error: " <> body
        end

    {:error, %Panoramix.Error{message: message, code: status_code}}
  end

  @doc ~S"""
  Format a date or a datetime into a format that Druid expects.

  ## Examples

      iex> Panoramix.format_time! ~D[2018-07-20]
      "2018-07-20"
      iex> Panoramix.format_time!(
      ...>   Timex.to_datetime({{2018,07,20},{1,2,3}}))
      "2018-07-20T01:02:03+00:00"
  """
  def format_time!(%DateTime{} = datetime) do
    Timex.format!(datetime, "{ISO:Extended}")
  end

  def format_time!(%Date{} = date) do
    Timex.format!(date, "{ISOdate}")
  end

  defmacro __using__(_params) do
    quote do
      import Panoramix.Query, only: [from: 2]
    end
  end
end
