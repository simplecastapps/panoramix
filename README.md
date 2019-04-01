# ElixirDruid
=====
[![Build Status](https://travis-ci.com/GameAnalytics/elixir_druid.svg?token=7iC72mSUZcJMSAvPBsAL&branch=master)](https://travis-ci.com/GameAnalytics/elixir_druid)

An open-source client library for sending requests to [Apache Druid][druid] from applications written in Elixir. The project uses [HTTPoison][httpoison] as an HTTP client for sending queries.

[druid]: http://druid.io/
[httpoison]: https://github.com/edgurgel/httpoison

## Getting Started

Add ElixirDruid as a dependency to your project.

[//]: # (TODO - Replace GitHub dep with Hex.pm below)

```elixir
defp deps do
  [
    {:elixir_druid, github: "GameAnalytics/elixir_druid"}
  ]
end
```

## Configuration 

ElixirDruid requires a Druid Broker profile to be defined in the configuration of your application.

```elixir
config :elixir_druid,
  request_timeout: 120_000,
  query_priority:  0,
  broker_profiles: [
    default: [
      base_url:       "https://druid-broker-host:9088",
      cacertfile:     "path/to/druid-certificate.crt",
      http_username:  "username",
      http_password:  "password"
    ]
  ]
```

* `request_timeout`: Query timeout in millis to be used in [`Context`](context-druid-doc-link) of all Druid queries. 
* `query_priority`: Priority to be used in [`Context`](context-druid-doc-link) of all Druid queries. 

[context-druid-doc-link]: http://druid.io/docs/latest/querying/query-context.html

## Usage

Build a query like this:

```elixir
use ElixirDruid

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
ElixirDruid.post_query(q, :default)
```

Where `:default` is a configuration profile pointing to your Druid server.

The default value for the profile argument is `:default`, so if you
only need a single configuration you can omit it:

```elixir
ElixirDruid.post_query(q)
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

## Troubleshooting

You can check correctness of your configuration by requesting status from Druid Broker. A successfull response will look like this.

```elixir
iex(1)> ElixirDruid.status(:default)
{:ok,
 %{
   "memory" => %{...},
   "modules" => [...],
   "version" => "0.13.0"
 }}
```

## Contributions
We'd love to accept your contributions in a form of patches, bug reports and new features! 

Before opening a pull request please make sure your changes pass all the tests. 

## License
Except as otherwise noted this software is licensed under the [Apache License, Version 2.0]((http://www.apache.org/licenses/LICENSE-2.0))

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the 
License. You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an 
"AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the 
specific language governing permissions and limitations under the License.

The code was Copyright 2018-2019 GameAnalytics and/or its affiliates. 
