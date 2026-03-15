-module(fixture_SUITE).

-export([all/0, hello_test/1]).

all() -> [hello_test].

hello_test(_Config) ->
    world = fixture:hello().
