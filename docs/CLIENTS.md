# External clients

`sf-q3-8flash` does not ship an agent binary. Use an OpenAI-, Responses-, or
Anthropic-compatible client against the local server.

```sh
./sf-q3-8flash-server --ctx 32768
```

The default base URL is `http://127.0.0.1:8004`; an arbitrary local API key is
usually sufficient. Select one of the aliases returned by `/v1/models`, such as
`qwen3.8-flash-next`.

For coding agents, disable provider-side prompt caching and compaction unless
the client requires them: the server owns live and disk KV reuse. Enable vision
in the client only when the server was started with the Qwen projector. Keep
server traces private because prompts and tool arguments may contain secrets.
