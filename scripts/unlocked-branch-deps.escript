#!/usr/bin/env escript
%% Prints, one per line, the deps in ./rebar.config (any profile) that track a
%% git branch and that ./rebar.lock does not pin to a commit.
-mode(compile).

main(_) ->
    Locked = locked_names("rebar.lock"),
    Names = lists:usort([
        atom_to_list(Name)
     || Dep <- config_deps("rebar.config"),
        {Name, Source} <- dep_source(Dep),
        tracks_branch(Source)
    ]),
    [io:format("~ts~n", [Name]) || Name <- Names, not lists:member(Name, Locked)],
    ok.

config_deps(File) ->
    case file:consult(File) of
        {ok, Config} ->
            Profiles = [
                Opts
             || {profiles, Ps} <- Config, is_list(Ps), {_, Opts} <- Ps, is_list(Opts)
            ],
            [
                Dep
             || Opts <- [Config | Profiles], {deps, Deps} <- Opts, is_list(Deps), Dep <- Deps
            ];
        {error, enoent} ->
            []
    end.

dep_source({Name, Source}) when is_atom(Name), is_tuple(Source) -> [{Name, Source}];
dep_source({Name, Source, _}) when is_atom(Name), is_tuple(Source) -> [{Name, Source}];
dep_source({Name, _, Source}) when is_atom(Name), is_tuple(Source) -> [{Name, Source}];
dep_source({Name, _, Source, _}) when is_atom(Name), is_tuple(Source) -> [{Name, Source}];
dep_source(_) -> [].

tracks_branch({git, _Url}) -> true;
tracks_branch({git, _Url, ""}) -> true;
tracks_branch({git, _Url, {branch, _}}) -> true;
tracks_branch({git_subdir, _Url, {branch, _}, _Dir}) -> true;
tracks_branch(_) -> false.

locked_names(File) ->
    case file:consult(File) of
        {ok, [{_Vsn, Deps} | _]} when is_list(Deps) -> lock_entry_names(Deps);
        {ok, [Deps | _]} when is_list(Deps) -> lock_entry_names(Deps);
        {ok, []} -> [];
        {error, enoent} -> []
    end.

lock_entry_names(Deps) ->
    [unicode:characters_to_list(Name) || {Name, _, _} <- Deps, is_binary(Name)] ++
        [atom_to_list(Name) || {Name, _, _} <- Deps, is_atom(Name)].
